//
// Copyright © 2026 Alexander Romanov
// ServiceRegistering.swift, created on 28.01.2026
//

import FactoryKit
import Foundation

public extension Container {
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    var intelligenceService: Factory<IntelligenceServiceProtocol> {
        self { IntelligenceService() }
    }
}
