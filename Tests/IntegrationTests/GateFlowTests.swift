import Foundation
import Testing
@testable import TradeGateCore

@Test func bootKeepsFIDODisabled() async throws {
    let harness = try await Harness()
    await harness.mock.apply(.unlocked)
    await harness.coordinator.boot()
    let state = try await harness.mock.getState(deviceID: "12345678")
    #expect(!state.fidoAvailable)
    #expect(await harness.coordinator.currentState() != .unlocked)
}

@Test func missingPlanAndPendingSignalCannotUnlock() async throws {
    let harness = try await Harness()
    await harness.coordinator.boot()
    do {
        try await harness.coordinator.approveAndUnlock(planID: "none")
        #expect(Bool(false))
    } catch {
        #expect(error is TradeGateError)
    }
    var plan = try entryPlan()
    plan.entry?.signalStatus = .notAppeared
    plan.entry?.signalTimeframe = nil
    plan.entry?.stopPrice = nil
    plan.entry?.positionMode = nil
    plan.entry?.positionValue = nil
    let saved = try await harness.coordinator.createPlan(plan)
    #expect(await harness.coordinator.currentState() == .signalPending)
    do {
        try await harness.coordinator.approveAndUnlock(planID: saved.id)
        #expect(Bool(false))
    } catch let denial as UnlockDenial {
        #expect(denial == .signalPending)
    }
    #expect(try await !(harness.mock.getState(deviceID: "12345678").fidoAvailable))
}

@Test func approvedPlanUnlocksThenLocksAndRequiresReview() async throws {
    let harness = try await Harness()
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(entryPlan())
    #expect(await harness.coordinator.currentState() == .ready)
    try await harness.coordinator.approveAndUnlock(planID: plan.id, now: Date(timeIntervalSince1970: 1000))
    #expect(try await harness.mock.getState(deviceID: "12345678").fidoAvailable)
    #expect(await harness.coordinator.currentState() == .unlocked)
    await harness.coordinator.expireUnlockWindow(at: Date(timeIntervalSince1970: 2000))
    #expect(try await !(harness.mock.getState(deviceID: "12345678").fidoAvailable))
    let execution = try await harness.coordinator.confirmExecution(ExecutionInput(
        planID: plan.id,
        price: DecimalValue(parsing: "188.30"),
        positionMode: .percent,
        positionValue: DecimalValue(parsing: "20")
    ))
    #expect(execution.reviewRequired)
    #expect(await harness.coordinator.currentState() == .reviewRequired)
    do {
        try await harness.coordinator.approveAndUnlock(planID: plan.id)
        #expect(Bool(false))
    } catch let denial as UnlockDenial {
        #expect(denial == .reviewRequired)
    }
    let verification = try harness.database.verifyAuditChain()
    #expect(verification.eventCount > 0)
}

@Test func emergencyBypassesReviewAndLeavesAnotherReview() async throws {
    let harness = try await Harness()
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(entryPlan())
    try await harness.coordinator.approveAndUnlock(planID: plan.id, now: Date(timeIntervalSince1970: 1000))
    await harness.coordinator.expireUnlockWindow(at: Date(timeIntervalSince1970: 2000))
    _ = try await harness.coordinator.confirmExecution(ExecutionInput(
        planID: plan.id,
        price: DecimalValue(parsing: "10"),
        positionMode: .quantity,
        positionValue: DecimalValue(parsing: "1")
    ))
    let override = try await harness.coordinator.emergencyUnlock(EmergencyOverrideInput(
        application: .kraken,
        symbol: Symbol(raw: "BTC"),
        reasonCategory: .positionRisk,
        reasonText: "need to cut risk now",
        confirmationPhrase: "EMERGENCY UNLOCK"
    ), now: Date(timeIntervalSince1970: 3000))
    #expect(override.reviewRequired)
    #expect(try await harness.mock.getState(deviceID: "12345678").fidoAvailable)
    let types = try harness.database.auditEvents().map(\.eventType)
    #expect(types.contains(.emergencyOverrideRequested))
    #expect(types.contains(.emergencyOverrideApproved))
    #expect(types.contains(.reviewRequired))
}

@Test func removalWhileUnlockedLocksOnReinsert() async throws {
    let harness = try await Harness()
    await harness.coordinator.boot()
    let plan = try await harness.coordinator.createPlan(entryPlan())
    try await harness.coordinator.approveAndUnlock(planID: plan.id)
    await harness.mock.apply(.removedWhileUnlocked)
    _ = await harness.coordinator.snapshot()
    #expect(await harness.coordinator.currentState() == .lockStateUnknown)
    await harness.mock.apply(.present)
    await harness.mock.apply(.unlocked)
    _ = await harness.coordinator.snapshot()
    #expect(try await !(harness.mock.getState(deviceID: "12345678").fidoAvailable))
    #expect(await harness.coordinator.currentState() != .unlocked)
}

private struct Harness {
    let database: TradeGateDatabase
    let mock: MockYubiKeyController
    let coordinator: GateCoordinator

    init() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tradegate-\(UUID().uuidString).sqlite")
        database = try TradeGateDatabase(path: url.path)
        mock = MockYubiKeyController()
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
            signalTimeframe: .m30,
            stopPrice: DecimalValue(parsing: "182.50"),
            positionMode: .percent,
            positionValue: DecimalValue(parsing: "20")
        )
    )
}
