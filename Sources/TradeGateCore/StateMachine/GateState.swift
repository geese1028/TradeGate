import Foundation

public enum GateState: String, Codable, Sendable, CaseIterable {
    case locked = "LOCKED"
    case reviewRequired = "REVIEW_REQUIRED"
    case planRequired = "PLAN_REQUIRED"
    case signalPending = "SIGNAL_PENDING"
    case ready = "READY"
    case unlocking = "UNLOCKING"
    case unlocked = "UNLOCKED"
    case locking = "LOCKING"
    case errorFailClosed = "ERROR_FAIL_CLOSED"
    case lockStateUnknown = "LOCK_STATE_UNKNOWN"

    public var menuSymbol: String {
        switch self {
        case .unlocked, .unlocking:
            "🟢"
        case .reviewRequired, .errorFailClosed, .lockStateUnknown:
            "⚠️"
        case .locked, .planRequired, .signalPending, .ready, .locking:
            "🔒"
        }
    }

    public var isIdle: Bool {
        switch self {
        case .locked, .reviewRequired, .planRequired, .signalPending, .ready:
            true
        case .unlocking, .unlocked, .locking, .errorFailClosed, .lockStateUnknown:
            false
        }
    }
}

public enum UnlockDenial: String, Codable, Equatable, Error, Sendable {
    case reviewRequired
    case planRequired
    case signalPending
    case planNotApproved
    case failClosed
    case lockUnknown
    case busy
}

public struct GateFacts: Equatable, Sendable {
    public var pendingReviewCount: Int
    public var hasSavablePlan: Bool
    public var planType: PlanType?
    public var signalStatus: SignalStatus?
    public var canRequestUnlock: Bool

    public init(
        pendingReviewCount: Int,
        hasSavablePlan: Bool,
        planType: PlanType? = nil,
        signalStatus: SignalStatus? = nil,
        canRequestUnlock: Bool = false
    ) {
        self.pendingReviewCount = pendingReviewCount
        self.hasSavablePlan = hasSavablePlan
        self.planType = planType
        self.signalStatus = signalStatus
        self.canRequestUnlock = canRequestUnlock
    }

    public static let empty = GateFacts(pendingReviewCount: 0, hasSavablePlan: false)
}

public enum GateEvent: Equatable, Sendable {
    case evaluate(GateFacts)
    case requestNormalUnlock
    case requestEmergencyUnlock
    case unlockSucceeded
    case unlockFailed
    case timerFired
    case deviceRemovedWhileUnlocked
    case deviceInserted
    case lockSucceeded
    case lockUnconfirmed
    case confirmedLockedFailure
    case acknowledgeError

    public var name: String {
        switch self {
        case .evaluate: "evaluate"
        case .requestNormalUnlock: "requestNormalUnlock"
        case .requestEmergencyUnlock: "requestEmergencyUnlock"
        case .unlockSucceeded: "unlockSucceeded"
        case .unlockFailed: "unlockFailed"
        case .timerFired: "timerFired"
        case .deviceRemovedWhileUnlocked: "deviceRemovedWhileUnlocked"
        case .deviceInserted: "deviceInserted"
        case .lockSucceeded: "lockSucceeded"
        case .lockUnconfirmed: "lockUnconfirmed"
        case .confirmedLockedFailure: "confirmedLockedFailure"
        case .acknowledgeError: "acknowledgeError"
        }
    }
}

public enum GateTransitionError: Error, Equatable, Sendable {
    case illegal(from: GateState, event: String)
}

public enum RuleEngine {
    public static func idleState(facts: GateFacts) -> GateState {
        if facts.pendingReviewCount > 0 {
            return .reviewRequired
        }
        guard facts.hasSavablePlan else {
            return .planRequired
        }
        if facts.planType == .entry, facts.signalStatus != .appeared {
            return .signalPending
        }
        if facts.canRequestUnlock {
            return .ready
        }
        return .planRequired
    }

    public static func normalUnlockDenial(state: GateState, facts: GateFacts) -> UnlockDenial? {
        switch state {
        case .errorFailClosed:
            return .failClosed
        case .lockStateUnknown:
            return .lockUnknown
        case .unlocking, .unlocked, .locking:
            return .busy
        case .locked, .reviewRequired, .planRequired, .signalPending, .ready:
            break
        }
        if facts.pendingReviewCount > 0 {
            return .reviewRequired
        }
        if !facts.hasSavablePlan {
            return .planRequired
        }
        if facts.planType == .entry, facts.signalStatus != .appeared {
            return .signalPending
        }
        if !facts.canRequestUnlock {
            return .planNotApproved
        }
        if state != .ready {
            return .planNotApproved
        }
        return nil
    }
}

public enum GateMachine {
    public static func transition(_ state: GateState, _ event: GateEvent) -> Result<GateState, GateTransitionError> {
        switch (state, event) {
        case let (idle, .evaluate(facts)) where idle.isIdle:
            .success(RuleEngine.idleState(facts: facts))
        case (.ready, .requestNormalUnlock):
            .success(.unlocking)
        case (.locked, .requestEmergencyUnlock),
             (.reviewRequired, .requestEmergencyUnlock),
             (.planRequired, .requestEmergencyUnlock),
             (.signalPending, .requestEmergencyUnlock),
             (.ready, .requestEmergencyUnlock):
            .success(.unlocking)
        case (.unlocking, .unlockSucceeded):
            .success(.unlocked)
        case (.unlocking, .unlockFailed):
            .success(.locking)
        case (.unlocked, .timerFired):
            .success(.locking)
        case (.unlocked, .deviceRemovedWhileUnlocked):
            .success(.lockStateUnknown)
        case (.lockStateUnknown, .deviceInserted):
            .success(.locking)
        case (.locking, .lockSucceeded):
            .success(.locked)
        case (.locking, .lockUnconfirmed):
            .success(.lockStateUnknown)
        case (.locking, .confirmedLockedFailure):
            .success(.errorFailClosed)
        case (.errorFailClosed, .acknowledgeError):
            .success(.locked)
        default:
            .failure(.illegal(from: state, event: event.name))
        }
    }
}
