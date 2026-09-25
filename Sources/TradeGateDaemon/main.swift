import Foundation
import TradeGateCore

final class DaemonDelegate: NSObject, NSXPCListenerDelegate, TradeGateXPC {
    let coordinator: GateCoordinator
    let database: TradeGateDatabase

    init(coordinator: GateCoordinator, database: TradeGateDatabase) {
        self.coordinator = coordinator
        self.database = database
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: TradeGateXPC.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func perform(action: String, payload: String, reply: @escaping (String) -> Void) {
        let box = ReplyBox(reply)
        let coordinator = coordinator
        let database = database
        Task {
            let result = await GateRouter.perform(
                coordinator: coordinator,
                database: database,
                action: action,
                payload: payload
            )
            box.reply(result)
        }
    }
}

final class ReplyBox: @unchecked Sendable {
    let reply: (String) -> Void
    init(_ reply: @escaping (String) -> Void) { self.reply = reply }
}

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
let delegate = DaemonDelegate(coordinator: coordinator, database: database)
let listener = NSXPCListener(machServiceName: TradeGatePaths.machService)
listener.delegate = delegate
listener.resume()
while true {
    try await Task.sleep(for: .seconds(3600))
}
