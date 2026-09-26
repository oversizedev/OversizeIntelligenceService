//
// Copyright © 2026 Alexander Romanov
// IntelligenceRequestOptions.swift, created on 25.09.2026
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

public enum IntelligenceReasoningEffort: String, Sendable, Equatable, CaseIterable {
    case none
    case low
    case medium
    case high
}

public struct IntelligenceRequestOptions: Sendable, Equatable {
    /// Overrides the provider's model for this request.
    public var model: String?
    public var temperature: Double?
    public var topProbability: Double?
    public var maximumResponseTokens: Int?
    /// Idle timeout of the request; the whole exchange may take twice as long.
    public var timeout: TimeInterval?
    /// How much a reasoning model thinks before answering; `nil` keeps the model's default.
    public var reasoningEffort: IntelligenceReasoningEffort?
    /// Groups requests that share a prompt prefix so the provider serves it from its cache.
    public var promptCacheKey: String?

    public init(
        model: String? = nil,
        temperature: Double? = nil,
        topProbability: Double? = nil,
        maximumResponseTokens: Int? = nil,
        timeout: TimeInterval? = nil,
        reasoningEffort: IntelligenceReasoningEffort? = nil,
        promptCacheKey: String? = nil
    ) {
        self.model = model
        self.temperature = temperature
        self.topProbability = topProbability
        self.maximumResponseTokens = maximumResponseTokens
        self.timeout = timeout
        self.reasoningEffort = reasoningEffort
        self.promptCacheKey = promptCacheKey
    }
}

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    extension IntelligenceRequestOptions {
        var generationOptions: GenerationOptions {
            GenerationOptions(
                samplingMode: topProbability.map { GenerationOptions.SamplingMode.random(probabilityThreshold: $0) },
                temperature: temperature,
                maximumResponseTokens: maximumResponseTokens
            )
        }
    }
#endif
