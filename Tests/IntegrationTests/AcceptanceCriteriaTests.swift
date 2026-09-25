import Foundation
import SQLite3
import Testing
@testable import TradeGateCore

@Test func cachedSnapshotDoesNotRereadTheKey() async throws {
    let harness = try AcceptanceHarness()
    _ = await harness.coordinator.snapshot(probeHardware: false)
    _ = await harness.coordinator.snapshot(probeHardware: false)
    #expect(await harness.mock.listCount == 1)
}

@Test func snapshotListsTheKeyOnce() async throws {
    let harness = try AcceptanceHarness()
    _ = await harness.coordinator.snapshot()
    #expect(await harness.mock.listCount == 1)
}

@Test func newerRootDatabaseIsAdopted() {
    let older = Date(timeIntervalSince1970: 10)
    let newer = Date(timeIntervalSince1970: 20)
    #expect(TradeGatePaths.shouldAdoptRootDatabase(rootModified: newer, userModified: nil))
    #expect(TradeGatePaths.shouldAdoptRootDatabase(rootModified: newer, userModified: older))
    #expect(!TradeGatePaths.shouldAdoptRootDatabase(rootModified: older, userModified: newer))
}

@Test func daemonPlistAllowsTheAppAndCLI() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let text = try String(contentsOf: root.appendingPathComponent("Packaging/com.tradegate.daemon.plist"), encoding: .utf8)
    #expect(text.contains("SMAuthorizedClients"))
    #expect(text.contains("com.tradegate.app"))
    #expect(text.contains("com.tradegate.cli"))
}

@Test func snapshotNamesTheHelper() async throws {
    let harness = try AcceptanceHarness()
    let snapshot = await harness.coordinator.snapshot()
    #expect(snapshot.helperStatus == "mock")
}

@Test func ac01BootDisablesFIDO() async throws {
    let harness = try AcceptanceHarness()
    await harness.mock.apply(.unlocked)
    await harness.coordinator.boot()
    #expect(try await !(harness.mock.getState(deviceID: "111").fidoAvailable))
}

@Test func registeredSerialSurvivesANewDaemon() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    try await harness.coordinator.registerDevice(serial: "111")
    let other = MockYubiKeyController(devices: [
        MockYubiKeyController.SimulatedDevice(serialNumber: "222", fido2Enabled: true, u2fEnabled: true),
    ])
    let restarted = GateCoordinator(database: harness.database, yubiKey: other)
    await restarted.boot()
    let snapshot = await restarted.snapshot()
    #expect(snapshot.managedSerial == "111")
    #expect(try await other.getState(deviceID: "222").fidoAvailable)
}

@Test func ac02ManagedSerialNotEveryInsertedKey() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    try await harness.coordinator.registerDevice(serial: "111")
    await harness.mock.apply(.unlocked, serialNumber: "222")
    _ = await harness.coordinator.snapshot()
    #expect(try await !(harness.mock.getState(deviceID: "111").fidoAvailable))
    #expect(try await harness.mock.getState(deviceID: "222").fidoAvailable)
}

