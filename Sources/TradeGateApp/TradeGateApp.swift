import AppKit
import ServiceManagement
import SwiftUI
import TradeGateCore
import UserNotifications

@main
struct TradeGateApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            Text("\(model.snapshot.state.menuSymbol) TradeGate")
        }
        Window("TradeGate", id: "gate") {
            GateRootView(model: model)
                .frame(minWidth: 460, minHeight: 560)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot = GateSnapshot(
        state: .lockStateUnknown,
        pendingReviewCount: 0,
        todayUnlocks: 0,
        yubiKeyPresent: false
    )
    @Published var route: GateRoute = .home
    @Published var plans: [TradePlan] = []
    @Published var journal: [JournalEntry] = []
    @Published var audit: [AuditEvent] = []
    @Published var dashboard = DashboardStats(
        unlockCount: 0, emergencyCount: 0, tradeCount: 0, noExecutionUnlockCount: 0,
        exactCount: 0, deviationCount: 0, significantDeviationCount: 0,
        positionDeviationCount: 0, stopDeviationCount: 0, earlyEntryCount: 0
    )
    @Published var recentSymbols: [String] = []
    @Published var settings = TradeGateSettings()
    @Published var errorText: String?
    @Published var symbolText = ""
    @Published var signalAppeared = true
    @Published var stopText = ""
    @Published var positionText = "20"
    @Published var entryPositionMode = PositionMode.percent
    @Published var exitPositionMode = ExitPositionMode.all
    @Published var exitPositionText = ""
    @Published var customDivergence = ""
    @Published var exitPrice = ""
    @Published var exitCustom = ""
    @Published var traded = false
    @Published var fillPrice = ""
    @Published var fillSize = ""
    @Published var fillPositionMode = ExecutionPositionMode.quantity
    @Published var adherence = PlanAdherence.exact
    @Published var deviationReason = ""
    @Published var emergencyApplication = TradingApplication.ibkr
    @Published var emergencySymbol = ""
    @Published var emergencyReason = ""
    @Published var emergencyPhrase = ""
    @Published var emergencyCategory = EmergencyReasonCategory.positionRisk
    @Published var emergencyArmedAt: Date?
    @Published var emergencyWhy = ""
    @Published var emergencyNext = ""
    @Published var emergencyDidTrade = false
    @Published var emergencyChangedPosition = false
    @Published var emergencyCouldNormal = false
    @Published var reviewWork: [ReviewWorkItem] = []
    @Published var auditDay = ""
    @Published var auditSymbol = ""
    @Published var auditEmergencyOnly = false
    @Published var auditApplication = ""
    @Published var auditEventType = ""
    @Published var selectedPlanID: String?
    @Published var revisions: [PlanRevision] = []
    @Published var actualTimeframe = PlanTimeframe.threeDay
    @Published var actualMajor = MajorPullback.twoLeg
    @Published var actualMedium = MediumPullback.oneLeg
    @Published var actualDivergence = SmallDivergenceTimeframe.m15
    @Published var actualSignal = SignalTimeframe.m30
    @Published var actualStop = ""
    @Published var actualPosition = ""
    @Published var actualExitState = ExitSecondaryState.oneLegUp
    @Published var actualExitStrategy = ExitStrategy.fullExitOnBreak
    @Published var actualExitPrice = ""
    @Published var actualExitPositionMode = ExitPositionMode.all
    @Published var actualExitPositionText = ""
    @Published var draft = TradePlan(application: .ibkr, symbol: Symbol(raw: ""), planType: .entry, entry: EntryPlanFields())
    private let inProcess: (coordinator: GateCoordinator, database: TradeGateDatabase)?
    private var lastState: GateState?

    init() {
        if ProcessInfo.processInfo.arguments.contains("--in-process") {
            let directory = TradeGatePaths.supportDirectory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let database = (try? TradeGateDatabase(path: TradeGatePaths.databasePath))
                ?? (try? TradeGateDatabase(path: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tradegate-app.sqlite").path))
            if let database {
                let coordinator = GateCoordinator(database: database, yubiKey: MockYubiKeyController())
                inProcess = (coordinator, database)
                Task { await coordinator.boot() }
            } else {
                inProcess = nil
            }
        } else {
            inProcess = nil
            let daemon = SMAppService.daemon(plistName: "com.tradegate.daemon.plist")
            do {
                try daemon.register()
                NSLog("TradeGate SMAppService.register succeeded status=\(daemon.status)")
            } catch {
                NSLog("TradeGate SMAppService.register failed status=\(daemon.status) error=\(error)")
            }
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task {
            await refresh()
            _ = await call("appStarted")
        }
    }

    func refresh() async {
        let reply = await call("snapshot", #"{"probe":false}"#)
        guard let next = decodeEnvelope(GateSnapshot.self, from: reply) else {
            snapshot = GateSnapshot(
                state: .lockStateUnknown,
                pendingReviewCount: snapshot.pendingReviewCount,
                todayUnlocks: snapshot.todayUnlocks,
                yubiKeyPresent: false,
                warning: "无法连接 TradeGate daemon。FIDO 状态未知。"
            )
            return
        }
        if let lastState, lastState != next.state {
            notify(next)
        }
        lastState = next.state
        snapshot = next
        if next.needsExecutionPrompt {
            route = .executionPrompt
        } else if next.state == .reviewRequired, route == .home {
            route = .reviewRequired
        }
    }

    @discardableResult
    func perform(_ action: String, payload: String = "") async -> String {
        let reply = await call(action, payload)
        if reply.contains("\"ok\":false") {
            errorText = readableError(in: reply)
        } else if !reply.isEmpty {
            errorText = nil
        }
        await refresh()
        absorb(action, reply: reply)
        return reply
    }

    private func absorb(_ action: String, reply: String) {
        switch action {
        case "journal":
            if let value = decodeEnvelope([JournalEntry].self, from: reply) {
                journal = value
            }
        case "audit":
            if let value = decodeEnvelope([AuditEvent].self, from: reply) {
                audit = value
            }
        case "dashboard":
            if let value = decodeEnvelope(DashboardStats.self, from: reply) {
                dashboard = value
            }
        case "recentSymbols":
            if let value = decodeEnvelope([String].self, from: reply) {
                recentSymbols = value
            }
        case "settings":
            if let value = decodeEnvelope(TradeGateSettings.self, from: reply) {
                settings = value
            }
        case "reviewQueue":
            if let value = decodeEnvelope([ReviewWorkItem].self, from: reply) {
                reviewWork = value
            }
        case "plans":
            if let value = decodeEnvelope([TradePlan].self, from: reply) {
                plans = value
            }
        default:
            break
        }
    }

    func beginExecutionReport() {
        if draft.entry?.positionMode == .percent || draft.exit?.exitPositionMode == .percent {
            fillPositionMode = .percent
        } else if draft.exit?.exitPositionMode == .all, draft.entry == nil {
            fillPositionMode = .all
        } else {
            fillPositionMode = .quantity
        }
        traded = true
    }

    func beginNewPlan() {
        draft = TradePlan(application: .ibkr, symbol: Symbol(raw: ""), planType: .entry, entry: EntryPlanFields())
        signalAppeared = true
        stopText = ""
        positionText = "20"
        entryPositionMode = .percent
        exitPositionMode = .all
        exitPositionText = ""
        symbolText = ""
        route = .chooseApp
    }

    func saveDraft() async -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = (try? encoder.encode(draft)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let action = snapshot.activePlanID == draft.id ? "updatePlan" : "createPlan"
        let reply = await perform(action, payload: encoded)
        return reply.contains("\"ok\":true")
    }

    func auditPayload() -> String {
        let filter = AuditFilter(
            day: auditDay.isEmpty ? nil : auditDay,
            application: TradingApplication(rawValue: auditApplication),
            symbol: auditSymbol.isEmpty ? nil : auditSymbol.uppercased(),
            eventType: AuditEventType(rawValue: auditEventType),
            emergencyOnly: auditEmergencyOnly
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(filter), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    func seedReview(_ item: ReviewWorkItem) {
        if let entry = item.plan?.entry {
            actualTimeframe = entry.timeframe ?? .threeDay
            actualMajor = entry.majorPullback ?? .twoLeg
            actualMedium = entry.mediumPullback ?? .oneLeg
            actualDivergence = entry.smallDivergence ?? .m15
            actualSignal = entry.signalTimeframe ?? .m30
            actualStop = entry.stopPrice?.storage ?? ""
            actualPosition = entry.positionValue?.storage ?? ""
        }
        if let exit = item.plan?.exit {
            actualTimeframe = exit.timeframe ?? .threeDay
            actualExitState = exit.secondaryState ?? .oneLegUp
            actualExitStrategy = exit.exitStrategy ?? .fullExitOnBreak
            actualExitPrice = exit.plannedExitPrice?.storage ?? ""
            actualExitPositionMode = exit.exitPositionMode ?? .all
            actualExitPositionText = exit.exitPositionValue?.storage ?? ""
        }
        if let price = item.execution?.executionPrice.storage {
            fillPrice = price
        }
    }

    private func call(_ action: String, _ payload: String = "") async -> String {
        if let inProcess {
            return await GateRouter.perform(
                coordinator: inProcess.coordinator,
                database: inProcess.database,
                action: action,
                payload: payload
            )
        }
        return await withCheckedContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: TradeGatePaths.machService, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: TradeGateXPC.self)
            connection.resume()
            guard let proxy = connection.remoteObjectProxy as? TradeGateXPC else {
                connection.invalidate()
                continuation.resume(returning: "")
                return
            }
            proxy.perform(action: action, payload: payload) { reply in
                connection.invalidate()
                continuation.resume(returning: reply)
            }
        }
    }

    private func readableError(in reply: String) -> String {
        guard let data = reply.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? String
        else {
            return "操作没有完成。"
        }
        return translatedValidation(error)
    }

    private func translatedValidation(_ error: String) -> String {
        let messages = [
            "emptySymbol": "请填写标的。",
            "missingTimeframe": "请选择周期。",
            "missingMajorPullback": "请选择运行级别回调。",
            "missingMediumPullback": "请选择中周期回调。",
            "missingSmallDivergence": "请选择底背离级别。",
            "missingCustomDivergence": "选了「其他」就要写上具体级别。",
            "missingSignalTimeframe": "信号出现后要选择 5m、30m 或 1H。",
            "missingStopPrice": "请填写止损价格。",
            "stopPriceNotPositive": "止损价格要是正数。",
            "missingPosition": "仓位没有填上。百分比可以写 50 或 50%。",
            "missingExitPosition": "请选择离场仓位。",
            "positionNotPositive": "仓位要是正数。",
            "percentOutOfRange": "百分比要在 0 和 100 之间。",
            "missingSecondaryState": "请选择次级运行状态。",
            "missingExitStrategy": "请选择离场计划。",
            "missingCustomExitStrategy": "选了自定义离场计划，就要写上内容。",
            "missingPlannedExitPrice": "请填写离场价格。",
            "exitPriceNotPositive": "离场价格要是正数。",
            "reasonTooShort": "紧急解锁的原因至少要 10 个字。",
            "confirmationPhraseMismatch": "确认短语必须是 EMERGENCY UNLOCK。",
            "missingDeviationReason": "没有完全按计划执行时，要写上偏离原因。",
        ]
        for (key, message) in messages where error.contains(key) {
            return message
        }
        if error.contains("TradeGateCore") || error.contains("validation(") {
            return "这一步没有通过，请检查刚填的内容。"
        }
        return error
    }

    private func notify(_ snapshot: GateSnapshot) {
        guard settings.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        switch snapshot.state {
        case .unlocked:
            content.title = "YubiKey unlocked"
        case .locked, .planRequired, .signalPending, .ready:
            content.title = "YubiKey locked"
        case .reviewRequired:
            content.title = "Review required"
        case .lockStateUnknown:
            content.title = "YubiKey removed before relock"
        default:
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

enum GateRoute {
    case home
    case reviewRequired
    case chooseApp
    case symbol
    case planType
    case entryForm
    case exitForm
    case signalPending
    case confirm
    case unlocked
    case executionPrompt
    case entryReview
    case emergency
    case emergencyReview
    case exitReview
    case dashboard
    case tradeDetail
    case journal
    case audit
    case settings
    case onboarding
}
