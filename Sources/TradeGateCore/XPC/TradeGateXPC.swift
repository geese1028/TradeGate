import Foundation

@objc public protocol TradeGateXPC {
    func perform(action: String, payload: String, reply: @escaping (String) -> Void)
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