@Test func ac03Through10NormalUnlockRules() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    do {
        try await harness.coordinator.approveAndUnlock(planID: "missing")
        #expect(Bool(false))
    } catch {
        #expect(error is TradeGateError)
    }
    var waiting = try entryPlan()
    waiting.entry?.signalStatus = .notAppeared
    waiting.entry?.signalTimeframe = nil
    waiting.entry?.stopPrice = nil
    waiting.entry?.positionMode = nil
    waiting.entry?.positionValue = nil
    let saved = try await harness.coordinator.createPlan(waiting)
    do {
        try await harness.coordinator.approveAndUnlock(planID: saved.id)
        #expect(Bool(false))
    } catch let denial as UnlockDenial {
        #expect(denial == .signalPending)
    }
    var ready = saved
    ready.entry?.signalStatus = .appeared
    ready.entry?.signalTimeframe = .m30
    ready.entry?.stopPrice = try DecimalValue(parsing: "182.50")
    ready.entry?.positionMode = .percent
    ready.entry?.positionValue = try DecimalValue(parsing: "20")
    ready = try await harness.coordinator.updatePlan(ready)
    let start = Date(timeIntervalSince1970: 10000)
    try await harness.coordinator.approveAndUnlock(planID: ready.id, now: start)
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
    await harness.coordinator.expireUnlockWindow(at: start.addingTimeInterval(119))
    #expect(await harness.coordinator.currentState() == .unlocked)
    await harness.coordinator.expireUnlockWindow(at: start.addingTimeInterval(120))
    #expect(try await !(harness.mock.getState(deviceID: "111").fidoAvailable))
    _ = try await harness.coordinator.confirmExecution(ExecutionInput(
        planID: ready.id,
        price: DecimalValue(parsing: "188"),
        positionMode: .percent,
        positionValue: DecimalValue(parsing: "20")
    ))
    do {
        try await harness.coordinator.approveAndUnlock(planID: ready.id)
        #expect(Bool(false))
    } catch let denial as UnlockDenial {
        #expect(denial == .reviewRequired)
    }
}

@Test func ac11And12EmergencyLeavesAuditAndReview() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let armed = Date(timeIntervalSince1970: 1)
    #expect(!EmergencyGate.canStartCountdown(reason: "short", phrase: "EMERGENCY UNLOCK"))
    #expect(!EmergencyGate.canStartCountdown(reason: "need to cut risk", phrase: "emergency unlock"))
    #expect(EmergencyGate.canStartCountdown(reason: "need to cut risk", phrase: "EMERGENCY UNLOCK"))
    #expect(!EmergencyGate.canConfirm(armedAt: armed, now: armed.addingTimeInterval(19), countdownSeconds: 20))
    #expect(EmergencyGate.canConfirm(armedAt: armed, now: armed.addingTimeInterval(20), countdownSeconds: 20))
    _ = try await harness.coordinator.emergencyUnlock(EmergencyOverrideInput(
        application: .ibkr,
        symbol: Symbol(raw: "NVDA"),
        reasonCategory: .positionRisk,
        reasonText: "need to cut risk",
        confirmationPhrase: "EMERGENCY UNLOCK"
    ))
    let types = try harness.database.auditEvents().map(\.eventType)
    #expect(types.contains(.emergencyOverrideRequested))
    #expect(types.contains(.emergencyOverrideApproved))
    #expect(types.contains(.reviewRequired))
    #expect(try harness.database.pendingReviewCount() == 1)
}

@Test func ac13And14AuditIsCompleteAndAppendOnly() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(entryPlan())
    try await harness.coordinator.approveAndUnlock(planID: plan.id, now: Date(timeIntervalSince1970: 50))
    await harness.coordinator.expireUnlockWindow(at: Date(timeIntervalSince1970: 200))
    let execution = try await harness.coordinator.confirmExecution(ExecutionInput(
        planID: plan.id,
        price: DecimalValue(parsing: "10"),
        positionMode: .quantity,
        positionValue: DecimalValue(parsing: "1")
    ))
    let review = try harness.database.startReview(executionID: execution.id)
    _ = try harness.database.completeEntryReview(reviewID: review.id, actuals: entryActuals())
    let types = try Set(harness.database.auditEvents().map(\.eventType))
    for required in [
        AuditEventType.planCreated, .planApproved, .unlockRequested, .unlockApproved,
        .yubiKeyUnlocked, .yubiKeyLocked, .executionConfirmed, .reviewRequired, .planSubmitted,
        .reviewStarted, .reviewCompleted,
    ] {
        #expect(types.contains(required))
    }
    let verification = try harness.database.verifyAuditChain()
    #expect(verification.eventCount > 0)
    #expect(throws: TradeGateError.self) {
        try mutateAudit(path: harness.database.path, sql: "DELETE FROM audit_events;")
    }
}

