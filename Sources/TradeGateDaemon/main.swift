import Darwin
import Foundation
import TradeGateCore

for argument in CommandLine.arguments.dropFirst() {
    if argument == "--mock" {
        setenv("TRADEGATE_MOCK", "1", 1)
    } else if let value = argument.split(separator: "=", maxSplits: 1).last, argument.hasPrefix("--mach-service=") {
        setenv("TRADEGATE_MACH_SERVICE", String(value), 1)
    } else if let value = argument.split(separator: "=", maxSplits: 1).last, argument.hasPrefix("--support-dir=") {
        setenv("TRADEGATE_SUPPORT_DIR", String(value), 1)
    }
}

let directory = TradeGatePaths.supportDirectory
TradeGatePaths.adoptNewerRootDatabaseIfNeeded()
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let database = try TradeGateDatabase(path: TradeGatePaths.databasePath)
let selection = await YubiKeyBackend.select()
let yubiKey = selection.controller
if let warning = selection.warning {
    _ = try? database.appendAudit(AuditEventDraft(eventType: .helperError, metadata: ["message": warning]))
}

let coordinator = GateCoordinator(database: database, yubiKey: yubiKey)
await coordinator.boot()
let delegate = TradeGateXPCHost(coordinator: coordinator, database: database)
let listener = NSXPCListener(machServiceName: TradeGatePaths.machService)
listener.delegate = delegate
listener.resume()
while true {
    let snapshot = await coordinator.snapshot()
    let pause: Double = snapshot.state == .unlocked ? 1 : 5
    try await Task.sleep(for: .seconds(pause))
}
