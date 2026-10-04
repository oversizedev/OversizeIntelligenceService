//
// Copyright © 2026 Alexander Romanov
// OpenAIAPIKey.swift, created on 03.10.2026
//

import Foundation
import OversizeServices

public enum OpenAIAPIKey {
    public static let keychainService = "AppConnector.OpenAI"
    public static let keychainKey = "apiKey"
}

public extension Keychain {
    static let openAIAPIKey = Keychain(
        service: OpenAIAPIKey.keychainService,
        synchronizable: true,
        useDataProtectionKeychain: true,
    )
}
