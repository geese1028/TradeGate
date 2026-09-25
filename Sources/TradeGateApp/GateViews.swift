import SwiftUI
import TradeGateCore

struct MenuBarMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("TradeGate")
        Divider()
        Text("YubiKey       \(model.snapshot.state == .unlocked ? "🟢 UNLOCKED" : "🔒 LOCKED")")
        Text("待复盘        \(model.snapshot.pendingReviewCount)")
        Text("今日解锁      \(model.snapshot.todayUnlocks)")
        if let remaining = model.snapshot.unlockSecondsRemaining {
            Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
        }
        Divider()
        Button("开始交易计划") {
            model.route = model.snapshot.pendingReviewCount > 0 ? .reviewRequired : .chooseApp
            openWindow(id: "gate")
        }
        .disabled(model.snapshot.pendingReviewCount > 0 || model.snapshot.state == .unlocked)
        Button("待复盘") { model.route = .reviewRequired; openWindow(id: "gate") }
        Button("Journal") { model.route = .journal; openWindow(id: "gate") }
        Button("Audit") { model.route = .audit; openWindow(id: "gate") }
        Divider()
        Button("Emergency Override") { model.route = .emergency; openWindow(id: "gate") }
        Button("Settings") { model.route = .settings; openWindow(id: "gate") }
    }
}

struct GateRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.route {
            case .home: HomeView(model: model)
            case .reviewRequired: ReviewRequiredView(model: model)
            case .chooseApp: ChooseAppView(model: model)
            case .symbol: SymbolView(model: model)
            case .planType: PlanTypeView(model: model)
            case .entryForm: EntryFormView(model: model)
            case .exitForm: ExitFormView(model: model)
            case .signalPending: SignalPendingView(model: model)
            case .confirm: ConfirmPlanView(model: model)
            case .unlocked: UnlockedView(model: model)
            case .executionPrompt: ExecutionPromptView(model: model)
            case .entryReview: EntryReviewView(model: model)
            case .emergency: EmergencyView(model: model)
            case .emergencyReview: EmergencyReviewView(model: model)
            case .journal: JournalView(model: model)
            case .audit: AuditView(model: model)
            case .settings: SettingsView(model: model)
            case .onboarding: OnboardingView(model: model)
            }
        }
        .padding(20)
        .onChange(of: model.snapshot.needsExecutionPrompt) { needed in
            if needed { model.route = .executionPrompt }
        }
        .onChange(of: model.snapshot.state) { state in
            if state == .unlocked { model.route = .unlocked }
            if state == .reviewRequired, model.route == .home { model.route = .reviewRequired }
        }
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TradeGate").font(.title2)
                Spacer()
                Text(model.snapshot.state.menuSymbol)
            }
            labeled("YubiKey", model.snapshot.state == .unlocked ? "UNLOCKED" : "LOCKED")
            labeled("待复盘", "\(model.snapshot.pendingReviewCount)")
            labeled("今日解锁", "\(model.snapshot.todayUnlocks)")
            if let warning = model.snapshot.warning { Text(warning).foregroundStyle(.orange) }
            Button("开始一次交易计划") { model.route = .chooseApp }
                .disabled(model.snapshot.pendingReviewCount > 0)
            HStack {
                Button("Journal") { model.route = .journal }
                Button("Audit") { model.route = .audit }
                Button("Settings") { model.route = .settings }
            }
            Button("引导设置") { model.route = .onboarding }
        }
    }
}

struct ReviewRequiredView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            Text("REVIEW REQUIRED").font(.title2)
            Text("在完成复盘之前")
            Text("无法正常解锁 YubiKey")
            Button("开始复盘") { model.route = .entryReview }
            Button("Emergency Override →") { model.route = .emergency }
        }
    }
}

struct ChooseAppView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            Text("选择交易应用")
            HStack {
                Button("IBKR\n股票") { model.draft.application = .ibkr; model.route = .symbol }
                Button("Kraken\n加密货币") { model.draft.application = .kraken; model.route = .symbol }
            }
        }
    }
}

