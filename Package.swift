// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LitScenes",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LitScenes", targets: ["LitScenes"])
    ],
    dependencies: [
        .package(path: "Vendor/PhosphorSwift"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "LitScenes",
            dependencies: [
                .product(name: "PhosphorSwift", package: "PhosphorSwift"),
                .product(name: "Yams", package: "Yams")
            ],
            resources: [
                .process("Resources/Pricing"),
                .process("Resources/Schemas"),
                .process("Resources/meaning_choice_index.json"),
                .process("Resources/render_stacks.yaml"),
                .process("Resources/story_pattern_index.json"),
                .copy("Resources/CatalogFallback"),
                .copy("Resources/Fonts")
            ]
        ),
        .testTarget(
            name: "LitScenesTests",
            dependencies: ["LitScenes"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
