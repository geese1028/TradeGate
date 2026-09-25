import Foundation
import TradeGateCore

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