@Test func ac13CoversUpdatesDenialRemovalAndErrors() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    var waiting = try entryPlan()
    waiting.entry?.signalStatus = .notAppeared
    waiting.entry?.signalTimeframe = nil
    waiting.entry?.stopPrice = nil
    waiting.entry?.positionMode = nil
    waiting.entry?.positionValue = nil
    let saved = try await harness.coordinator.createPlan(waiting)
    do {
        try await harness.coordinator.approveAndUnlock(planID: saved.id)
    } catch is UnlockDenial {}
    var ready = saved
    ready.entry?.signalStatus = .appeared
    ready.entry?.signalTimeframe = .m5
    ready.entry?.stopPrice = try DecimalValue(parsing: "10")
    ready.entry?.positionMode = .quantity
    ready.entry?.positionValue = try DecimalValue(parsing: "1")
    _ = try await harness.coordinator.updatePlan(ready)
    try await harness.coordinator.approveAndUnlock(planID: ready.id, now: Date(timeIntervalSince1970: 10))
    await harness.mock.apply(.removedWhileUnlocked, serialNumber: "111")
    _ = await harness.coordinator.snapshot(now: Date(timeIntervalSince1970: 15))
    await harness.mock.apply(.unlocked, serialNumber: "111")
    await harness.mock.apply(.failure, serialNumber: "111")
    _ = await harness.coordinator.snapshot(now: Date(timeIntervalSince1970: 20))
    _ = try await harness.coordinator.recordNoTrade(planID: ready.id, disposition: .noExecution)
    _ = try harness.database.appendAudit(AuditEventDraft(eventType: .appStarted))
    let types = try Set(harness.database.auditEvents().map(\.eventType))
    for required in [
        AuditEventType.daemonStarted, .planUpdated, .signalConfirmed, .unlockDenied,
        .deviceRemovedWhileUnlocked, .deviceInserted, .deviceRemoved, .yubiKeyError,
        .noExecution, .appStarted,
    ] {
        #expect(types.contains(required))
    }
}

@Test func helperFailureIsAuditedSeparatelyFromKeyFailure() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(entryPlan())
    await harness.mock.scriptNextFailure(.forbiddenCommand("reset"))
    do {
        try await harness.coordinator.approveAndUnlock(planID: plan.id)
    } catch is YubiKeyControlError {}
    let types = try harness.database.auditEvents().map(\.eventType)
    #expect(types.contains(.helperError))
    #expect(types.contains(.planSubmitted))
    let cancelled = try await harness.coordinator.recordNoTrade(planID: plan.id, disposition: .cancelled)
    #expect(cancelled.status == .cancelled)
    #expect(try harness.database.auditEvents().map(\.eventType).contains(.planCancelled))
}

@Test func daemonSnapshotKeepsTheWindowOpenUntilDeadline() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(entryPlan())
    let start = Date(timeIntervalSince1970: 5000)
    try await harness.coordinator.approveAndUnlock(planID: plan.id, now: start)
    _ = await harness.coordinator.snapshot(now: start.addingTimeInterval(30))
    #expect(await harness.coordinator.currentState() == .unlocked)
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
    _ = await harness.coordinator.snapshot(now: start.addingTimeInterval(120))
    #expect(await harness.coordinator.currentState() != .unlocked)
    #expect(try await !(harness.mock.getState(deviceID: "111").fidoAvailable))
}

@Test func pendingReviewBlocksADifferentSymbol() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let nvda = try await harness.coordinator.createPlan(entryPlan())
    try await harness.coordinator.approveAndUnlock(planID: nvda.id, now: Date(timeIntervalSince1970: 9000))
    await harness.coordinator.expireUnlockWindow(at: Date(timeIntervalSince1970: 9200))
    _ = try await harness.coordinator.confirmExecution(ExecutionInput(
        planID: nvda.id,
        price: DecimalValue(parsing: "10"),
        positionMode: .quantity,
        positionValue: DecimalValue(parsing: "1")
    ))
    var btc = try entryPlan()
    btc.application = .kraken
    btc.symbol = Symbol(raw: "BTC")
    btc = try await harness.coordinator.createPlan(btc)
    do {
        try await harness.coordinator.approveAndUnlock(planID: btc.id)
        #expect(Bool(false))
    } catch let denial as UnlockDenial {
        #expect(denial == .reviewRequired)
    }
    #expect(try await !(harness.mock.getState(deviceID: "111").fidoAvailable))
}