struct SymbolView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading) {
            Text("交易标的")
            TextField("NVDA", text: $model.symbolText)
            if !model.recentSymbols.isEmpty {
                Text("最近：")
                ForEach(model.recentSymbols, id: \.self) { symbol in
                    Button(symbol) { model.symbolText = symbol }
                }
            }
            Button("下一步") {
                model.draft.symbol = Symbol(raw: model.symbolText)
                model.route = .planType
            }
            .disabled(model.symbolText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

struct PlanTypeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack {
            Button("入场") {
                model.draft.planType = .entry
                model.draft.entry = EntryPlanFields()
                model.draft.exit = nil
                model.route = .entryForm
            }
            Button("出场") {
                model.draft.planType = .exit
                model.draft.exit = ExitPlanFields()
                model.draft.entry = nil
                model.route = .exitForm
            }
        }
    }
}

struct EntryFormView: View {
    @ObservedObject var model: AppModel
    var signalAppeared: Bool { model.signalAppeared }
    var body: some View {
        Form {
            Picker("交易周期", selection: binding(\.timeframe, PlanTimeframe.threeDay)) {
                ForEach(PlanTimeframe.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("运行级别回调", selection: binding(\.majorPullback, MajorPullback.twoLeg)) {
                Text("一段回调").tag(MajorPullback.oneLeg)
                Text("两段回调").tag(MajorPullback.twoLeg)
                Text("横盘").tag(MajorPullback.sideways)
            }
            Picker("中周期回调", selection: binding(\.mediumPullback, MediumPullback.oneLeg)) {
                Text("一段回调").tag(MediumPullback.oneLeg)
                Text("两段回调").tag(MediumPullback.twoLeg)
                Text("不明确").tag(MediumPullback.unclear)
            }
            Picker("底背离级别", selection: binding(\.smallDivergence, SmallDivergenceTimeframe.m15)) {
                Text("5m").tag(SmallDivergenceTimeframe.m5)
                Text("15m").tag(SmallDivergenceTimeframe.m15)
                Text("30m").tag(SmallDivergenceTimeframe.m30)
                Text("1H").tag(SmallDivergenceTimeframe.h1)
                Text("2H").tag(SmallDivergenceTimeframe.h2)
                Text("4H").tag(SmallDivergenceTimeframe.h4)
                Text("尚未出现").tag(SmallDivergenceTimeframe.notYet)
                Text("其他").tag(SmallDivergenceTimeframe.other)
            }
            if model.draft.entry?.smallDivergence == .other {
                TextField("其他", text: $model.customDivergence)
            }
            Picker("进场信号", selection: $model.signalAppeared) {
                Text("已出现").tag(true)
                Text("未出现").tag(false)
            }
            if signalAppeared {
                Picker("信号级别", selection: binding(\.signalTimeframe, SignalTimeframe.m30)) {
                    Text("5m").tag(SignalTimeframe.m5)
                    Text("30m").tag(SignalTimeframe.m30)
                    Text("1H").tag(SignalTimeframe.h1)
                }
                TextField("止损价格", text: $model.stopText)
                TextField("计划仓位 %", text: $model.positionText)
            }
            Button("保存计划") { Task { await save() } }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<EntryPlanFields, T?>, _ fallback: T) -> Binding<T> {
        Binding {
            model.draft.entry?[keyPath: keyPath] ?? fallback
        } set: { newValue in
            if model.draft.entry == nil { model.draft.entry = EntryPlanFields() }
            model.draft.entry?[keyPath: keyPath] = newValue
        }
    }

    private func save() async {
        model.draft.entry?.signalStatus = model.signalAppeared ? .appeared : .notAppeared
        model.draft.entry?.smallDivergenceCustom = model.customDivergence
        if model.signalAppeared {
            model.draft.entry?.stopPrice = try? DecimalValue(parsing: model.stopText)
            model.draft.entry?.positionMode = .percent
            model.draft.entry?.positionValue = try? DecimalValue(parsing: model.positionText)
        } else {
            model.draft.entry?.signalTimeframe = nil
            model.draft.entry?.stopPrice = nil
            model.draft.entry?.positionMode = nil
            model.draft.entry?.positionValue = nil
        }
        let payload = (try? json(model.draft)) ?? ""
        await model.perform("createPlan", payload: payload)
        model.route = model.signalAppeared ? .confirm : .signalPending
    }
}

struct ExitFormView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Picker("运行级别", selection: exitBinding(\.timeframe, PlanTimeframe.threeDay)) {
                ForEach(PlanTimeframe.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("次级运行状态", selection: exitBinding(\.secondaryState, ExitSecondaryState.oneLegUp)) {
                Text("一段上涨").tag(ExitSecondaryState.oneLegUp)
                Text("两段上涨").tag(ExitSecondaryState.twoLegUp)
                Text("顶背离").tag(ExitSecondaryState.topDivergence)
                Text("不明确").tag(ExitSecondaryState.unclear)
            }
            Picker("离场计划", selection: exitBinding(\.exitStrategy, ExitStrategy.fullExitOnBreak)) {
                Text("跌破次级别全部离场").tag(ExitStrategy.fullExitOnBreak)
                Text("减仓等待").tag(ExitStrategy.reduceAndWait)
                Text("自定义").tag(ExitStrategy.custom)
            }
            if model.draft.exit?.exitStrategy == .custom { TextField("自定义", text: $model.exitCustom) }
            TextField("计划离场价格", text: $model.exitPrice)
            Button("确认") {
                model.draft.exit?.plannedExitPrice = try? DecimalValue(parsing: model.exitPrice)
                model.draft.exit?.customExitStrategy = model.exitCustom
                model.draft.exit?.exitPositionMode = .all
                Task {
                    await model.perform("createPlan", payload: (try? json(model.draft)) ?? "")
                    model.route = .confirm
                }
            }
        }
    }

    private func exitBinding<T>(_ keyPath: WritableKeyPath<ExitPlanFields, T?>, _ fallback: T) -> Binding<T> {
        Binding {
            model.draft.exit?[keyPath: keyPath] ?? fallback
        } set: { newValue in
            if model.draft.exit == nil { model.draft.exit = ExitPlanFields() }
            model.draft.exit?[keyPath: keyPath] = newValue
        }
    }
}

struct SignalPendingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("✓ 交易计划已保存")
            Text("进场信号尚未出现。")
            Text("YubiKey 保持锁定。")
            Button("信号出现了") { model.route = .entryForm }
        }
    }
}

