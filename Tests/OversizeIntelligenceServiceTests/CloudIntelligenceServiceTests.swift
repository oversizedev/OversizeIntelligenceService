//
// Copyright © 2026 Alexander Romanov
// CloudIntelligenceServiceTests.swift, created on 25.09.2026
//

import CoreGraphics
import FactoryKit
import FactoryTesting
import Foundation
import ImageIO
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
        private nonisolated(unsafe) static var reply = Reply(status: 200, headers: [:], body: Data())
        private nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

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

    private func writeTestImage(width: Int, height: Int) throws -> URL {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0.4, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    private func makeService() -> IntelligenceService {
        IntelligenceService(provider: .openAI(model: "gpt-test")) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            return configuration
        }
    }

    private var intentSchema: [String: Any] {
        [
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
        ]
    }

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
        func imagesFollowTheirLabelsInTheUserMessage() async throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            StubURLProtocol.install(.init(status: 200, headers: ["Content-Type": "text/event-stream"], body: streamBody(content: #"{"items":[]}"#)))
            let imageURL = try writeTestImage(width: 1290, height: 2796)
            defer { try? FileManager.default.removeItem(at: imageURL) }

            let schema = try IntelligenceJSONSchema(name: "aso_keyword_intent", schema: intentSchema)
            _ = try await makeService().respondStructured(
                to: "Describe",
                images: [IntelligenceImage(label: "1", url: imageURL)],
                instructions: nil,
                schema: schema,
                options: .init()
            )

            let body = try #require(StubURLProtocol.requests.first?.httpBody)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try #require(object["messages"] as? [[String: Any]])
            let userContent = try #require(messages.last { $0["role"] as? String == "user" }?["content"] as? [[String: Any]])
            let texts = userContent.compactMap { $0["text"] as? String }
            #expect(texts.contains { $0.contains("Describe") })
            let headerIndex = try #require(userContent.firstIndex { ($0["text"] as? String)?.contains("Image 1:") == true })
            let imageIndex = try #require(userContent.firstIndex { $0["image_url"] != nil })
            #expect(headerIndex < imageIndex)
            let imagePart = try #require(userContent[imageIndex]["image_url"] as? [String: Any])
            #expect((imagePart["url"] as? String)?.hasPrefix("data:image/jpeg;base64,") == true)
        }

        @Test
        func unreadableImageFailsBeforeAnyRequest() async throws {
            guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
            StubURLProtocol.install(.init(status: 200, headers: [:], body: Data()))
            let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")

            let schema = try IntelligenceJSONSchema(name: "aso_keyword_intent", schema: intentSchema)
            await #expect(throws: IntelligenceImageError.unreadable(label: "2")) {
                try await makeService().respondStructured(
                    to: "Describe",
                    images: [IntelligenceImage(label: "2", url: missingURL)],
                    instructions: nil,
                    schema: schema,
                    options: .init()
                )
            }
            #expect(StubURLProtocol.requests.isEmpty)
        }

        @Test
        func thumbnailFitsTheMaximumSide() throws {
            let imageURL = try writeTestImage(width: 1290, height: 2796)
            defer { try? FileManager.default.removeItem(at: imageURL) }

            let thumbnail = try IntelligenceImage(label: "1", url: imageURL, maxPixelSize: 512).thumbnail()

            #expect(max(thumbnail.width, thumbnail.height) == 512)
            #expect(thumbnail.width < thumbnail.height)
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
