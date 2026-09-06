//
// Copyright © 2025 Alexander Romanov
// IntelligenceService.swift, created on 13.11.2025
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: IntelligenceServiceProtocol

public protocol IntelligenceServiceProtocol: Sendable {
    var isAvailable: Bool { get }
    func respond(to prompt: String, instructions: String?) async throws -> String
}

public extension IntelligenceServiceProtocol {
    func respond(to prompt: String) async throws -> String {
        try await respond(to: prompt, instructions: nil)
    }
}

// MARK: IntelligenceProvider

public enum IntelligenceProvider: Sendable {
    case onDevice
    case openAI(model: String)

    public static var openAI: IntelligenceProvider {
        .openAI(model: "gpt-4o-mini")
    }
}

// MARK: IntelligenceService

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public final class IntelligenceService: IntelligenceServiceProtocol, @unchecked Sendable {
    private let provider: IntelligenceProvider

    public init(provider: IntelligenceProvider = .onDevice) {
        self.provider = provider
    }

    private static func openAIAPIKey() -> String? {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !key.isEmpty
        else { return nil }
        return key
    }

    public var isAvailable: Bool {
        #if canImport(FoundationModels)
            switch provider {
            case .onDevice:
                return SystemLanguageModel.default.isAvailable
            case .openAI:
                #if canImport(FoundationModels, _version: 2)
                    guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return false }
                    return Self.openAIAPIKey() != nil
                #else
                    return false
                #endif
            }
        #else
            return false
        #endif
    }

    public func respond(to prompt: String, instructions: String? = nil) async throws -> String {
        #if canImport(FoundationModels)
            switch provider {
            case .onDevice:
                return try await respondOnDevice(to: prompt, instructions: instructions)
            case let .openAI(model):
                #if canImport(FoundationModels, _version: 2)
                    return try await respondViaOpenAI(to: prompt, instructions: instructions, model: model)
                #else
                    throw IntelligenceError.unsupportedPlatform
                #endif
            }
        #else
            throw IntelligenceError.unsupportedPlatform
        #endif
    }

    #if canImport(FoundationModels)
        private func respondOnDevice(to prompt: String, instructions: String?) async throws -> String {
            guard SystemLanguageModel.default.isAvailable else {
                throw IntelligenceError.modelNotAvailable
            }

            let session = LanguageModelSession(instructions: instructions ?? "")
            let response = try await session.respond(to: prompt)
            return response.content
        }

        #if canImport(FoundationModels, _version: 2)
            private func respondViaOpenAI(to prompt: String, instructions: String?, model: String) async throws -> String {
                guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else {
                    throw IntelligenceError.unsupportedPlatform
                }
                guard let apiKey = Self.openAIAPIKey() else {
                    throw IntelligenceError.modelNotAvailable
                }

                let languageModel = OpenAILanguageModel(apiKey: apiKey, model: model)
                let session = LanguageModelSession(model: languageModel, instructions: instructions ?? "")
                let response = try await session.respond(to: prompt)
                return response.content
            }
        #endif
    #endif
}

// MARK: - Error

public enum IntelligenceError: Error, Sendable {
    case unsupportedPlatform
    case modelNotAvailable
}
