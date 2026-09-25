import Testing
@testable import TradeGateCore

@Test func unsupportedYkmanVersionStaysFailClosed() async throws {
    let selection = await YubiKeyBackend.select(
        environment: [
            "TRADEGATE_YKMAN": "/tmp/ykman",
            "TRADEGATE_DEV_YKMAN": "1",
        ],
        runner: { _, arguments in
            if arguments == ["--version"] {
                return "YubiKey Manager (ykman) version: 5.8.0"
            }
            return ""
        }
    )
    #expect(selection.warning != nil)
    await #expect(throws: YubiKeyControlError.self) {
        try await selection.controller.unlock(deviceID: "1")
    }
}

@Test func ykmanSixStaysFailClosed() async throws {
    let selection = await YubiKeyBackend.select(
        environment: [
            "TRADEGATE_YKMAN": "/tmp/ykman",
            "TRADEGATE_DEV_YKMAN": "1",
        ],
        runner: { _, arguments in
            if arguments == ["--version"] {
                return "YubiKey Manager (ykman) version: 6.0.0"
            }
            return ""
        }
    )
    #expect(selection.warning != nil)
}

@Test func supportedYkmanUnlockOnlyEnablesFIDO() async throws {
    let recorder = YkmanCallRecorder()
    let selection = await YubiKeyBackend.select(
        environment: [
            "TRADEGATE_YKMAN": "/tmp/ykman",
            "TRADEGATE_DEV_YKMAN": "1",
        ],
        runner: { _, arguments in
            recorder.record(arguments)
            if arguments == ["--version"] {
                return "YubiKey Manager (ykman) version: 5.9.0"
            }
            if arguments.contains("list") {
                return "YubiKey 5C NFC (5.7.1) [FIDO] Serial: 42\n"
            }
            if arguments.contains("info") {
                return "FIDO U2F        Enabled\nFIDO2           Enabled\n"
            }
            return ""
        }
    )
    #expect(selection.warning == nil)
    try await selection.controller.unlock(deviceID: "42")
    let calls = recorder.calls
    #expect(calls.contains(["--device", "42", "config", "usb", "--enable", "FIDO2"]))
    #expect(calls.contains(["--device", "42", "config", "usb", "--enable", "U2F"]))
    #expect(calls.allSatisfy { !$0.joined(separator: " ").lowercased().contains("reset") })
}

@Test func missingYkmanStaysFailClosed() async throws {
    let selection = await YubiKeyBackend.select(environment: ["TRADEGATE_YKMAN": "/tmp/tradegate-missing-ykman"])
    #expect(selection.warning != nil)
    let devices = try await selection.controller.listDevices()
    #expect(devices.isEmpty)
    await #expect(throws: YubiKeyControlError.self) {
        try await selection.controller.unlock(deviceID: "1")
    }
}

@Test func mockCoversRequiredScenarios() async throws {
    let mock = MockYubiKeyController()
    await mock.apply(.absent)
    #expect(try await mock.listDevices().isEmpty)
    await mock.apply(.present)
    await mock.apply(.locked)
    let locked = try await mock.getState(deviceID: "12345678")
    #expect(locked.present && !locked.fidoAvailable)
    try await mock.unlock(deviceID: "12345678")
    #expect(try await mock.getState(deviceID: "12345678").fidoAvailable)
    try await mock.lock(deviceID: "12345678")
    #expect(try await !(mock.getState(deviceID: "12345678").fidoAvailable))
    await mock.apply(.failure)
    do {
        try await mock.unlock(deviceID: "12345678")
        #expect(Bool(false))
    } catch {
        #expect(error is YubiKeyControlError)
    }
    await mock.apply(.removedWhileUnlocked)
    #expect(try await mock.listDevices().isEmpty)
}

@Test func ykmanCommandsNeverResetOrTouchPIN() throws {
    let commands: [YkmanCommand] = [
        .version, .list, .info(serial: "123"),
        .setUSB(serial: "123", application: .fido2, enabled: false),
        .setUSB(serial: "123", application: .u2f, enabled: true),
    ]
    for command in commands {
        let arguments = try YkmanCommandBuilder.arguments(for: command)
        let joined = arguments.joined(separator: " ").lowercased()
        #expect(!joined.contains("reset"))
        #expect(!joined.contains("delete"))
        #expect(!joined.contains("pin"))
    }
    #expect(throws: YubiKeyControlError.self) {
        try YkmanCommandBuilder.validate(["fido", "reset"])
    }
}

@Test func ykmanParserReadsListAndInfo() {
    let listed = YkmanTextParser.devices(from: "YubiKey 5C NFC (5.7.1) [OTP+FIDO+CCID] Serial: 99887766\n")
    #expect(listed.first?.serialNumber == "99887766")
    #expect(listed.first?.isManageable == true)
    let info = """
    FIDO U2F        Disabled
    FIDO2           Disabled
    """
    let state = YkmanTextParser.state(from: info)
    #expect(!state.fido2Enabled)
    #expect(!state.u2fEnabled)
    let version = YkmanTextParser.version(from: "YubiKey Manager (ykman) version: 5.9.0")
    #expect(version?.isSupportedRelease == true)
    #expect(YkmanTextParser.version(from: "version: 5.8.0")?.isSupportedRelease == false)
    #expect(YkmanTextParser.version(from: "version: 6.0.0")?.isSupportedRelease == false)
}

@Test func untrustedYkmanPathIsRejected() throws {
    #expect(throws: YubiKeyControlError.self) {
        try YkmanPathPolicy.validate(path: "/tmp/ykman", allowUntrusted: false)
    }
    try YkmanPathPolicy.validate(path: "/tmp/ykman", allowUntrusted: true)
}

@Test func simulatedYkmanLockOnlyTogglesFIDO() async throws {
    let recorder = YkmanCallRecorder()
    let controller = try YkmanCLIController(executable: "/tmp/ykman", allowUntrusted: true) { _, arguments in
        recorder.record(arguments)
        if arguments.contains("info") {
            return "FIDO U2F        Disabled\nFIDO2           Disabled\n"
        }
        if arguments.contains("list") {
            return "YubiKey 5C NFC (5.7.1) [FIDO] Serial: 42\n"
        }
        return ""
    }
    _ = try await controller.listDevices()
    try await controller.lock(deviceID: "42")
    let calls = recorder.calls
    #expect(calls.contains(["--device", "42", "config", "usb", "--disable", "FIDO2"]))
    #expect(calls.contains(["--device", "42", "config", "usb", "--disable", "U2F"]))
    #expect(calls.allSatisfy { call in
        !call.joined(separator: " ").lowercased().contains("reset")
    })
}

private final class YkmanCallRecorder: @unchecked Sendable {
    var calls: [[String]] = []
    func record(_ arguments: [String]) {
        calls.append(arguments)
    }
}
