import Foundation

public actor YkmanCLIController: YubiKeyControlling {
    public typealias Runner = @Sendable (String, [String]) throws -> String

    private let executable: String
    private let runner: Runner

    public init(executable: String, allowUntrusted: Bool = false, runner: @escaping Runner = YkmanCLIController.processRunner) throws {
        try YkmanPathPolicy.validate(path: executable, allowUntrusted: allowUntrusted)
        self.executable = (executable as NSString).expandingTildeInPath
        self.runner = runner
    }

    public func listDevices() async throws -> [YubiKeyDevice] {
        let output = try run(.list)
        return YkmanTextParser.devices(from: output).filter(\.isManageable)
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
}
