//
// Copyright © 2026 Alexander Romanov
// IntelligenceRequestError.swift, created on 25.09.2026
//

import Foundation

/// Why a cloud request failed, in a shape callers can classify without reading HTTP themselves.
/// Transport failures are passed through as the original `URLError`.
public enum IntelligenceRequestError: Error, Sendable, Equatable {
    case missingAPIKey
    case unauthorized(status: Int)
    case rateLimited(headers: [String: String])
    /// A permanent billing state. OpenAI reports it as HTTP 429 as well, so it must not be
    /// retried like a rate limit.
    case quotaExhausted(code: String)
    case status(Int, message: String?)
    case api(code: String?, message: String)
    case invalidSchema(name: String)
    case decoding

    public static let permanentBillingCodes: Set<String> = [
        "insufficient_quota",
        "credit_balance_exhausted",
        "billing_not_active",
        "billing_hard_limit_reached",
        "access_terminated",
    ]

    public var isTransient: Bool {
        switch self {
        case .rateLimited:
            true
        case let .status(code, _):
            code == 408 || (500 ... 599).contains(code)
        case .missingAPIKey, .unauthorized, .quotaExhausted, .api, .invalidSchema, .decoding:
            false
        }
    }

    static func from(status: Int, body: Data, headers: [String: String]) -> IntelligenceRequestError {
        let envelope = ErrorEnvelope.decode(body)
        if let code = envelope?.code, permanentBillingCodes.contains(code) {
            return .quotaExhausted(code: code)
        }
        switch status {
        case 401, 403:
            return .unauthorized(status: status)
        case 429:
            return .rateLimited(headers: headers)
        default:
            return .status(status, message: envelope?.summary ?? String(data: body.prefix(160), encoding: .utf8))
        }
    }

    static func from(code: String?, message: String) -> IntelligenceRequestError {
        if let code, permanentBillingCodes.contains(code) {
            return .quotaExhausted(code: code)
        }
        return .api(code: code, message: message)
    }
}

private struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String?
        let message: String?

        var summary: String {
            [code, message.map { String($0.prefix(120)) }].compactMap(\.self).joined(separator: ": ")
        }
    }

    let error: Body

    static func decode(_ data: Data) -> Body? {
        try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error
    }
}

#if canImport(FoundationModels, _version: 2)
    import FoundationModels

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
    @available(tvOS, unavailable)
    extension IntelligenceRequestError {
        init(_ error: ChatCompletionsLanguageModel.RequestError) {
            switch error {
            case let .httpError(statusCode, data, headers):
                self = .from(status: statusCode, body: data, headers: headers)
            case .invalidStreamData:
                self = .decoding
            case let .invalidRequest(description):
                self = .api(code: nil, message: description)
            }
        }

        init(_ error: ChatCompletionsLanguageModel.APIError) {
            self = .from(code: error.code, message: error.message)
        }
    }
#endif
