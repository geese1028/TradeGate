// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TradeGate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TradeGateCore", targets: ["TradeGateCore"]),
        .executable(name: "TradeGateApp", targets: ["TradeGateApp"]),
        .executable(name: "TradeGateDaemon", targets: ["TradeGateDaemon"]),
        .executable(name: "tradegate", targets: ["TradeGateCLI"])
    ],
    targets: [
        .target(
            name: "TradeGateCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(name: "TradeGateApp", dependencies: ["TradeGateCore"]),
        .executableTarget(name: "TradeGateDaemon", dependencies: ["TradeGateCore"]),
        .executableTarget(name: "TradeGateCLI", dependencies: ["TradeGateCore"]),
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
        ),
        .testTarget(name: "StateMachineTests", dependencies: ["TradeGateCore"]),
        .testTarget(name: "YubiKeyMockTests", dependencies: ["TradeGateCore"]),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["TradeGateCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
