//
// Copyright © 2025 Alexander Romanov
// IntelligenceService.swift, created on 13.11.2025
//

import FactoryKit
import Foundation
import OversizeCore
import OversizeServices

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - IntelligenceServiceKeyProvider

/// How the OpenAI token reaches a request. By default it is read from the Keychain on every call,
/// so a key saved mid-session is picked up, then from `OPENAI_API_KEY`, which only the Dev scheme
/// and command-line consumers set; tests register their own provider.
public typealias IntelligenceServiceKeyProvider = @Sendable () -> String?

public extension Container {
    var intelligenceServiceKeyProvider: Factory<IntelligenceServiceKeyProvider> {
        self {
            {
                (try? Keychain.openAIAPIKey.string(forKey: OpenAIAPIKey.keychainKey))
                    ?? environmentKey("OPENAI_API_KEY")
            }
        }
    }
}

private func environmentKey(_ name: String) -> String? {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
    return value
}

// MARK: - IntelligenceServiceProtocol

public protocol IntelligenceServiceProtocol: Sendable {
    var isAvailable: Bool { get }

    func respond(
        to prompt: String,
        instructions: String?,
        options: IntelligenceRequestOptions
    ) async throws -> String

    /// Returns the model's answer as JSON text that conforms to `schema`, with the token usage
    /// the provider reported for it.
    func respondStructured(
        to prompt: String,
        instructions: String?,
        schema: IntelligenceJSONSchema,
        options: IntelligenceRequestOptions
    ) async throws -> IntelligenceStructuredResponse
}

public extension IntelligenceServiceProtocol {
    /// Returns the model's answer as JSON text that conforms to `schema`.
    func respond(
        to prompt: String,
        instructions: String?,
        schema: IntelligenceJSONSchema,
        options: IntelligenceRequestOptions
    ) async throws -> String {
        try await respondStructured(to: prompt, instructions: instructions, schema: schema, options: options).text
    }

    func respond(to prompt: String) async throws -> String {
        try await respond(to: prompt, instructions: nil, options: IntelligenceRequestOptions())
    }

    func respond(to prompt: String, instructions: String?) async throws -> String {
        try await respond(to: prompt, instructions: instructions, options: IntelligenceRequestOptions())
    }
}

// MARK: - IntelligenceProvider

public enum IntelligenceProvider: Sendable, Equatable {
    case onDevice
    case openAI(model: String)
}

// MARK: - IntelligenceAvailability

public enum IntelligenceAvailability {
    /// Cloud models run through the Foundation Models server-side language model API, which
    /// first ships in OS 27. Screens that depend on them stay hidden below it.
    public static var isCloudSupported: Bool {
        #if canImport(FoundationModels, _version: 2)
            if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                return true
            }
        #endif
        return false
    }
}

