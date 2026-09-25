import Foundation
import TradeGateCore

let directory = TradeGatePaths.supportDirectory
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let database = try TradeGateDatabase(path: TradeGatePaths.databasePath)
let yubiKey: any YubiKeyControlling
if ProcessInfo.processInfo.environment["TRADEGATE_MOCK"] == "1" {
    yubiKey = MockYubiKeyController()
} else {
    let path = ProcessInfo.processInfo.environment["TRADEGATE_YKMAN"] ?? "/opt/homebrew/bin/ykman"
    let allow = ProcessInfo.processInfo.environment["TRADEGATE_DEV_YKMAN"] == "1"
    yubiKey = try YkmanCLIController(executable: path, allowUntrusted: allow)
}

let coordinator = GateCoordinator(database: database, yubiKey: yubiKey)
await coordinator.boot()
let delegate = TradeGateXPCHost(coordinator: coordinator, database: database)
let listener = NSXPCListener(machServiceName: TradeGatePaths.machService)
listener.delegate = delegate
listener.resume()
while true {
    try await Task.sleep(for: .seconds(3600))
}
