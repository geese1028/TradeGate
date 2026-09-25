import Foundation

public struct GateSnapshot: Equatable, Sendable, Codable {
    public var state: GateState
    public var pendingReviewCount: Int
    public var todayUnlocks: Int
    public var yubiKeyPresent: Bool
    public var yubiKeySerial: String?
    public var yubiKeyProduct: String?
    public var yubiKeyFirmware: String?
    public var unlockSecondsRemaining: Int?
    public var warning: String?
    public var activePlanID: String?
    public var needsExecutionPrompt: Bool
    public var onboardingComplete: Bool
    public var managedSerial: String?
    public var helperStatus: String?

    public init(
        state: GateState,
        pendingReviewCount: Int,
        todayUnlocks: Int,
        yubiKeyPresent: Bool,
        yubiKeySerial: String? = nil,
        yubiKeyProduct: String? = nil,
        yubiKeyFirmware: String? = nil,
        unlockSecondsRemaining: Int? = nil,
        warning: String? = nil,
        activePlanID: String? = nil,
        needsExecutionPrompt: Bool = false,
        onboardingComplete: Bool = false,
        managedSerial: String? = nil,
        helperStatus: String? = nil
    ) {
        self.state = state
        self.pendingReviewCount = pendingReviewCount
        self.todayUnlocks = todayUnlocks
        self.yubiKeyPresent = yubiKeyPresent
        self.yubiKeySerial = yubiKeySerial
        self.yubiKeyProduct = yubiKeyProduct
        self.yubiKeyFirmware = yubiKeyFirmware
        self.unlockSecondsRemaining = unlockSecondsRemaining
        self.warning = warning
        self.activePlanID = activePlanID
        self.needsExecutionPrompt = needsExecutionPrompt
        self.onboardingComplete = onboardingComplete
        self.managedSerial = managedSerial
        self.helperStatus = helperStatus
    }
}