struct ConfirmPlanView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(model.draft.application.rawValue.uppercased()) / \(model.draft.symbol.normalized)")
            Text(model.draft.planType == .entry ? "ENTRY PLAN" : "EXIT PLAN")
            Text("运行级别 \(model.draft.entry?.timeframe?.rawValue ?? model.draft.exit?.timeframe?.rawValue ?? "")")
            Text("止损 \(model.draft.entry?.stopPrice?.storage ?? "-")")
            Text("计划仓位 \(model.draft.entry?.positionValue?.storage ?? "")%")
            Button("批准并请求解锁") {
                Task {
                    guard let id = model.plans.first?.id ?? model.snapshot.activePlanID else { return }
                    await model.perform("approve", payload: #"{"id":"\#(id)"}"#)
                }
            }
            Button("返回修改") { model.route = model.draft.planType == .entry ? .entryForm : .exitForm }
        }
    }
}

struct UnlockedView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack {
            Text("YubiKey")
            Text("🟢 UNLOCKED")
            if let remaining = model.snapshot.unlockSecondsRemaining {
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60)).font(.largeTitle)
            }
        }
    }
}

struct ExecutionPromptView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading) {
            Text("刚才是否发生实际交易？")
            if !model.traded {
                Button("没有交易") {
                    Task {
                        let id = model.snapshot.activePlanID ?? ""
                        await model.perform("noTrade", payload: #"{"id":"\#(id)","disposition":"NO_EXECUTION"}"#)
                        model.route = .home
                    }
                }
                Button("已成交") { model.traded = true }
            } else {
                TextField("实际成交价格", text: $model.fillPrice)
                TextField("实际成交仓位", text: $model.fillSize)
                Button("确认成交") {
                    Task {
                        guard let parsedPrice = try? DecimalValue(parsing: model.fillPrice) else { return }
                        let input = ExecutionInput(
                            planID: model.snapshot.activePlanID,
                            price: parsedPrice,
                            positionMode: .quantity,
                            positionValue: try? DecimalValue(parsing: model.fillSize)
                        )
                        await model.perform("execution", payload: (try? json(input)) ?? "")
                        model.route = .reviewRequired
                    }
                }
            }
        }
    }
}

