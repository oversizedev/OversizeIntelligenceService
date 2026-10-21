//
// Copyright © 2026 Alexander Romanov
// OpenAIAPIKey.swift, created on 03.10.2026
//

import Foundation

public enum OpenAIAPIKey {
    public static let environmentVariable = "OPENAI_API_KEY"

    public static var environmentValue: String? {
        guard let value = ProcessInfo.processInfo.environment[environmentVariable], !value.isEmpty else { return nil }
        return value
    }
}
