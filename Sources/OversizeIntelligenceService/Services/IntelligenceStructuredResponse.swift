//
// Copyright © 2026 Alexander Romanov
// IntelligenceStructuredResponse.swift, created on 25.09.2026
//

import Foundation

public struct IntelligenceUsage: Sendable, Equatable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningTokens: Int

    public init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int, reasoningTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
    }
}

public struct IntelligenceStructuredResponse: Sendable, Equatable {
    /// The answer as JSON text that conforms to the request's schema.
    public let text: String
    /// Token usage reported by the provider; `nil` when it reports none.
    public let usage: IntelligenceUsage?

    public init(text: String, usage: IntelligenceUsage?) {
        self.text = text
        self.usage = usage
    }
}
