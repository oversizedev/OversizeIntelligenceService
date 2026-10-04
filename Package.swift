// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let commonDependencies: [PackageDescription.Package.Dependency] = [
    .package(url: "https://github.com/hmlongco/Factory.git", .upToNextMajor(from: .init(3, 0, 2))),
]

let remoteDependencies: [PackageDescription.Package.Dependency] = commonDependencies + [
    .package(url: "https://github.com/oversizedev/OversizeCore.git", .upToNextMajor(from: "1.18.0")),
    .package(url: "https://github.com/oversizedev/OversizeServices.git", .upToNextMajor(from: "1.27.0")),
]

let localDependencies: [PackageDescription.Package.Dependency] = commonDependencies + [
    .package(name: "OversizeCore", path: "../OversizeCore"),
    .package(name: "OversizeServices", path: "../OversizeServices"),
]

let isLocalDev = ["OversizeCore", "OversizeServices"].allSatisfy {
    FileManager.default.fileExists(atPath: "\(NSHomeDirectory())/Developer/Packages/\($0)")
}

let dependencies: [PackageDescription.Package.Dependency] = isLocalDev ? localDependencies : remoteDependencies

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
    dependencies: dependencies,
    targets: [
        .target(
            name: "OversizeIntelligenceService",
            dependencies: [
                .product(name: "FactoryKit", package: "Factory"),
                .product(name: "OversizeCore", package: "OversizeCore"),
                .product(name: "OversizeServices", package: "OversizeServices"),
            ]
        ),
        .testTarget(
            name: "OversizeIntelligenceServiceTests",
            dependencies: [
                "OversizeIntelligenceService",
                .product(name: "FactoryTesting", package: "Factory"),
            ]
        ),
    ]
)