struct EntryReviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Text("计划 vs 实际")
            Picker("是否按照计划执行？", selection: $model.adherence) {
                Text("完全执行").tag(PlanAdherence.exact)
                Text("有偏差").tag(PlanAdherence.deviation)
                Text("明显偏离计划").tag(PlanAdherence.significantDeviation)
            }
            if model.adherence != .exact { TextField("偏离原因", text: $model.deviationReason) }
            Button("完成复盘") {
                Task {
                    let pendingReply = await model.perform("pendingReviews")
                    guard let pending = decodeEnvelope(PendingReviews.self, from: pendingReply),
                          let execution = pending.executions.last(where: \.reviewRequired) else { return }
                    let started = await model.perform("startReview", payload: #"{"id":"\#(execution.id)"}"#)
                    guard let review = decodeEnvelope(ReviewRecord.self, from: started) else { return }
                    guard let stop = try? DecimalValue(parsing: "1"),
                          let size = try? DecimalValue(parsing: "20") else { return }
                    let actuals = EntryReviewActuals(
                        timeframe: .threeDay, majorPullback: .twoLeg, mediumPullback: .oneLeg,
                        smallDivergence: .m15, signalStatus: .appeared, signalTimeframe: .m30,
                        stopPrice: stop, positionMode: .percent,
                        positionValue: size,
                        executionPrice: execution.executionPrice, adherence: model.adherence, deviationReason: model.deviationReason
                    )
                    let payload = EntryReviewPayload(reviewID: review.id, actuals: actuals)
                    await model.perform("completeEntryReview", payload: (try? json(payload)) ?? "")
                    model.route = .home
                }
            }
        }
    }
}

struct EmergencyView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("⚠ 紧急解锁")
            Text("这次操作将永久写入 TradeGate Audit Log。")
            TextField("标的", text: $model.emergencySymbol)
            Picker("原因", selection: $model.emergencyCategory) {
                Text("持仓风险").tag(EmergencyReasonCategory.positionRisk)
                Text("Broker / 系统故障").tag(EmergencyReasonCategory.brokerOrSystemFailure)
                Text("无法完成正常计划").tag(EmergencyReasonCategory.cannotCompleteNormalPlan)
                Text("行情异常").tag(EmergencyReasonCategory.abnormalMarket)
                Text("其他").tag(EmergencyReasonCategory.other)
            }
            TextField("原因（至少 10 个字）", text: $model.emergencyReason)
            TextField("输入 EMERGENCY UNLOCK", text: $model.emergencyPhrase)
            if model.emergencyArmedAt == nil {
                Button("开始 20 秒倒计时") { model.emergencyArmedAt = Date() }
                    .disabled(model.emergencyReason.trimmingCharacters(in: .whitespaces).count < 10 || model.emergencyPhrase != "EMERGENCY UNLOCK")
            } else if Date().timeIntervalSince(model.emergencyArmedAt ?? Date()) < 20 {
                Text("请等待倒计时")
            } else {
                Button("确认紧急解锁") {
                    Task {
                        let input = EmergencyOverrideInput(
                            application: model.draft.application,
                            symbol: Symbol(raw: model.emergencySymbol),
                            reasonCategory: model.emergencyCategory,
                            reasonText: model.emergencyReason,
                            confirmationPhrase: model.emergencyPhrase
                        )
                        await model.perform("emergency", payload: (try? json(input)) ?? "")
                    }
                }
            }
        }
    }
}

