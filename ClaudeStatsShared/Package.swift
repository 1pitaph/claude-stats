// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeStatsShared",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ClaudeStatsCore", targets: ["ClaudeStatsCore"]),
        .library(name: "ClaudeStatsSync", targets: ["ClaudeStatsSync"]),
    ],
    targets: [
        .target(name: "ClaudeStatsCore"),
        .target(
            name: "ClaudeStatsSync",
            dependencies: ["ClaudeStatsCore"],
            linkerSettings: [
                .linkedFramework("CloudKit"),
            ]
        ),
    ]
)
