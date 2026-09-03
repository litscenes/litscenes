// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PhosphorSwift",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13)],
    products: [
        .library(name: "PhosphorSwift", targets: ["PhosphorSwift"])
    ],
    targets: [
        .target(
            name: "PhosphorSwift",
            path: "Sources/PhosphorSwift",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
