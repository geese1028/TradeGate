import Foundation

public struct YubiKeyDevice: Equatable, Sendable, Codable, Identifiable {
    public var serialNumber: String
    public var productName: String
    public var firmwareVersion: String
    public var fido2Controllable: Bool
    public var u2fControllable: Bool

    public var id: String {
        serialNumber
    }

    public init(
        serialNumber: String,
        productName: String,
        firmwareVersion: String,
        fido2Controllable: Bool,
        u2fControllable: Bool
    ) {
        self.serialNumber = serialNumber
        self.productName = productName
        self.firmwareVersion = firmwareVersion
        self.fido2Controllable = fido2Controllable
        self.u2fControllable = u2fControllable
    }

    public var isManageable: Bool {
        fido2Controllable && u2fControllable
    }
}

public struct YubiKeyState: Equatable, Sendable, Codable {
    public var present: Bool
    public var fido2Enabled: Bool
    public var u2fEnabled: Bool

    public init(present: Bool, fido2Enabled: Bool, u2fEnabled: Bool) {
        self.present = present
        self.fido2Enabled = fido2Enabled
        self.u2fEnabled = u2fEnabled
    }

    public var fidoAvailable: Bool {
        present && (fido2Enabled || u2fEnabled)
    }
}

public enum YubiKeyControlError: Error, Equatable, Sendable {
    case absent
    case unsupportedDevice
    case failed(String)
    case forbiddenCommand(String)
    case untrustedExecutable(String)
    case unsupportedYkmanVersion(String)
}

public actor FailClosedYubiKeyController: YubiKeyControlling {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func helperStatus() async -> String { reason }

    public func listDevices() async throws -> [YubiKeyDevice] { [] }

    public func getState(deviceID _: String) async throws -> YubiKeyState {
        YubiKeyState(present: false, fido2Enabled: false, u2fEnabled: false)
    }

    public func lock(deviceID _: String) async throws {
        throw YubiKeyControlError.failed(reason)
    }

    public func unlock(deviceID _: String) async throws {
        throw YubiKeyControlError.failed(reason)
    }
}

public enum YubiKeyBackend {
    public static func select(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: @escaping YkmanCLIController.Runner = YkmanCLIController.processRunner
    ) async -> (controller: any YubiKeyControlling, warning: String?) {
        if environment["TRADEGATE_MOCK"] == "1" {
            return (MockYubiKeyController(), nil)
        }
        let path = environment["TRADEGATE_YKMAN"] ?? "/opt/homebrew/bin/ykman"
        let allowUntrusted = environment["TRADEGATE_DEV_YKMAN"] == "1"
        do {
            let controller = try YkmanCLIController(executable: path, allowUntrusted: allowUntrusted, runner: runner)
            _ = try await controller.ykmanVersion()
            return (controller, nil)
        } catch {
            return (FailClosedYubiKeyController(reason: "\(error)"), "\(error)")
        }
    }
}

public protocol YubiKeyControlling: Sendable {
    func helperStatus() async -> String
    func listDevices() async throws -> [YubiKeyDevice]
    func getState(deviceID: String) async throws -> YubiKeyState
    func lock(deviceID: String) async throws
    func unlock(deviceID: String) async throws
}

public enum MockYubiKeyScenario: String, Codable, Sendable {
    case present
    case absent
    case locked
    case unlocked
    case failure
    case removedWhileUnlocked
}

