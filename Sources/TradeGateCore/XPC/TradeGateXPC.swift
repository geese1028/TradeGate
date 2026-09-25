import Darwin
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
        if let override = ProcessInfo.processInfo.environment["TRADEGATE_SUPPORT_DIR"],
           !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if geteuid() == 0, let home = consoleUserHome() {
            return URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("Library/Application Support/TradeGate", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TradeGate", isDirectory: true)
    }

    public static var databasePath: String {
        supportDirectory.appendingPathComponent("tradegate.sqlite").path
    }

    public static func adoptNewerRootDatabaseIfNeeded() {
        guard geteuid() == 0, let home = consoleUserHome() else { return }
        let userDirectory = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/TradeGate", isDirectory: true)
        let rootDatabase = URL(fileURLWithPath: "/var/root/Library/Application Support/TradeGate/tradegate.sqlite")
        let userDatabase = userDirectory.appendingPathComponent("tradegate.sqlite")
        guard FileManager.default.fileExists(atPath: rootDatabase.path) else { return }
        let rootModified = modifiedDate(rootDatabase.path)
        let userModified = FileManager.default.fileExists(atPath: userDatabase.path) ? modifiedDate(userDatabase.path) : nil
        guard shouldAdoptRootDatabase(rootModified: rootModified, userModified: userModified) else { return }
        try? FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = rootDatabase.path + suffix
            let destination = userDatabase.path + suffix
            guard FileManager.default.fileExists(atPath: source) else { continue }
            if FileManager.default.fileExists(atPath: destination) {
                try? FileManager.default.removeItem(atPath: destination)
            }
            try? FileManager.default.copyItem(atPath: source, toPath: destination)
        }
    }

    public static func shouldAdoptRootDatabase(rootModified: Date, userModified: Date?) -> Bool {
        guard let userModified else { return true }
        return rootModified > userModified
    }

    private static func modifiedDate(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
    }

    public static var machService: String {
        let override = ProcessInfo.processInfo.environment["TRADEGATE_MACH_SERVICE"] ?? ""
        if !override.isEmpty {
            return override
        }
        return "com.tradegate.daemon"
    }

    private static func consoleUserHome() -> String? {
        var info = stat()
        guard stat("/dev/console", &info) == 0, info.st_uid != 0 else { return nil }
        guard let password = getpwuid(info.st_uid), let directory = password.pointee.pw_dir else { return nil }
        let home = String(cString: directory)
        guard home.hasPrefix("/Users/") else { return nil }
        return home
    }
}
