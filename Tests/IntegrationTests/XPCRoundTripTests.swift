import Foundation
import Testing
@testable import TradeGateCore

@Test func supportDirectoryCanBeIsolated() {
    let key = "TRADEGATE_SUPPORT_DIR"
    let previous = getenv(key).map { String(cString: $0) }
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tradegate-support-\(UUID().uuidString)", isDirectory: true)
    setenv(key, directory.path, 1)
    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }
    let expected = URL(fileURLWithPath: directory.path, isDirectory: true)
        .appendingPathComponent("tradegate.sqlite")
        .path
    #expect(TradeGatePaths.databasePath == expected)
}

@Test func xpcSnapshotRoundTrip() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tradegate-xpc-\(UUID().uuidString).sqlite")
    let database = try TradeGateDatabase(path: url.path)
    let mock = MockYubiKeyController()
    let coordinator = GateCoordinator(database: database, yubiKey: mock)
    await coordinator.boot()
    let host = TradeGateXPCHost(coordinator: coordinator, database: database)
    let listener = NSXPCListener.anonymous()
    listener.delegate = host
    listener.resume()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: TradeGateXPC.self)
    connection.resume()
    defer { connection.invalidate() }
    let proxy = try #require(connection.remoteObjectProxy as? TradeGateXPC)
    let reply: String = try await withCheckedThrowingContinuation { continuation in
        proxy.perform(action: "snapshot", payload: "") { value in
            continuation.resume(returning: value)
        }
    }
    #expect(reply.contains("\"ok\":true"))
    #expect(reply.contains("PLAN_REQUIRED") || reply.contains("LOCKED") || reply.contains("READY"))
}