public actor GateCoordinator {
    private let database: TradeGateDatabase
    private let yubiKey: any YubiKeyControlling
    private var state: GateState = .locked
    private var managedSerial: String?
    private var activePlanID: String?
    private var unlockDeadline: Date?
    private var needsExecutionPrompt = false
    private var warning: String?
    private var seenDevice = false
    private var lastDevices: [YubiKeyDevice] = []
    private var lastProbe: Date = .distantPast

    public init(database: TradeGateDatabase, yubiKey: any YubiKeyControlling) {
        self.database = database
        self.yubiKey = yubiKey
    }

    public func boot() async {
        state = .locked
        _ = try? database.appendAudit(AuditEventDraft(eventType: .daemonStarted))
        await reconcile(now: Date())
        if state != .lockStateUnknown, state != .errorFailClosed {
            apply(try? evaluate())
        }
    }

    public func snapshot(now: Date = Date(), probeHardware: Bool = true) async -> GateSnapshot {
        await reconcile(now: now, probeHardware: probeHardware)
        let pending = (try? database.pendingReviewCount()) ?? 0
        let today = (try? database.todayUnlockCount(now: now)) ?? 0
        let device = lastDevices.first { $0.serialNumber == managedSerial } ?? lastDevices.first
        let remaining = unlockDeadline.map { max(0, Int($0.timeIntervalSince(now))) }
        return await GateSnapshot(
            state: state,
            pendingReviewCount: pending,
            todayUnlocks: today,
            yubiKeyPresent: device != nil,
            yubiKeySerial: device?.serialNumber,
            yubiKeyProduct: device?.productName,
            yubiKeyFirmware: device?.firmwareVersion,
            unlockSecondsRemaining: state == .unlocked ? remaining : nil,
            warning: warning,
            activePlanID: activePlanID,
            needsExecutionPrompt: needsExecutionPrompt,
            onboardingComplete: (try? database.flag("onboarding_completed")) == "1",
            managedSerial: managedSerial,
            helperStatus: yubiKey.helperStatus()
        )
    }

    @discardableResult
    public func createPlan(_ plan: TradePlan) async throws -> TradePlan {
        let saved = try database.createPlan(plan)
        activePlanID = saved.id
        try evaluateAndStore()
        return saved
    }

    @discardableResult
    public func updatePlan(_ plan: TradePlan) async throws -> TradePlan {
        let saved = try database.updatePlan(plan)
        activePlanID = saved.id
        try evaluateAndStore()
        return saved
    }

    public func approveAndUnlock(planID: String, now: Date = Date()) async throws {
        guard var plan = try database.plan(id: planID) else {
            throw TradeGateError.notFound(planID)
        }
        activePlanID = plan.id
        let facts = try facts(for: plan)
        if let denial = RuleEngine.normalUnlockDenial(state: state, facts: facts) {
            _ = try? database.appendAudit(AuditEventDraft(
                eventType: .unlockDenied,
                application: plan.application,
                symbol: plan.symbol.normalized,
                planID: plan.id,
                metadata: ["reason": denial.rawValue]
            ))
            throw denial
        }
        _ = try database.appendAudit(AuditEventDraft(
            eventType: .planSubmitted,
            application: plan.application,
            symbol: plan.symbol.normalized,
            planID: plan.id,
            timestamp: now
        ))
        plan = try database.approvePlan(id: plan.id)
        try transition(.requestNormalUnlock)
        _ = try database.appendAudit(AuditEventDraft(
            eventType: .unlockRequested,
            application: plan.application,
            symbol: plan.symbol.normalized,
            planID: plan.id,
            timestamp: now
        ))
        _ = try database.appendAudit(AuditEventDraft(
            eventType: .unlockApproved,
            application: plan.application,
            symbol: plan.symbol.normalized,
            planID: plan.id,
            timestamp: now
        ))
        try await performUnlock(application: plan.application, symbol: plan.symbol.normalized, planID: plan.id, now: now, emergency: false)
    }

    public func emergencyUnlock(_ input: EmergencyOverrideInput, now: Date = Date()) async throws -> EmergencyOverride {
        guard GateMachine.transition(state, .requestEmergencyUnlock).isSuccess else {
            throw GateTransitionError.illegal(from: state, event: GateEvent.requestEmergencyUnlock.name)
        }
        let record = try database.recordEmergencyOverride(input)
        try transition(.requestEmergencyUnlock)
        try await performUnlock(
            application: input.application,
            symbol: input.symbol.normalized,
            planID: nil,
            now: now,
            emergency: true
        )
        return record
    }

    public func recordNoTrade(planID: String, disposition: NoTradeDisposition) async throws -> TradePlan {
        let plan = try database.recordNoTrade(planID: planID, disposition: disposition)
        needsExecutionPrompt = false
        try evaluateAndStore()
        return plan
    }

    public func confirmExecution(_ input: ExecutionInput) async throws -> ExecutionRecord {
        let record = try database.confirmExecution(input)
        needsExecutionPrompt = false
        try evaluateAndStore()
        return record
    }

    public func expireUnlockWindow(at date: Date) async {
        guard state == .unlocked, let deadline = unlockDeadline, date >= deadline else { return }
        await lockAfterWindow(now: date)
    }

    public func acknowledgeError() async throws {
        try transition(.acknowledgeError)
        warning = nil
        try evaluateAndStore()
    }

    public func registerDevice(serial: String) async throws {
        let devices = try await yubiKey.listDevices()
        guard let device = devices.first(where: { $0.serialNumber == serial }) else {
            throw YubiKeyControlError.absent
        }
        guard device.isManageable else {
            throw YubiKeyControlError.unsupportedDevice
        }
        managedSerial = serial
        _ = try database.upsertDevice(ManagedDevice(
            serialNumber: device.serialNumber,
            productName: device.productName,
            firmwareVersion: device.firmwareVersion,
            managedFIDO2: true,
            managedU2F: true
        ))
        try await yubiKey.lock(deviceID: serial)
    }

    public func onboardingLockCycle(serial: String) async throws {
        guard let device = try await yubiKey.listDevices().first(where: { $0.serialNumber == serial }),
              device.isManageable
        else {
            throw YubiKeyControlError.unsupportedDevice
        }
        try await yubiKey.lock(deviceID: serial)
        try await yubiKey.unlock(deviceID: serial)
        try await yubiKey.lock(deviceID: serial)
        _ = try database.appendAudit(AuditEventDraft(
            eventType: .yubiKeyUnlocked,
            metadata: ["context": "onboarding", "serial": serial]
        ))
        _ = try database.appendAudit(AuditEventDraft(
            eventType: .yubiKeyLocked,
            metadata: ["context": "onboarding", "serial": serial]
        ))
        try database.setFlag("onboarding_completed", "1")
        state = .locked
    }

    public func currentState() -> GateState {
        state
    }

    private func performUnlock(
        application: TradingApplication,
        symbol: String,
        planID: String?,
        now: Date,
        emergency: Bool
    ) async throws {
        guard let serial = try await managedDeviceID() else {
            try transition(.unlockFailed)
            await finishLock(confirmedFailure: true)
            throw YubiKeyControlError.absent
        }
        do {
            try await yubiKey.unlock(deviceID: serial)
            let opened = try await yubiKey.getState(deviceID: serial)
            guard opened.fidoAvailable else {
                throw YubiKeyControlError.failed("FIDO stayed disabled")
            }
            try transition(.unlockSucceeded)
            let settings = try database.settings()
            unlockDeadline = now.addingTimeInterval(TimeInterval(settings.unlockDurationSeconds))
            needsExecutionPrompt = false
            warning = nil
            _ = try database.appendAudit(AuditEventDraft(
                eventType: .yubiKeyUnlocked,
                application: application,
                symbol: symbol,
                planID: planID,
                metadata: emergency ? ["context": "emergency"] : [:],
                timestamp: now
            ))
            try database.insertUnlockSession(UnlockSession(
                application: application,
                symbol: symbol,
                planID: planID,
                requestedAt: now,
                approvedAt: now,
                unlockedAt: now,
                durationSeconds: settings.unlockDurationSeconds,
                result: emergency ? .emergency : .normal
            ))
        } catch {
            try? transition(.unlockFailed)
            await finishLock(confirmedFailure: true)
            let event: AuditEventType = switch error {
            case YubiKeyControlError.forbiddenCommand, YubiKeyControlError.untrustedExecutable, YubiKeyControlError.unsupportedYkmanVersion:
                .helperError
            default:
                .yubiKeyError
            }
            _ = try? database.appendAudit(AuditEventDraft(eventType: event, metadata: ["message": "\(error)"]))
            throw error
        }
    }

    private func lockAfterWindow(now: Date) async {
        guard GateMachine.transition(state, .timerFired).isSuccess else { return }
        try? transition(.timerFired)
        await finishLock(confirmedFailure: false)
        _ = try? database.appendAudit(AuditEventDraft(eventType: .yubiKeyLocked, timestamp: now))
        needsExecutionPrompt = true
        unlockDeadline = nil
        try? evaluateAndStore()
    }

    private func reconcile(now: Date, probeHardware: Bool = true) async {
        if state == .unlocked, let deadline = unlockDeadline, now >= deadline {
            await lockAfterWindow(now: now)
            return
        }
        let interval: TimeInterval = state == .unlocked ? 2 : 8
        if probeHardware || now.timeIntervalSince(lastProbe) >= interval {
            lastProbe = now
            let devices = await (try? yubiKey.listDevices()) ?? []
            lastDevices = devices
            if managedSerial == nil {
                managedSerial = try? database.enabledManagedSerial()
            }
            if managedSerial == nil {
                managedSerial = devices.first(where: \.isManageable)?.serialNumber
            }
            let present = devices.contains { $0.serialNumber == managedSerial }
            if state == .unlocked, seenDevice, !present {
                warning = "YubiKey 在重新锁定之前被拔出。请重新插入 YubiKey，TradeGate 将立即重新关闭 FIDO。"
                try? transition(.deviceRemovedWhileUnlocked)
                _ = try? database.appendAudit(AuditEventDraft(eventType: .deviceRemovedWhileUnlocked))
                needsExecutionPrompt = false
            }
            if state == .lockStateUnknown, present {
                try? transition(.deviceInserted)
                _ = try? database.appendAudit(AuditEventDraft(eventType: .deviceInserted, metadata: ["serial": managedSerial ?? ""]))
                await finishLock(confirmedFailure: false)
                try? evaluateAndStore()
            }
            if present, state == .locked || state.isIdle {
                if let serial = managedSerial, let device = try? await yubiKey.getState(deviceID: serial), device.fidoAvailable, state != .unlocked, state != .unlocking {
                    try? await yubiKey.lock(deviceID: serial)
                }
            }
            if present, !seenDevice, let serial = managedSerial {
                _ = try? database.appendAudit(AuditEventDraft(eventType: .deviceInserted, metadata: ["serial": serial]))
            }
            if !present, seenDevice {
                _ = try? database.appendAudit(AuditEventDraft(eventType: .deviceRemoved))
            }
            seenDevice = present
        }
        if state.isIdle {
            state = RuleEngine.idleState(facts: (try? currentFacts()) ?? .empty)
        }
    }

    private func finishLock(confirmedFailure: Bool) async {
        guard let serial = managedSerial else {
            try? transition(.lockUnconfirmed)
            warning = "无法确认 FIDO 已关闭。"
            return
        }
        do {
            try await yubiKey.lock(deviceID: serial)
            let after = try await yubiKey.getState(deviceID: serial)
            if after.fidoAvailable {
                try? transition(.lockUnconfirmed)
                warning = "无法确认 FIDO 已关闭。"
                return
            }
            if confirmedFailure {
                try? transition(.confirmedLockedFailure)
            } else if state == .locking {
                try? transition(.lockSucceeded)
            }
        } catch {
            try? transition(.lockUnconfirmed)
            warning = "无法确认 FIDO 已关闭。"
            _ = try? database.appendAudit(AuditEventDraft(eventType: .yubiKeyError, metadata: ["message": "\(error)"]))
        }
    }

    private func managedDeviceID() async throws -> String? {
        if let managedSerial {
            return managedSerial
        }
        let devices = try await yubiKey.listDevices()
        guard let device = devices.first(where: \.isManageable) else { return nil }
        managedSerial = device.serialNumber
        return device.serialNumber
    }

    private func evaluate() throws -> GateState {
        let facts = try currentFacts()
        return try GateMachine.transition(state, .evaluate(facts)).get()
    }

    private func evaluateAndStore() throws {
        guard state.isIdle || state == .locked else { return }
        state = try evaluate()
    }

    private func currentFacts() throws -> GateFacts {
        let plan = try activePlan()
        return try facts(for: plan)
    }

    private func facts(for plan: TradePlan?) throws -> GateFacts {
        let validation = plan.map(PlanValidator.validate)
        return try GateFacts(
            pendingReviewCount: database.pendingReviewCount(),
            hasSavablePlan: validation?.canSave == true,
            planType: plan?.planType,
            signalStatus: plan?.entry?.signalStatus,
            canRequestUnlock: validation?.canRequestUnlock == true && plan?.status != .cancelled && plan?.status != .noExecution
        )
    }

    private func activePlan() throws -> TradePlan? {
        if let activePlanID, let plan = try database.plan(id: activePlanID) {
            return plan
        }
        let open = try database.listPlans().first {
            $0.status == .saved || $0.status == .approved
        }
        activePlanID = open?.id
        return open
    }

    private func transition(_ event: GateEvent) throws {
        state = try GateMachine.transition(state, event).get()
    }

    private func apply(_ newState: GateState?) {
        if let newState {
            state = newState
        }
    }
}

private extension Result where Failure == GateTransitionError {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