@Test func lockThatLeavesFIDOEnabledIsUnknown() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(entryPlan())
    let start = Date(timeIntervalSince1970: 15000)
    try await harness.coordinator.approveAndUnlock(planID: plan.id, now: start)
    await harness.mock.setLockLeavesEnabled(true)
    _ = await harness.coordinator.snapshot(now: start.addingTimeInterval(120))
    #expect(await harness.coordinator.currentState() == .lockStateUnknown)
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
    let snapshot = await harness.coordinator.snapshot(now: start.addingTimeInterval(121))
    #expect(snapshot.warning == "无法确认 FIDO 已关闭。")
}

@Test func unknownLockClearsOnceFIDOIsDisabled() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(entryPlan())
    let start = Date(timeIntervalSince1970: 17000)
    try await harness.coordinator.approveAndUnlock(planID: plan.id, now: start)
    await harness.mock.setLockLeavesEnabled(true)
    _ = await harness.coordinator.snapshot(now: start.addingTimeInterval(120))
    #expect(await harness.coordinator.currentState() == .lockStateUnknown)
    await harness.mock.setLockLeavesEnabled(false)
    _ = await harness.coordinator.snapshot(now: start.addingTimeInterval(130))
    #expect(await harness.coordinator.currentState() != .lockStateUnknown)
    #expect(try await !(harness.mock.getState(deviceID: "111").fidoAvailable))
    var next = try entryPlan()
    next.symbol = Symbol(raw: "DIA")
    next = try await harness.coordinator.createPlan(next)
    try await harness.coordinator.approveAndUnlock(planID: next.id, now: start.addingTimeInterval(140))
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
}

@Test func unknownLockBlocksTheNextNormalUnlock() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let first = try await harness.coordinator.createPlan(entryPlan())
    let start = Date(timeIntervalSince1970: 16000)
    try await harness.coordinator.approveAndUnlock(planID: first.id, now: start)
    await harness.mock.setLockLeavesEnabled(true)
    _ = await harness.coordinator.snapshot(now: start.addingTimeInterval(120))
    var second = try entryPlan()
    second.symbol = Symbol(raw: "IWM")
    second = try await harness.coordinator.createPlan(second)
    do {
        try await harness.coordinator.approveAndUnlock(planID: second.id)
        #expect(Bool(false))
    } catch let denial as UnlockDenial {
        #expect(denial == .lockUnknown)
    }
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
}

@Test func unlockThatDoesNotEnableFIDODoesNotCountAsOpen() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    await harness.mock.setUnlockLeavesDisabled(true)
    let plan = try await harness.coordinator.createPlan(entryPlan())
    do {
        try await harness.coordinator.approveAndUnlock(planID: plan.id)
        #expect(Bool(false))
    } catch is YubiKeyControlError {}
    #expect(await harness.coordinator.currentState() != .unlocked)
    #expect(try await !(harness.mock.getState(deviceID: "111").fidoAvailable))
}

@Test func finishingAnEmergencyReviewClearsTheGate() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let override = try await harness.coordinator.emergencyUnlock(EmergencyOverrideInput(
        application: .ibkr,
        symbol: Symbol(raw: "NVDA"),
        reasonCategory: .positionRisk,
        reasonText: "need to cut risk",
        confirmationPhrase: "EMERGENCY UNLOCK"
    ), now: Date(timeIntervalSince1970: 14000))
    await harness.coordinator.expireUnlockWindow(at: Date(timeIntervalSince1970: 14200))
    #expect(await harness.coordinator.currentState() == .reviewRequired)
    let review = try harness.database.startEmergencyReview(overrideID: override.id)
    _ = try harness.database.completeEmergencyReview(
        reviewID: review.id,
        answers: EmergencyReviewAnswers(
            why: "risk was live",
            didTrade: false,
            changedPosition: false,
            couldHaveUsedNormalFlow: false,
            howToAvoidNextTime: "write the plan first"
        )
    )
    _ = await harness.coordinator.snapshot(now: Date(timeIntervalSince1970: 14300))
    #expect(await harness.coordinator.currentState() != .reviewRequired)
    let plan = try await harness.coordinator.createPlan(entryPlan())
    try await harness.coordinator.approveAndUnlock(planID: plan.id, now: Date(timeIntervalSince1970: 14400))
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
}

