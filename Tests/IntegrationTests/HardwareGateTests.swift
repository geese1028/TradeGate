import Foundation
import Testing
@testable import TradeGateCore

@Test func installedYkmanPassesTheProductionPathCheck() async throws {
    let path = "/opt/homebrew/bin/ykman"
    guard FileManager.default.isExecutableFile(atPath: path) else { return }
    try YkmanPathPolicy.validate(path: path, allowUntrusted: false)
    let controller = try YkmanCLIController(executable: path)
    _ = try await controller.listDevices()
}

@Test func hardwareTestStaysOffUnlessRequested() async throws {
    guard ProcessInfo.processInfo.environment["TRADEGATE_HARDWARE_TEST"] == "1" else {
        return
    }
    let path = ProcessInfo.processInfo.environment["TRADEGATE_YKMAN"] ?? "/opt/homebrew/bin/ykman"
    guard FileManager.default.isExecutableFile(atPath: path) else {
        throw YubiKeyControlError.untrustedExecutable("ykman is not executable at \(path)")
    }
    let controller = try YkmanCLIController(executable: path, allowUntrusted: true)
    let devices = try await controller.listDevices()
    guard let device = devices.first, device.isManageable else {
        throw YubiKeyControlError.absent
    }
    try await controller.lock(deviceID: device.serialNumber)
    try await controller.unlock(deviceID: device.serialNumber)
    try await controller.lock(deviceID: device.serialNumber)
    let state = try await controller.getState(deviceID: device.serialNumber)
    #expect(!state.fidoAvailable)
}

@Test func applicationSourcesDoNotInvokeYkman() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let app = root.appendingPathComponent("Sources/TradeGateApp")
    guard let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else {
        return
    }
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8).lowercased()
        #expect(!text.contains("ykman"))
        #expect(!text.contains("reset fido"))
    }
}
