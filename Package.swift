// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let commonDependencies: [PackageDescription.Package.Dependency] = [
    .package(url: "https://github.com/hmlongco/Factory.git", .upToNextMajor(from: .init(3, 0, 2))),
]

let package = Package(
    name: "OversizeIntelligenceService",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "OversizeIntelligenceService",
            targets: ["OversizeIntelligenceService"]
        ),
    ],
    dependencies: commonDependencies,
    targets: [
        .target(
            name: "OversizeIntelligenceService",
            dependencies: [
                .product(name: "FactoryKit", package: "Factory"),
            ]
        ),
    ]
)
