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
            return "🟢"
        case .reviewRequired, .errorFailClosed, .lockStateUnknown:
            return "⚠️"
        case .locked, .planRequired, .signalPending, .ready, .locking:
            return "🔒"
        }
    }

    public var isIdle: Bool {
        switch self {
        case .locked, .reviewRequired, .planRequired, .signalPending, .ready:
            return true
        case .unlocking, .unlocked, .locking, .errorFailClosed, .lockStateUnknown:
            return false
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
        case .evaluate: return "evaluate"
        case .requestNormalUnlock: return "requestNormalUnlock"
        case .requestEmergencyUnlock: return "requestEmergencyUnlock"
        case .unlockSucceeded: return "unlockSucceeded"
        case .unlockFailed: return "unlockFailed"
        case .timerFired: return "timerFired"
        case .deviceRemovedWhileUnlocked: return "deviceRemovedWhileUnlocked"
        case .deviceInserted: return "deviceInserted"
        case .lockSucceeded: return "lockSucceeded"
        case .lockUnconfirmed: return "lockUnconfirmed"
        case .confirmedLockedFailure: return "confirmedLockedFailure"
        case .acknowledgeError: return "acknowledgeError"
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
            return .success(RuleEngine.idleState(facts: facts))
        case (.ready, .requestNormalUnlock):
            return .success(.unlocking)
        case (.locked, .requestEmergencyUnlock),
             (.reviewRequired, .requestEmergencyUnlock),
             (.planRequired, .requestEmergencyUnlock),
             (.signalPending, .requestEmergencyUnlock),
             (.ready, .requestEmergencyUnlock):
            return .success(.unlocking)
        case (.unlocking, .unlockSucceeded):
            return .success(.unlocked)
        case (.unlocking, .unlockFailed):
            return .success(.locking)
        case (.unlocked, .timerFired):
            return .success(.locking)
        case (.unlocked, .deviceRemovedWhileUnlocked):
            return .success(.lockStateUnknown)
        case (.lockStateUnknown, .deviceInserted):
            return .success(.locking)
        case (.locking, .lockSucceeded):
            return .success(.locked)
        case (.locking, .lockUnconfirmed):
            return .success(.lockStateUnknown)
        case (.locking, .confirmedLockedFailure):
            return .success(.errorFailClosed)
        case (.errorFailClosed, .acknowledgeError):
            return .success(.locked)
        default:
            return .failure(.illegal(from: state, event: event.name))
        }
    }
}
