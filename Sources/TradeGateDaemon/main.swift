import Foundation
import TradeGateCore

let directory = TradeGatePaths.supportDirectory
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let database = try TradeGateDatabase(path: TradeGatePaths.databasePath)
let selection = YubiKeyBackend.select()
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
    try await Task.sleep(for: .seconds(3600))
}
