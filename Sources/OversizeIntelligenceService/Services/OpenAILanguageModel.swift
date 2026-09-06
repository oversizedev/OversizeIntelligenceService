//
// Copyright © 2026 Alexander Romanov
// OpenAILanguageModel.swift
//

import Foundation

#if canImport(FoundationModels, _version: 2)
    import FoundationModels

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    @available(tvOS, unavailable)
    public struct OpenAILanguageModel: LanguageModel {
        public let apiKey: String
        public let model: String
        public let baseURL: URL

        public init(
            apiKey: String,
            model: String = "gpt-4o-mini",
            baseURL: URL = URL(string: "https://api.openai.com/v1/chat/completions")!
        ) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
        }

        public var capabilities: LanguageModelCapabilities {
            LanguageModelCapabilities([])
        }

        public var executorConfiguration: Executor.Configuration {
            Executor.Configuration(apiKey: apiKey, model: model, baseURL: baseURL)
        }

        public struct Executor: LanguageModelExecutor {
            public struct Configuration: Hashable, Sendable {
                public let apiKey: String
                public let model: String
                public let baseURL: URL
            }

            public typealias Model = OpenAILanguageModel

            private let configuration: Configuration
            private let urlSession: URLSession

            public init(configuration: Configuration) throws {
                self.configuration = configuration
                urlSession = URLSession(configuration: .default)
            }

            public func prewarm(model _: OpenAILanguageModel, transcript _: Transcript) {}

            public func respond(
                to request: LanguageModelExecutorGenerationRequest,
                model _: OpenAILanguageModel,
                streamingInto channel: LanguageModelExecutorGenerationChannel
            ) async throws {
                let messages = Self.chatMessages(from: request.transcript)

                var urlRequest = URLRequest(url: configuration.baseURL)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.timeoutInterval = 60

                let body = ChatCompletionsRequest(
                    model: configuration.model,
                    messages: messages,
                    temperature: request.generationOptions.temperature,
                    maxTokens: request.generationOptions.maximumResponseTokens
                )
                urlRequest.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await urlSession.data(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw OpenAILanguageModelError.http(status: status)
                }

                let decoded: ChatCompletionsResponse
                do {
                    decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
                } catch {
                    throw OpenAILanguageModelError.decoding
                }

                guard let content = decoded.choices.first?.message.content else {
                    throw OpenAILanguageModelError.emptyResponse
                }

                await channel.send(.response(action: .appendText(
                    content,
                    tokenCount: decoded.usage?.completionTokens ?? 0
                )))

                if let usage = decoded.usage {
                    await channel.send(.response(action: .updateUsage(
                        input: .init(totalTokenCount: usage.promptTokens, cachedTokenCount: 0),
                        output: .init(totalTokenCount: usage.completionTokens, reasoningTokenCount: 0)
                    )))
                }
            }

            private static func chatMessages(from transcript: Transcript) -> [ChatMessage] {
                var messages: [ChatMessage] = []
                for entry in transcript {
                    switch entry {
                    case let .instructions(instructions):
                        let content = text(from: instructions.segments)
                        if !content.isEmpty {
                            messages.append(ChatMessage(role: "system", content: content))
                        }
                    case let .prompt(prompt):
                        let content = text(from: prompt.segments)
                        if !content.isEmpty {
                            messages.append(ChatMessage(role: "user", content: content))
                        }
                    case let .response(response):
                        let content = text(from: response.segments)
                        if !content.isEmpty {
                            messages.append(ChatMessage(role: "assistant", content: content))
                        }
                    default:
                        continue
                    }
                }
                return messages
            }

            private static func text(from segments: [Transcript.Segment]) -> String {
                segments
                    .compactMap { segment -> String? in
                        guard case let .text(textSegment) = segment else { return nil }
                        return textSegment.content
                    }
                    .joined(separator: "\n")
            }
        }
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    @available(tvOS, unavailable)
    public enum OpenAILanguageModelError: Error, Sendable {
        case http(status: Int)
        case decoding
        case emptyResponse
    }

    private struct ChatMessage: Codable, Sendable {
        let role: String
        let content: String
    }

    private struct ChatCompletionsRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double?
        let maxTokens: Int?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
        }
    }

    private struct ChatCompletionsResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        struct Usage: Decodable {
            let promptTokens: Int
            let completionTokens: Int

            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
            }
        }

        let choices: [Choice]
        let usage: Usage?
    }
#endif
