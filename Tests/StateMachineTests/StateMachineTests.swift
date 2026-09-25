import Testing
@testable import TradeGateCore

@Test func idleStateFollowsReviewThenPlanThenSignal() {
    #expect(RuleEngine.idleState(facts: GateFacts(pendingReviewCount: 1, hasSavablePlan: true, canRequestUnlock: true)) == .reviewRequired)
    #expect(RuleEngine.idleState(facts: .empty) == .planRequired)
    #expect(RuleEngine.idleState(facts: GateFacts(
        pendingReviewCount: 0,
        hasSavablePlan: true,
        planType: .entry,
        signalStatus: .notAppeared,
        canRequestUnlock: false
    )) == .signalPending)
    #expect(RuleEngine.idleState(facts: GateFacts(
        pendingReviewCount: 0,
        hasSavablePlan: true,
        planType: .entry,
        signalStatus: .appeared,
        canRequestUnlock: true
    )) == .ready)
}

@Test func normalUnlockIsDeniedUntilReady() {
    let readyFacts = GateFacts(pendingReviewCount: 0, hasSavablePlan: true, planType: .entry, signalStatus: .appeared, canRequestUnlock: true)
    #expect(RuleEngine.normalUnlockDenial(state: .reviewRequired, facts: GateFacts(pendingReviewCount: 2, hasSavablePlan: true, canRequestUnlock: true)) == .reviewRequired)
    #expect(RuleEngine.normalUnlockDenial(state: .planRequired, facts: .empty) == .planRequired)
    #expect(RuleEngine.normalUnlockDenial(state: .signalPending, facts: GateFacts(
        pendingReviewCount: 0, hasSavablePlan: true, planType: .entry, signalStatus: .notAppeared
    )) == .signalPending)
    #expect(RuleEngine.normalUnlockDenial(state: .ready, facts: readyFacts) == nil)
    #expect(RuleEngine.normalUnlockDenial(state: .errorFailClosed, facts: readyFacts) == .failClosed)
    #expect(RuleEngine.normalUnlockDenial(state: .lockStateUnknown, facts: readyFacts) == .lockUnknown)
}

@Test func legalAndIllegalTransitions() throws {
    #expect(try GateMachine.transition(.ready, .requestNormalUnlock).get() == .unlocking)
    #expect(try GateMachine.transition(.reviewRequired, .requestEmergencyUnlock).get() == .unlocking)
    #expect(try GateMachine.transition(.unlocking, .unlockSucceeded).get() == .unlocked)
    #expect(try GateMachine.transition(.unlocked, .timerFired).get() == .locking)
    #expect(try GateMachine.transition(.locking, .lockSucceeded).get() == .locked)
    #expect(try GateMachine.transition(.unlocked, .deviceRemovedWhileUnlocked).get() == .lockStateUnknown)
    #expect(try GateMachine.transition(.lockStateUnknown, .deviceInserted).get() == .locking)
    #expect(try GateMachine.transition(.locking, .lockUnconfirmed).get() == .lockStateUnknown)
    #expect(try GateMachine.transition(.reviewRequired, .requestNormalUnlock).isIllegal)
    #expect(try GateMachine.transition(.signalPending, .requestNormalUnlock).isIllegal)
    #expect(try GateMachine.transition(.planRequired, .requestNormalUnlock).isIllegal)
    #expect(try GateMachine.transition(.unlocked, .requestNormalUnlock).isIllegal)
    #expect(try GateMachine.transition(.errorFailClosed, .requestEmergencyUnlock).isIllegal)
}

private extension Result where Failure == GateTransitionError {
    var isIllegal: Bool {
        if case .failure = self { return true }
        return false
    }
}