// MARK: - IntelligenceService

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public final class IntelligenceService: IntelligenceServiceProtocol {
        public static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!

        private let provider: IntelligenceProvider
        private let baseURL: URL
        private let sessionConfiguration: @Sendable () -> URLSessionConfiguration

        public init(
            provider: IntelligenceProvider = .onDevice,
            baseURL: URL = IntelligenceService.openAIBaseURL,
            sessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }
        ) {
            self.provider = provider
            self.baseURL = baseURL
            self.sessionConfiguration = sessionConfiguration
        }

        private static func openAIAPIKey() -> String? {
            guard let key = Container.shared.intelligenceServiceKeyProvider()(), !key.isEmpty else { return nil }
            return key
        }

        public var isAvailable: Bool {
            #if canImport(FoundationModels)
                switch provider {
                case .onDevice:
                    return SystemLanguageModel.default.isAvailable
                case .openAI:
                    return IntelligenceAvailability.isCloudSupported && Self.openAIAPIKey() != nil
                }
            #else
                return false
            #endif
        }

        public func respond(
            to prompt: String,
            instructions: String?,
            options: IntelligenceRequestOptions
        ) async throws -> String {
            let session = try makeSession(instructions: instructions, options: options)
            do {
                return try await session.respond(to: prompt, options: options.generationOptions).content
            } catch {
                throw Self.mapped(error)
            }
        }

        public func respondStructured(
            to prompt: String,
            instructions: String?,
            schema: IntelligenceJSONSchema,
            options: IntelligenceRequestOptions
        ) async throws -> IntelligenceStructuredResponse {
            let generationSchema: GenerationSchema
            do {
                generationSchema = try schema.generationSchema()
            } catch {
                throw IntelligenceRequestError.invalidSchema(name: schema.name)
            }
            let session = try makeSession(instructions: instructions, options: options)
            do {
                let response = try await session.respond(
                    to: prompt,
                    schema: generationSchema,
                    options: options.generationOptions
                )
                return IntelligenceStructuredResponse(text: response.content.jsonString, usage: Self.usage(of: response))
            } catch {
                throw Self.mapped(error)
            }
        }

        // MARK: - Session

        private func makeSession(instructions: String?, options: IntelligenceRequestOptions) throws -> LanguageModelSession {
            switch provider {
            case .onDevice:
                guard SystemLanguageModel.default.isAvailable else {
                    throw IntelligenceError.modelNotAvailable
                }
                return LanguageModelSession(instructions: instructions ?? "")
            case let .openAI(defaultModel):
                #if canImport(FoundationModels, _version: 2)
                    guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else {
                        throw IntelligenceError.unsupportedPlatform
                    }
                    guard let apiKey = Self.openAIAPIKey() else {
                        throw IntelligenceRequestError.missingAPIKey
                    }
                    let configuration = sessionConfiguration()
                    if let timeout = options.timeout {
                        configuration.timeoutIntervalForRequest = timeout
                        configuration.timeoutIntervalForResource = timeout * 2
                    }
                    let model = ChatCompletionsLanguageModel(
                        name: options.model ?? defaultModel,
                        url: baseURL,
                        additionalHeaders: ["Authorization": "Bearer \(apiKey)"],
                        reasoningEffort: options.reasoningEffort?.rawValue,
                        promptCacheKey: options.promptCacheKey,
                        urlSessionConfiguration: configuration
                    )
                    return LanguageModelSession(model: model, instructions: instructions ?? "")
                #else
                    throw IntelligenceError.unsupportedPlatform
                #endif
            }
        }

        // MARK: - Usage

        private static func usage(of response: LanguageModelSession.Response<GeneratedContent>) -> IntelligenceUsage? {
            #if canImport(FoundationModels, _version: 2)
                if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                    let usage = response.usage
                    guard usage.input.totalTokenCount > 0 || usage.output.totalTokenCount > 0 else { return nil }
                    return IntelligenceUsage(
                        inputTokens: usage.input.totalTokenCount,
                        cachedInputTokens: usage.input.cachedTokenCount,
                        outputTokens: usage.output.totalTokenCount,
                        reasoningTokens: usage.output.reasoningTokenCount
                    )
                }
            #endif
            return nil
        }

        // MARK: - Errors

        private static func mapped(_ error: Error) -> Error {
            #if canImport(FoundationModels, _version: 2)
                if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                    if let requestError = error as? ChatCompletionsLanguageModel.RequestError {
                        return IntelligenceRequestError(requestError)
                    }
                    if let apiError = error as? ChatCompletionsLanguageModel.APIError {
                        return IntelligenceRequestError(apiError)
                    }
                }
            #endif
            if let generationError = error as? LanguageModelSession.GenerationError {
                switch generationError {
                case .decodingFailure:
                    return IntelligenceRequestError.decoding
                case .rateLimited:
                    return IntelligenceRequestError.rateLimited(headers: [:])
                default:
                    return generationError
                }
            }
            return error
        }
    }
#endif
