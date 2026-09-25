import Foundation

@objc public protocol TradeGateXPC {
    func perform(action: String, payload: String, reply: @escaping (String) -> Void)
}

public final class TradeGateXPCHost: NSObject, NSXPCListenerDelegate, TradeGateXPC, @unchecked Sendable {
    private let coordinator: GateCoordinator
    private let database: TradeGateDatabase

    public init(coordinator: GateCoordinator, database: TradeGateDatabase) {
        self.coordinator = coordinator
        self.database = database
    }

    public func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: TradeGateXPC.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    public func perform(action: String, payload: String, reply: @escaping (String) -> Void) {
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
    init(_ reply: @escaping (String) -> Void) {
        self.reply = reply
    }
}

public enum TradeGatePaths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TradeGate", isDirectory: true)
    }

    public static var databasePath: String {
        supportDirectory.appendingPathComponent("tradegate.sqlite").path
    }

    public static let machService = "com.tradegate.daemon"
}
