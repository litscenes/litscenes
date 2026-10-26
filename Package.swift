// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LitScenes",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LitScenes", targets: ["LitScenes"]),
        .library(name: "MeaningGraphCore", targets: ["MeaningGraphCore"]),
        .executable(name: "MeaningGraphCompiler", targets: ["MeaningGraphCompiler"])
    ],
    dependencies: [
        .package(path: "Vendor/PhosphorSwift"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(name: "MeaningGraphCore", dependencies: [.product(name: "Yams", package: "Yams")]),
        .executableTarget(name: "MeaningGraphCompiler", dependencies: ["MeaningGraphCore"]),
        .executableTarget(
            name: "LitScenes",
            dependencies: [
                "MeaningGraphCore",
                .product(name: "PhosphorSwift", package: "PhosphorSwift"),
                .product(name: "Yams", package: "Yams")
            ],
            resources: [
                .process("Resources/Pricing"),
                .process("Resources/Schemas"),
                .copy("Resources/MeaningGraph"),
                .process("Resources/render_stacks.yaml"),
                .process("Resources/story_pattern_index.json"),
                .copy("Resources/CatalogFallback"),
                .copy("Resources/Fonts")
            ]
        ),
        .testTarget(
            name: "LitScenesTests",
            dependencies: ["LitScenes", "MeaningGraphCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
