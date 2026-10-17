//
// Copyright © 2026 Alexander Romanov
// IntelligenceImage.swift, created on 16.10.2026
//

import Foundation

#if canImport(ImageIO)
    import CoreGraphics
    import ImageIO
#endif

// MARK: - IntelligenceImage

public struct IntelligenceImage: Sendable, Equatable {
    public static let defaultMaxPixelSize = 1024

    public let label: String
    public let url: URL
    public let maxPixelSize: Int

    public init(label: String, url: URL, maxPixelSize: Int = IntelligenceImage.defaultMaxPixelSize) {
        self.label = label
        self.url = url
        self.maxPixelSize = maxPixelSize
    }

    var promptHeader: String {
        "Image \(label):"
    }
}

// MARK: - IntelligenceImageError

public enum IntelligenceImageError: LocalizedError, Sendable, Equatable {
    case unreadable(label: String)

    public var errorDescription: String? {
        switch self {
        case let .unreadable(label):
            "Image \(label) could not be read."
        }
    }
}

// MARK: - Loading

#if canImport(ImageIO)
    extension IntelligenceImage {
        func thumbnail() throws -> CGImage {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
                throw IntelligenceImageError.unreadable(label: label)
            }
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
                throw IntelligenceImageError.unreadable(label: label)
            }
            return image
        }
    }
#endif