struct EmergencyReviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            TextField("为什么使用 Emergency Override？", text: $model.emergencyWhy)
            TextField("下次如何避免？", text: $model.emergencyNext)
            Button("完成紧急复盘") {
                Task { model.route = .home }
            }
            .disabled(model.emergencyWhy.isEmpty || model.emergencyNext.isEmpty)
        }
    }
}

struct JournalView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        List(model.journal, id: \.plan.id) { entry in
            VStack(alignment: .leading) {
                Text(entry.plan.symbol.normalized)
                Text(entry.plan.application.rawValue.uppercased())
                Text(entry.plan.planType == .entry ? "ENTRY PLAN" : "EXIT PLAN")
                Text(entry.executions.isEmpty ? "NO EXECUTION" : "EXECUTION")
                Text(entry.reviewCompleted ? "REVIEW" : "REVIEW REQUIRED")
            }
        }
        .task { await model.perform("journal") }
    }
}

struct AuditView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        List(model.audit, id: \.id) { event in
            Text("\(event.eventType.rawValue)  \(event.symbol ?? "")")
        }
        .task { await model.perform("audit") }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Picker("Unlock duration", selection: $model.settings.unlockDurationSeconds) {
                ForEach(UnlockDuration.allCases, id: \.rawValue) { Text("\($0.rawValue) sec").tag($0.rawValue) }
            }
            Stepper("Emergency countdown \(model.settings.emergencyCountdownSeconds) sec", value: $model.settings.emergencyCountdownSeconds, in: 5...120)
            Toggle("Start at login", isOn: $model.settings.startAtLogin)
            Toggle("Notification", isOn: $model.settings.notificationsEnabled)
            Text("Database \(TradeGatePaths.databasePath)")
            Button("保存") { Task { await model.perform("updateSettings", payload: (try? json(model.settings)) ?? "") } }
            Button("Export JSON") { Task { await model.perform("export") } }
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("检测 daemon：本进程内的 Gate 已启动")
            Text(model.snapshot.yubiKeyPresent ? "检测到 YubiKey \(model.snapshot.yubiKeyProduct ?? "")" : "请插入 YubiKey")
            Text("Serial: \(model.snapshot.yubiKeySerial ?? "-")")
            Text("Firmware: \(model.snapshot.yubiKeyFirmware ?? "-")")
            Text("TradeGate 将临时关闭该 YubiKey 的 FIDO 功能，以增加交易账户登录前的操作摩擦。它不会删除 Passkey 或重置 YubiKey。")
            Button("测试 LOCK / UNLOCK / LOCK") {
                Task {
                    let serial = model.snapshot.yubiKeySerial ?? "12345678"
                    await model.perform("register", payload: #"{"id":"\#(serial)"}"#)
                    await model.perform("onboardingCycle", payload: #"{"id":"\#(serial)"}"#)
                    model.route = .home
                }
            }
        }
    }
}

private func labeled(_ title: String, _ value: String) -> some View {
    HStack { Text(title); Spacer(); Text(value) }
}

private func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(value), encoding: .utf8) ?? ""
}

private struct Envelope<T: Decodable>: Decodable {
    var result: T?
}

func decodeEnvelope<T: Decodable>(_ type: T.Type, from reply: String) -> T? {
    guard let data = reply.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(Envelope<T>.self, from: data))?.result
}
