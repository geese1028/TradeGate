// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TradeGate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TradeGateCore", targets: ["TradeGateCore"])
    ],
    targets: [
        .target(
            name: "TradeGateCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["TradeGateCore"]
        ),
        .testTarget(
            name: "DatabaseTests",
            dependencies: ["TradeGateCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
