//
// Copyright © 2026 Alexander Romanov
// IntelligenceRequestOptions.swift, created on 25.09.2026
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

public struct IntelligenceRequestOptions: Sendable, Equatable {
    /// Overrides the provider's model for this request.
    public var model: String?
    public var temperature: Double?
    public var topProbability: Double?
    public var maximumResponseTokens: Int?
    /// Idle timeout of the request; the whole exchange may take twice as long.
    public var timeout: TimeInterval?

    public init(
        model: String? = nil,
        temperature: Double? = nil,
        topProbability: Double? = nil,
        maximumResponseTokens: Int? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.model = model
        self.temperature = temperature
        self.topProbability = topProbability
        self.maximumResponseTokens = maximumResponseTokens
        self.timeout = timeout
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