public actor MockYubiKeyController: YubiKeyControlling {
    public struct SimulatedDevice: Equatable, Sendable {
        public var serialNumber: String
        public var productName: String
        public var firmwareVersion: String
        public var present: Bool
        public var fido2Enabled: Bool
        public var u2fEnabled: Bool
        public var manageable: Bool
        public var failNextLock: Bool
        public var failNextUnlock: Bool

        public init(
            serialNumber: String = "12345678",
            productName: String = "YubiKey 5C NFC",
            firmwareVersion: String = "5.7.1",
            present: Bool = true,
            fido2Enabled: Bool = false,
            u2fEnabled: Bool = false,
            manageable: Bool = true,
            failNextLock: Bool = false,
            failNextUnlock: Bool = false
        ) {
            self.serialNumber = serialNumber
            self.productName = productName
            self.firmwareVersion = firmwareVersion
            self.present = present
            self.fido2Enabled = fido2Enabled
            self.u2fEnabled = u2fEnabled
            self.manageable = manageable
            self.failNextLock = failNextLock
            self.failNextUnlock = failNextUnlock
        }
    }

    private var devices: [String: SimulatedDevice]
    private var scriptedError: YubiKeyControlError?
    private var unlockLeavesDisabled = false
    private var lockLeavesEnabled = false
    public private(set) var listCount = 0
    public private(set) var lockCount = 0
    public private(set) var unlockCount = 0

    public init(devices: [SimulatedDevice] = [SimulatedDevice()]) {
        self.devices = Dictionary(uniqueKeysWithValues: devices.map { ($0.serialNumber, $0) })
    }

    public func scriptNextFailure(_ error: YubiKeyControlError) {
        scriptedError = error
    }

    public func setUnlockLeavesDisabled(_ value: Bool) {
        unlockLeavesDisabled = value
    }

    public func setLockLeavesEnabled(_ value: Bool) {
        lockLeavesEnabled = value
    }

    public func apply(_ scenario: MockYubiKeyScenario, serialNumber: String = "12345678") {
        var device = devices[serialNumber] ?? SimulatedDevice(serialNumber: serialNumber)
        switch scenario {
        case .present:
            device.present = true
        case .absent:
            device.present = false
        case .locked:
            device.present = true
            device.fido2Enabled = false
            device.u2fEnabled = false
        case .unlocked:
            device.present = true
            device.fido2Enabled = true
            device.u2fEnabled = true
        case .failure:
            device.present = true
            device.failNextLock = true
            device.failNextUnlock = true
        case .removedWhileUnlocked:
            device.fido2Enabled = true
            device.u2fEnabled = true
            device.present = false
        }
        devices[serialNumber] = device
    }

    public func helperStatus() async -> String { "mock" }

    public func listDevices() async throws -> [YubiKeyDevice] {
        listCount += 1
        return devices.values.filter(\.present).map {
            YubiKeyDevice(
                serialNumber: $0.serialNumber,
                productName: $0.productName,
                firmwareVersion: $0.firmwareVersion,
                fido2Controllable: $0.manageable,
                u2fControllable: $0.manageable
            )
        }
    }

    public func getState(deviceID: String) async throws -> YubiKeyState {
        guard let device = devices[deviceID], device.present else {
            return YubiKeyState(present: false, fido2Enabled: false, u2fEnabled: false)
        }
        return YubiKeyState(
            present: true,
            fido2Enabled: device.fido2Enabled,
            u2fEnabled: device.u2fEnabled
        )
    }

    public func lock(deviceID: String) async throws {
        if let scriptedError {
            self.scriptedError = nil
            throw scriptedError
        }
        guard var device = devices[deviceID] else {
            throw YubiKeyControlError.absent
        }
        guard device.present else { throw YubiKeyControlError.absent }
        guard device.manageable else { throw YubiKeyControlError.unsupportedDevice }
        if device.failNextLock {
            device.failNextLock = false
            devices[deviceID] = device
            throw YubiKeyControlError.failed("mock lock failure")
        }
        if !lockLeavesEnabled {
            device.fido2Enabled = false
            device.u2fEnabled = false
        }
        devices[deviceID] = device
        lockCount += 1
    }

    public func unlock(deviceID: String) async throws {
        if let scriptedError {
            self.scriptedError = nil
            throw scriptedError
        }
        guard var device = devices[deviceID] else {
            throw YubiKeyControlError.absent
        }
        guard device.present else { throw YubiKeyControlError.absent }
        guard device.manageable else { throw YubiKeyControlError.unsupportedDevice }
        if device.failNextUnlock {
            device.failNextUnlock = false
            devices[deviceID] = device
            throw YubiKeyControlError.failed("mock unlock failure")
        }
        if unlockLeavesDisabled {
            devices[deviceID] = device
            unlockCount += 1
            return
        }
        device.fido2Enabled = true
        device.u2fEnabled = true
        devices[deviceID] = device
        unlockCount += 1
    }
}
