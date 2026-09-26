//
// Copyright © 2026 Alexander Romanov
// CloudIntelligenceServiceTests.swift, created on 25.09.2026
//

import FactoryKit
import FactoryTesting
import Foundation
@testable import OversizeIntelligenceService
import Testing

#if canImport(FoundationModels, _version: 2)

    // MARK: - Stub transport

    final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        struct Reply: Sendable {
            let status: Int
            let headers: [String: String]
            let body: Data
        }

        private static let lock = NSLock()
        nonisolated(unsafe) private static var reply = Reply(status: 200, headers: [:], body: Data())
        nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

        static func install(_ newReply: Reply) {
            lock.withLock {
                reply = newReply
                capturedRequests = []
            }
        }

        static var requests: [URLRequest] {
            lock.withLock { capturedRequests }
        }

        override class func canInit(with _: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            var captured = request
            if captured.httpBody == nil, let stream = request.httpBodyStream {
                captured.httpBody = Self.read(stream)
            }
            let current = Self.lock.withLock {
                Self.capturedRequests.append(captured)
                return Self.reply
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: current.status,
                httpVersion: "HTTP/1.1",
                headerFields: current.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: current.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func read(_ stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }

    // MARK: - Helpers

    private func streamBody(content: String) -> Data {
        let chunk: [String: Any] = [
            "id": "chatcmpl-1",
            "model": "gpt-test",
            "choices": [["index": 0, "delta": ["role": "assistant", "content": content]]],
        ]
        let json = String(data: try! JSONSerialization.data(withJSONObject: chunk), encoding: .utf8)!
        return Data("data: \(json)\n\ndata: [DONE]\n\n".utf8)
    }

    private func streamBodyWithUsage(content: String) -> Data {
        let contentChunk: [String: Any] = [
            "id": "chatcmpl-1",
            "model": "gpt-test",
            "choices": [["index": 0, "delta": ["role": "assistant", "content": content]]],
        ]
        let usageChunk: [String: Any] = [
            "id": "chatcmpl-1",
            "model": "gpt-test",
            "choices": [],
            "usage": [
                "prompt_tokens": 1200,
                "completion_tokens": 300,
                "prompt_tokens_details": ["cached_tokens": 1024],
                "completion_tokens_details": ["reasoning_tokens": 120],
            ],
        ]
        let lines = [contentChunk, usageChunk].map { chunk in
            "data: " + String(data: try! JSONSerialization.data(withJSONObject: chunk), encoding: .utf8)! + "\n\n"
        }
        return Data((lines.joined() + "data: [DONE]\n\n").utf8)
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    private func makeService() -> IntelligenceService {
        IntelligenceService(provider: .openAI(model: "gpt-test")) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            return configuration
        }
    }

    private var intentSchema: [String: Any] { [
        "type": "object",
        "additionalProperties": false,
        "required": ["items"],
        "properties": [
            "items": [
                "type": "array",
                "maxItems": 3,
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["keyword", "intent", "relevance", "suggestion"],
                    "properties": [
                        "keyword": ["type": "string", "description": "The keyword."],
                        "intent": ["type": "string", "enum": ["feature", "brand"]],
                        "relevance": ["type": "number"],
                        "suggestion": ["type": ["string", "null"]],
                    ],
                ],
            ],
        ],
    ] }

    // MARK: - Tests

    @Suite(.container, .serialized)
    struct CloudIntelligenceServiceTests {
        init() {
            Container.shared.intelligenceServiceKeyProvider.register { { "sk-test" } }
        }

        @Test
        func plainSchemaBecomesGenerationSchema() throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            let schema = try IntelligenceJSONSchema(name: "aso_keyword_intent", schema: intentSchema)
            _ = try schema.generationSchema()
        }

        @Test
        func structuredRequestSendsStrictSchemaWithoutFrameworkExtensions() async throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            let payload = #"{"items":[{"keyword":"scanner","intent":"feature","relevance":0.9,"suggestion":null}]}"#
            StubURLProtocol.install(.init(status: 200, headers: ["Content-Type": "text/event-stream"], body: streamBody(content: payload)))

            let schema = try IntelligenceJSONSchema(name: "aso_keyword_intent", schema: intentSchema)
            let text = try await makeService().respond(
                to: "Classify",
                instructions: "Return JSON.",
                schema: schema,
                options: IntelligenceRequestOptions(model: "gpt-override", timeout: 20)
            )

            let decoded = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            let items = try #require(decoded?["items"] as? [[String: Any]])
            #expect(items.first?["keyword"] as? String == "scanner")

            let request = try #require(StubURLProtocol.requests.first)
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            let body = try #require(request.httpBody)
            let bodyText = String(data: body, encoding: .utf8) ?? ""
            #expect(!bodyText.contains("x-order"))
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["model"] as? String == "gpt-override")
            let format = try #require(object["response_format"] as? [String: Any])
            let jsonSchema = try #require(format["json_schema"] as? [String: Any])
            #expect(jsonSchema["strict"] as? Bool == true)

            let wireSchema = try #require(jsonSchema["schema"] as? [String: Any])
            let definitions = try #require(wireSchema["$defs"] as? [String: [String: Any]])
            let item = try #require(definitions.values.first { ($0["properties"] as? [String: Any])?["suggestion"] != nil })
            #expect(Set(item["required"] as? [String] ?? []) == ["keyword", "intent", "relevance", "suggestion"])
            let suggestion = try #require((item["properties"] as? [String: Any])?["suggestion"] as? [String: Any])
            let variants = try #require(suggestion["anyOf"] as? [[String: Any]])
            #expect(variants.contains { $0["type"] as? String == "null" })
        }

        @Test
        func structuredRequestSendsReasoningEffortAndCacheKeyAndReturnsUsage() async throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            let payload = #"{"items":[{"keyword":"scanner","intent":"feature","relevance":0.9,"suggestion":null}]}"#
            StubURLProtocol.install(.init(status: 200, headers: ["Content-Type": "text/event-stream"], body: streamBodyWithUsage(content: payload)))

            let schema = try IntelligenceJSONSchema(name: "aso_keyword_intent", schema: intentSchema)
            let response = try await makeService().respondStructured(
                to: "Classify",
                instructions: "Return JSON.",
                schema: schema,
                options: IntelligenceRequestOptions(reasoningEffort: .low, promptCacheKey: "intent-app")
            )

            let body = try #require(StubURLProtocol.requests.first?.httpBody)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["reasoning_effort"] as? String == "low")
            #expect(object["prompt_cache_key"] as? String == "intent-app")
            #expect(object["temperature"] == nil)
            #expect(response.usage == IntelligenceUsage(inputTokens: 1200, cachedInputTokens: 1024, outputTokens: 300, reasoningTokens: 120))
        }

        @Test
        func requestWithoutEffortOmitsReasoningFields() async throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            let payload = #"{"items":[]}"#
            StubURLProtocol.install(.init(status: 200, headers: ["Content-Type": "text/event-stream"], body: streamBody(content: payload)))

            let schema = try IntelligenceJSONSchema(name: "aso_keyword_intent", schema: intentSchema)
            _ = try await makeService().respondStructured(to: "Classify", instructions: nil, schema: schema, options: .init())

            let body = try #require(StubURLProtocol.requests.first?.httpBody)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["reasoning_effort"] == nil)
            #expect(object["prompt_cache_key"] == nil)
        }

        @Test
        func exhaustedQuotaIsNotARateLimit() async throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            let body = Data(#"{"error":{"code":"insufficient_quota","message":"You exceeded your quota"}}"#.utf8)
            StubURLProtocol.install(.init(status: 429, headers: [:], body: body))

            await #expect(throws: IntelligenceRequestError.quotaExhausted(code: "insufficient_quota")) {
                try await makeService().respond(to: "Hi", instructions: nil, options: .init())
            }
        }

        @Test
        func streamedRateLimitIsARateLimit() {
            #expect(IntelligenceRequestError.from(code: "rate_limit_exceeded", message: "Slow down") == .rateLimited(headers: [:]))
            #expect(IntelligenceRequestError.from(code: "insufficient_quota", message: "Quota") == .quotaExhausted(code: "insufficient_quota"))
        }

        @Test
        func rateLimitCarriesHeaders() async throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            let body = Data(#"{"error":{"code":"rate_limit_exceeded","message":"Slow down"}}"#.utf8)
            StubURLProtocol.install(.init(status: 429, headers: ["Retry-After": "7"], body: body))

            do {
                _ = try await makeService().respond(to: "Hi", instructions: nil, options: .init())
                Issue.record("Expected a rate limit error")
            } catch let IntelligenceRequestError.rateLimited(headers) {
                #expect(headers["retry-after"] == "7")
            }
        }

        @Test
        func unauthorizedIsClassified() async throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            StubURLProtocol.install(.init(status: 401, headers: [:], body: Data(#"{"error":{"message":"bad key"}}"#.utf8)))

            await #expect(throws: IntelligenceRequestError.unauthorized(status: 401)) {
                try await makeService().respond(to: "Hi", instructions: nil, options: .init())
            }
        }

        @Test
        func missingKeyFailsBeforeAnyRequest() async throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            Container.shared.intelligenceServiceKeyProvider.register { { nil } }
            StubURLProtocol.install(.init(status: 200, headers: [:], body: Data()))

            await #expect(throws: IntelligenceRequestError.missingAPIKey) {
                try await makeService().respond(to: "Hi", instructions: nil, options: .init())
            }
            #expect(StubURLProtocol.requests.isEmpty)
        }
    }
#endif
