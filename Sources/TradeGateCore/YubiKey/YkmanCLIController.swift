import Darwin
import Foundation

@_silgen_name("posix_spawnattr_set_uid_np")
private func posix_spawnattr_set_uid_np(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>, _ uid: uid_t) -> Int32

public actor YkmanCLIController: YubiKeyControlling {
    public typealias Runner = @Sendable (String, [String]) throws -> String

    private let executable: String
    private let runner: Runner

    public init(executable: String, allowUntrusted: Bool = false, runner: @escaping Runner = YkmanCLIController.processRunner) throws {
        try YkmanPathPolicy.validate(path: executable, allowUntrusted: allowUntrusted)
        self.executable = (executable as NSString).expandingTildeInPath
        self.runner = runner
    }

    public func helperStatus() async -> String { "ykman" }

    public func listDevices() async throws -> [YubiKeyDevice] {
        let output = try run(.list)
        var manageable: [YubiKeyDevice] = []
        for device in YkmanTextParser.devices(from: output) {
            let info = try run(.info(serial: device.serialNumber))
            let applications = YkmanTextParser.controllableApplications(from: info)
            guard applications.fido2, applications.u2f else { continue }
            manageable.append(
                YubiKeyDevice(
                    serialNumber: device.serialNumber,
                    productName: device.productName,
                    firmwareVersion: device.firmwareVersion,
                    fido2Controllable: true,
                    u2fControllable: true
                )
            )
        }
        return manageable
    }

    public func getState(deviceID: String) async throws -> YubiKeyState {
        do {
            let output = try run(.info(serial: deviceID))
            return YkmanTextParser.state(from: output)
        } catch YubiKeyControlError.failed {
            return YubiKeyState(present: false, fido2Enabled: false, u2fEnabled: false)
        }
    }

    public func lock(deviceID: String) async throws {
        _ = try run(.setUSB(serial: deviceID, application: .fido2, enabled: false))
        _ = try run(.setUSB(serial: deviceID, application: .u2f, enabled: false))
    }

    public func unlock(deviceID: String) async throws {
        _ = try run(.setUSB(serial: deviceID, application: .fido2, enabled: true))
        _ = try run(.setUSB(serial: deviceID, application: .u2f, enabled: true))
    }

    public func ykmanVersion() async throws -> YkmanVersion {
        let output = try run(.version)
        guard let version = YkmanTextParser.version(from: output), version.isSupportedRelease else {
            throw YubiKeyControlError.unsupportedYkmanVersion(output)
        }
        return version
    }

    private func run(_ command: YkmanCommand) throws -> String {
        let arguments = try YkmanCommandBuilder.arguments(for: command)
        return try runner(executable, arguments)
    }

    public static func processRunner(executable: String, arguments: [String]) throws -> String {
        try YkmanCommandBuilder.validate(arguments)
        let uid = try YkmanPathPolicy.spawnUID(executable: executable)
        if uid != getuid() {
            return try spawn(executable: executable, arguments: arguments, uid: uid)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw YubiKeyControlError.failed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout + stderr
    }

    private static func spawn(executable: String, arguments: [String], uid: UInt32) throws -> String {
        var outPipe: [Int32] = [0, 0]
        var errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0, pipe(&errPipe) == 0 else {
            throw YubiKeyControlError.failed("pipe")
        }
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        guard posix_spawnattr_set_uid_np(&attr, uid) == 0 else {
            throw YubiKeyControlError.failed("spawn uid")
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, outPipe[0])
        posix_spawn_file_actions_addclose(&actions, errPipe[0])
        posix_spawn_file_actions_addclose(&actions, outPipe[1])
        posix_spawn_file_actions_addclose(&actions, errPipe[1])
        let argv = ([executable] + arguments).map { strdup($0) }
        defer { argv.forEach { free($0) } }
        var cargs: [UnsafeMutablePointer<CChar>?] = argv.map { $0 } + [nil]
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &actions, &attr, &cargs, environ)
        close(outPipe[1])
        close(errPipe[1])
        guard rc == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            throw YubiKeyControlError.failed("posix_spawn \(rc)")
        }
        let stdout = String(data: Data(reading: outPipe[0]), encoding: .utf8) ?? ""
        let stderr = String(data: Data(reading: errPipe[0]), encoding: .utf8) ?? ""
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : status
        guard code == 0 else {
            throw YubiKeyControlError.failed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout + stderr
    }
}

private extension Data {
    init(reading fd: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        close(fd)
        self = data
    }
}
