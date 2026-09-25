import Foundation
import TradeGateCore

let arguments = Array(CommandLine.arguments.dropFirst())
let joined = arguments.joined(separator: " ")
if joined.contains("unlock") && joined.contains("--force") {
    fputs("tradegate unlock --force is not available\n", stderr)
    exit(2)
}
if joined.contains("review") && joined.contains("--skip") {
    fputs("tradegate review --skip is not available\n", stderr)
    exit(2)
}

guard let command = arguments.first else {
    fputs("usage: tradegate status | tradegate audit verify | tradegate doctor\n", stderr)
    exit(2)
}

switch command {
case "status":
    let snapshot = xpc(action: "snapshot", payload: "")
    if let data = snapshot.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let result = object["result"] as? [String: Any] {
        print("TradeGate")
        print("")
        print("State: \(result["state"] as? String ?? "LOCK_STATE_UNKNOWN")")
        print("")
        print("Pending review: \(result["pendingReviewCount"] as? Int ?? 0)")
        print("")
        print("YubiKey:")
        print((result["yubiKeyPresent"] as? Bool) == true ? "Present" : "Absent")
        print("")
        print("Today unlocks: \(result["todayUnlocks"] as? Int ?? 0)")
    } else {
        print("TradeGate")
        print("")
        print("State: LOCK_STATE_UNKNOWN")
        print("")
        print("Pending review: \(pendingFromDatabase())")
        print("")
        print("YubiKey:")
        print("Unknown")
        print("")
        print("Today unlocks: 0")
    }
case "audit":
    guard arguments.dropFirst().first == "verify" else {
        fputs("usage: tradegate audit verify\n", stderr)
        exit(2)
    }
    let database = try openDatabase()
    let verification = try database.verifyAuditChain()
    print("audit chain ok events=\(verification.eventCount)")
case "doctor":
    var failures = 0
    failures += report("database") { _ = try openDatabase() }
    failures += report("audit chain") { _ = try openDatabase().verifyAuditChain() }
    failures += report("ykman") {
        let path = ProcessInfo.processInfo.environment["TRADEGATE_YKMAN"] ?? "/opt/homebrew/bin/ykman"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw TradeGateError.invalidState("ykman not executable at \(path)")
        }
    }
    failures += report("XPC") {
        let reply = xpc(action: "snapshot", payload: "")
        guard reply.contains("\"ok\":true") else { throw TradeGateError.invalidState(reply) }
    }
    failures += report("daemon") {
        let reply = xpc(action: "snapshot", payload: "")
        guard reply.contains("\"ok\":true") else { throw TradeGateError.invalidState("daemon did not answer") }
    }
    failures += report("YubiKey") {
        let reply = xpc(action: "snapshot", payload: "")
        guard reply.contains("yubiKeyPresent") else { throw TradeGateError.invalidState("no key status") }
    }
    if failures > 0 { exit(1) }
    print("doctor ok")
default:
    fputs("usage: tradegate status | tradegate audit verify | tradegate doctor\n", stderr)
    exit(2)
}

func openDatabase() throws -> TradeGateDatabase {
    try FileManager.default.createDirectory(at: TradeGatePaths.supportDirectory, withIntermediateDirectories: true)
    return try TradeGateDatabase(path: TradeGatePaths.databasePath)
}

func pendingFromDatabase() -> Int {
    (try? openDatabase().pendingReviewCount()) ?? 0
}

func xpc(action: String, payload: String) -> String {
    let connection = NSXPCConnection(machServiceName: TradeGatePaths.machService)
    connection.remoteObjectInterface = NSXPCInterface(with: TradeGateXPC.self)
    connection.resume()
    defer { connection.invalidate() }
    guard let proxy = connection.remoteObjectProxy as? TradeGateXPC else { return "" }
    let semaphore = DispatchSemaphore(value: 0)
    var reply = ""
    proxy.perform(action: action, payload: payload) { value in
        reply = value
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 2)
    return reply
}

func report(_ name: String, _ body: () throws -> Void) -> Int {
    do {
        try body()
        print("\(name): ok")
        return 0
    } catch {
        print("\(name): \(error)")
        return 1
    }
}
