import Foundation

public enum YkmanUSBApplication: String, Sendable {
    case fido2 = "FIDO2"
    case u2f = "U2F"
}

public enum YkmanCommand: Equatable, Sendable {
    case version
    case list
    case info(serial: String)
    case setUSB(serial: String, application: YkmanUSBApplication, enabled: Bool)
}

public enum YkmanCommandBuilder {
    public static let forbiddenTokens = ["reset", "delete", "pin"]

    public static func arguments(for command: YkmanCommand) throws -> [String] {
        let arguments: [String]
        switch command {
        case .version:
            arguments = ["--version"]
        case .list:
            arguments = ["list"]
        case let .info(serial):
            arguments = ["--device", serial, "info"]
        case let .setUSB(serial, application, enabled):
            let flag = enabled ? "--enable" : "--disable"
            arguments = ["--device", serial, "config", "usb", flag, application.rawValue]
        }
        try validate(arguments)
        return arguments
    }

    public static func validate(_ arguments: [String]) throws {
        for argument in arguments {
            let lowered = argument.lowercased()
            if forbiddenTokens.contains(where: { lowered.contains($0) }) {
                throw YubiKeyControlError.forbiddenCommand(argument)
            }
        }
    }
}

public struct YkmanVersion: Equatable, Sendable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var isSupportedRelease: Bool {
        major == 5 && minor >= 9
    }
}

public enum YkmanTextParser {
    public static func version(from output: String) -> YkmanVersion? {
        let pattern = #"(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let majorRange = Range(match.range(at: 1), in: output),
              let minorRange = Range(match.range(at: 2), in: output),
              let patchRange = Range(match.range(at: 3), in: output),
              let major = Int(output[majorRange]),
              let minor = Int(output[minorRange]),
              let patch = Int(output[patchRange])
        else {
            return nil
        }
        return YkmanVersion(major: major, minor: minor, patch: patch)
    }

    public static func devices(from listOutput: String) -> [YubiKeyDevice] {
        listOutput.split(separator: "\n").compactMap { line in
            let text = String(line)
            guard text.contains("Serial:"),
                  let serial = text.split(separator: "Serial:").last?.trimmingCharacters(in: .whitespaces),
                  !serial.isEmpty
            else {
                return nil
            }
            let product = text.split(separator: "(").first?.trimmingCharacters(in: .whitespaces) ?? "YubiKey"
            let firmware = version(from: text).map { "\($0.major).\($0.minor).\($0.patch)" } ?? ""
            return YubiKeyDevice(
                serialNumber: serial,
                productName: product,
                firmwareVersion: firmware,
                fido2Controllable: text.uppercased().contains("FIDO"),
                u2fControllable: text.uppercased().contains("FIDO")
            )
        }
    }

    public static func state(from infoOutput: String) -> YubiKeyState {
        YubiKeyState(
            present: true,
            fido2Enabled: applicationEnabled("FIDO2", in: infoOutput),
            u2fEnabled: applicationEnabled("FIDO U2F", in: infoOutput) || applicationEnabled("U2F", in: infoOutput)
        )
    }

    private static func applicationEnabled(_ name: String, in output: String) -> Bool {
        for line in output.split(separator: "\n") {
            let text = String(line)
            guard text.uppercased().contains(name.uppercased()) else { continue }
            let lowered = text.lowercased()
            if lowered.contains("disabled") {
                return false
            }
            if lowered.contains("enabled") {
                return true
            }
        }
        return false
    }
}

public enum YkmanPathPolicy {
    public static let trustedPaths = [
        "/opt/homebrew/bin/ykman",
        "/usr/local/bin/ykman",
    ]

    public static func validate(path: String, allowUntrusted: Bool) throws {
        if allowUntrusted {
            return
        }
        let expanded = (path as NSString).expandingTildeInPath
        guard trustedPaths.contains(expanded) || expanded.contains("/TradeGate.app/Contents/") else {
            throw YubiKeyControlError.untrustedExecutable(path)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: expanded)
        let owner = attributes[.ownerAccountID] as? NSNumber
        let permissions = attributes[.posixPermissions] as? NSNumber
        if owner?.uint32Value != 0 {
            throw YubiKeyControlError.untrustedExecutable("owner is not root")
        }
        if let mode = permissions?.uint16Value, mode & 0o022 != 0 {
            throw YubiKeyControlError.untrustedExecutable("executable is writable by group or others")
        }
    }
}