@Test func completedReviewAllowsTheNextPlanToUnlock() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let first = try await harness.coordinator.createPlan(entryPlan())
    try await harness.coordinator.approveAndUnlock(planID: first.id, now: Date(timeIntervalSince1970: 13000))
    await harness.coordinator.expireUnlockWindow(at: Date(timeIntervalSince1970: 13200))
    let execution = try await harness.coordinator.confirmExecution(ExecutionInput(
        planID: first.id,
        price: DecimalValue(parsing: "11"),
        positionMode: .quantity,
        positionValue: DecimalValue(parsing: "1")
    ))
    let review = try harness.database.startReview(executionID: execution.id)
    _ = try harness.database.completeEntryReview(reviewID: review.id, actuals: entryActuals())
    #expect(try harness.database.pendingReviewCount() == 0)
    var second = try entryPlan()
    second.symbol = Symbol(raw: "AAPL")
    second = try await harness.coordinator.createPlan(second)
    try await harness.coordinator.approveAndUnlock(planID: second.id, now: Date(timeIntervalSince1970: 13300))
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
}

@Test func noExecutionAllowsTheNextPlanToUnlock() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let first = try await harness.coordinator.createPlan(entryPlan())
    try await harness.coordinator.approveAndUnlock(planID: first.id, now: Date(timeIntervalSince1970: 12000))
    await harness.coordinator.expireUnlockWindow(at: Date(timeIntervalSince1970: 12200))
    _ = try await harness.coordinator.recordNoTrade(planID: first.id, disposition: .noExecution)
    #expect(try harness.database.pendingReviewCount() == 0)
    var second = try entryPlan()
    second.symbol = Symbol(raw: "MSFT")
    second = try await harness.coordinator.createPlan(second)
    #expect(await harness.coordinator.currentState() == .ready)
    try await harness.coordinator.approveAndUnlock(planID: second.id, now: Date(timeIntervalSince1970: 12300))
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
}

@Test func exitPlanUnlocksWithoutAnEntrySignal() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(TradePlan(
        application: .ibkr,
        symbol: Symbol(raw: "QQQ"),
        planType: .exit,
        exit: ExitPlanFields(
            timeframe: .oneDay,
            secondaryState: .topDivergence,
            exitStrategy: .fullExitOnBreak,
            plannedExitPrice: DecimalValue(parsing: "500"),
            exitPositionMode: .all
        )
    ))
    #expect(await harness.coordinator.currentState() == .ready)
    try await harness.coordinator.approveAndUnlock(planID: plan.id, now: Date(timeIntervalSince1970: 11000))
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
}

@Test func unlockWindowUsesTheSavedDuration() async throws {
    let harness = try AcceptanceHarness()
    var settings = try harness.database.settings()
    settings.unlockDurationSeconds = 10
    #expect(throws: TradeGateError.self) {
        try harness.database.updateSettings(settings)
    }
    settings.unlockDurationSeconds = 30
    try harness.database.updateSettings(settings)
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(entryPlan())
    let start = Date(timeIntervalSince1970: 8000)
    try await harness.coordinator.approveAndUnlock(planID: plan.id, now: start)
    _ = await harness.coordinator.snapshot(now: start.addingTimeInterval(29))
    #expect(await harness.coordinator.currentState() == .unlocked)
    _ = await harness.coordinator.snapshot(now: start.addingTimeInterval(30))
    #expect(try await !(harness.mock.getState(deviceID: "111").fidoAvailable))
}

