//
// Copyright © 2026 Alexander Romanov
// ServiceRegistering.swift, created on 28.01.2026
//

import FactoryKit
import Foundation

#if canImport(FoundationModels)
    public extension Container {
        @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        var intelligenceService: Factory<IntelligenceServiceProtocol> {
            self { IntelligenceService() }
        }

        /// OpenAI through the Foundation Models server-side model API. Requests fail with
        /// `IntelligenceError.unsupportedPlatform` below OS 27; the key is read on every request.
        @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        var cloudIntelligenceService: Factory<IntelligenceServiceProtocol> {
            self { IntelligenceService(provider: .openAI(model: IntelligenceModelDefaults.openAIModel)) }
        }
    }
#endif

public enum IntelligenceModelDefaults {
    public static let openAIModel = "gpt-6-luna"
}