@Test func signalAppearedUpdatesTheSavedPlan() async throws {
    let harness = try AcceptanceHarness()
    await harness.coordinator.boot()
    var plan = try entryPlan()
    plan.entry?.signalStatus = .notAppeared
    plan.entry?.signalTimeframe = nil
    plan.entry?.stopPrice = nil
    plan.entry?.positionMode = nil
    plan.entry?.positionValue = nil
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let waiting = try String(data: encoder.encode(plan), encoding: .utf8) ?? ""
    let created = await GateRouter.perform(
        coordinator: harness.coordinator,
        database: harness.database,
        action: "createPlan",
        payload: waiting
    )
    #expect(created.contains("\"ok\":true"))
    let duplicate = await GateRouter.perform(
        coordinator: harness.coordinator,
        database: harness.database,
        action: "createPlan",
        payload: waiting
    )
    #expect(duplicate.contains("\"ok\":false"))
    plan.entry?.signalStatus = .appeared
    plan.entry?.signalTimeframe = .m30
    plan.entry?.stopPrice = try DecimalValue(parsing: "10")
    plan.entry?.positionMode = .quantity
    plan.entry?.positionValue = try DecimalValue(parsing: "1")
    let appeared = try String(data: encoder.encode(plan), encoding: .utf8) ?? ""
    let updated = await GateRouter.perform(
        coordinator: harness.coordinator,
        database: harness.database,
        action: "updatePlan",
        payload: appeared
    )
    #expect(updated.contains("\"ok\":true"))
    #expect(try harness.database.listPlans().count == 1)
    try await harness.coordinator.approveAndUnlock(planID: plan.id)
    #expect(try await harness.mock.getState(deviceID: "111").fidoAvailable)
}

@Test func ac16SourcesDoNotUseNetwork() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources")
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("URLSession"))
        #expect(!text.contains("http://"))
        #expect(!text.contains("https://"))
    }
}

@Test func ac17MockCoversHardwareStates() async throws {
    let mock = MockYubiKeyController()
    for scenario in [MockYubiKeyScenario.present, .absent, .locked, .unlocked, .failure, .removedWhileUnlocked] {
        await mock.apply(scenario)
    }
    #expect(try await mock.listDevices().isEmpty)
}

private struct AcceptanceHarness {
    let database: TradeGateDatabase
    let mock: MockYubiKeyController
    let coordinator: GateCoordinator

    init() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tradegate-ac-\(UUID().uuidString).sqlite")
        database = try TradeGateDatabase(path: url.path)
        mock = MockYubiKeyController(devices: [
            MockYubiKeyController.SimulatedDevice(serialNumber: "111", fido2Enabled: false, u2fEnabled: false),
        ])
        coordinator = GateCoordinator(database: database, yubiKey: mock)
    }
}

private func entryPlan() throws -> TradePlan {
    try TradePlan(
        application: .ibkr,
        symbol: Symbol(raw: "NVDA"),
        planType: .entry,
        entry: EntryPlanFields(
            timeframe: .threeDay,
            majorPullback: .twoLeg,
            mediumPullback: .oneLeg,
            smallDivergence: .m15,
            signalStatus: .appeared,
            signalTimeframe: .h1,
            stopPrice: DecimalValue(parsing: "182.50"),
            positionMode: .percent,
            positionValue: DecimalValue(parsing: "20")
        )
    )
}

private func entryActuals() throws -> EntryReviewActuals {
    try EntryReviewActuals(
        timeframe: .threeDay,
        majorPullback: .twoLeg,
        mediumPullback: .oneLeg,
        smallDivergence: .m15,
        signalStatus: .appeared,
        signalTimeframe: .h1,
        stopPrice: DecimalValue(parsing: "182.5"),
        positionMode: .percent,
        positionValue: DecimalValue(parsing: "20"),
        executionPrice: DecimalValue(parsing: "10"),
        adherence: .exact
    )
}

private func mutateAudit(path: String, sql: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK else { throw TradeGateError.sqlite("open") }
    defer { sqlite3_close(db) }
    var error: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &error)
    if rc != SQLITE_OK {
        let message = error.map { String(cString: $0) } ?? "sqlite"
        sqlite3_free(error)
        throw TradeGateError.sqlite(message)
    }
}
