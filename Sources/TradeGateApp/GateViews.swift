import ServiceManagement
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
            if model.snapshot.pendingReviewCount > 0 {
                model.route = .reviewRequired
            } else {
                model.beginNewPlan()
            }
            openWindow(id: "gate")
        }
        .disabled(model.snapshot.pendingReviewCount > 0 || model.snapshot.state == .unlocked)
        Button("待复盘") { model.route = .reviewRequired; openWindow(id: "gate") }
        Button("Journal") { model.route = .journal; openWindow(id: "gate") }
        Button("Audit") { model.route = .audit; openWindow(id: "gate") }
        Button("统计") { model.route = .dashboard; openWindow(id: "gate") }
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
            case .exitReview: ExitReviewView(model: model)
            case .dashboard: DashboardView(model: model)
            case .tradeDetail: TradeDetailView(model: model)
            case .journal: JournalView(model: model)
            case .audit: AuditView(model: model)
            case .settings: SettingsView(model: model)
            case .onboarding: OnboardingView(model: model)
            }
        }
        .padding(20)
        .safeAreaInset(edge: .bottom) {
            if let errorText = model.errorText {
                HStack {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("关闭") { model.errorText = nil }
                }
                .padding(8)
            }
        }
        .onChange(of: model.snapshot.needsExecutionPrompt) { needed in
            if needed {
                model.route = .executionPrompt
            }
        }
        .onChange(of: model.snapshot.state) { state in
            if state == .unlocked {
                model.route = .unlocked
            }
            if state == .reviewRequired, model.route == .home {
                model.route = .reviewRequired
            }
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
            if let warning = model.snapshot.warning {
                Text(warning).foregroundStyle(.orange)
            }
            Button("开始一次交易计划") { model.beginNewPlan() }
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
            if let item = model.reviewWork.first {
                Text("\(item.application.rawValue.uppercased()) / \(item.symbol)")
                Text(item.kind == "emergency" ? "紧急解锁" : (item.kind == "exit" ? "出场" : "入场"))
            }
            Text("在完成复盘之前")
            Text("无法正常解锁 YubiKey")
            Button("开始复盘") {
                guard let item = model.reviewWork.first else { return }
                model.seedReview(item)
                switch item.kind {
                case "emergency": model.route = .emergencyReview
                case "exit": model.route = .exitReview
                default: model.route = .entryReview
                }
            }
            .task { await model.perform("reviewQueue") }
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
    var signalAppeared: Bool {
        model.signalAppeared
    }

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
                Picker("计划仓位", selection: $model.entryPositionMode) {
                    Text("账户比例").tag(PositionMode.percent)
                    Text("数量").tag(PositionMode.quantity)
                }
                TextField(model.entryPositionMode == .percent ? "百分比" : "Shares / Units", text: $model.positionText)
            }
            Button("保存计划") { Task { await save() } }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<EntryPlanFields, T?>, _ fallback: T) -> Binding<T> {
        Binding {
            model.draft.entry?[keyPath: keyPath] ?? fallback
        } set: { newValue in
            if model.draft.entry == nil {
                model.draft.entry = EntryPlanFields()
            }
            model.draft.entry?[keyPath: keyPath] = newValue
        }
    }

    private func save() async {
        model.draft.entry?.signalStatus = model.signalAppeared ? .appeared : .notAppeared
        model.draft.entry?.smallDivergenceCustom = model.customDivergence
        if model.signalAppeared {
            model.draft.entry?.stopPrice = try? DecimalValue(parsing: model.stopText)
            model.draft.entry?.positionMode = model.entryPositionMode
            model.draft.entry?.positionValue = try? DecimalValue(parsing: model.positionText)
        } else {
            model.draft.entry?.signalTimeframe = nil
            model.draft.entry?.stopPrice = nil
            model.draft.entry?.positionMode = nil
            model.draft.entry?.positionValue = nil
        }
        guard await model.saveDraft() else { return }
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
            if model.draft.exit?.exitStrategy == .custom {
                TextField("自定义", text: $model.exitCustom)
            }
            TextField("计划离场价格", text: $model.exitPrice)
            Picker("计划离场仓位", selection: $model.exitPositionMode) {
                Text("全部").tag(ExitPositionMode.all)
                Text("百分比").tag(ExitPositionMode.percent)
                Text("数量").tag(ExitPositionMode.quantity)
            }
            if model.exitPositionMode != .all {
                TextField(model.exitPositionMode == .percent ? "百分比" : "Shares / Units", text: $model.exitPositionText)
            }
            Button("确认") {
                model.draft.exit?.plannedExitPrice = try? DecimalValue(parsing: model.exitPrice)
                model.draft.exit?.customExitStrategy = model.exitCustom
                model.draft.exit?.exitPositionMode = model.exitPositionMode
                model.draft.exit?.exitPositionValue = model.exitPositionMode == .all ? nil : (try? DecimalValue(parsing: model.exitPositionText))
                Task {
                    guard await model.saveDraft() else { return }
                    model.route = .confirm
                }
            }
        }
    }

    private func exitBinding<T>(_ keyPath: WritableKeyPath<ExitPlanFields, T?>, _ fallback: T) -> Binding<T> {
        Binding {
            model.draft.exit?[keyPath: keyPath] ?? fallback
        } set: { newValue in
            if model.draft.exit == nil {
                model.draft.exit = ExitPlanFields()
            }
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
            if let entry = model.draft.entry {
                Text("运行级别 \(entry.timeframe?.rawValue ?? "-")")
                Text("运行级回调 \(entry.majorPullback?.rawValue ?? "-")")
                Text("中周期回调 \(entry.mediumPullback?.rawValue ?? "-")")
                Text("底背离 \(entry.smallDivergence?.rawValue ?? "-")")
                Text("进场信号 \(entry.signalStatus == .appeared ? "已出现" : "未出现")")
                Text("信号级别 \(entry.signalTimeframe?.rawValue ?? "-")")
                Text("止损 \(entry.stopPrice?.storage ?? "-")")
                Text("计划仓位 \(entry.positionValue?.storage ?? "-") \(entry.positionMode?.rawValue ?? "")")
            }
            if let exit = model.draft.exit {
                Text("运行级别 \(exit.timeframe?.rawValue ?? "-")")
                Text("次级运行状态 \(exit.secondaryState?.rawValue ?? "-")")
                Text("离场计划 \(exit.exitStrategy?.rawValue ?? "-")")
                Text("离场价格 \(exit.plannedExitPrice?.storage ?? "-")")
                Text("离场仓位 \(exit.exitPositionMode?.rawValue ?? "-") \(exit.exitPositionValue?.storage ?? "")")
            }
            Button("批准并请求解锁") {
                Task {
                    let id = model.snapshot.activePlanID ?? model.draft.id
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
                        let id = model.snapshot.activePlanID ?? model.draft.id
                        let reply = await model.perform("noTrade", payload: #"{"id":"\#(id)","disposition":"NO_EXECUTION"}"#)
                        if reply.contains("\"ok\":true") {
                            model.route = .home
                        }
                    }
                }
                Button("已成交") { model.beginExecutionReport() }
            } else {
                TextField("实际成交价格", text: $model.fillPrice)
                Picker("实际成交仓位", selection: $model.fillPositionMode) {
                    Text("全部").tag(ExecutionPositionMode.all)
                    Text("百分比").tag(ExecutionPositionMode.percent)
                    Text("数量").tag(ExecutionPositionMode.quantity)
                }
                if model.fillPositionMode != .all {
                    TextField("仓位", text: $model.fillSize)
                }
                Button("确认成交") {
                    Task {
                        guard let parsedPrice = try? DecimalValue(parsing: model.fillPrice) else { return }
                        let input = ExecutionInput(
                            planID: model.snapshot.activePlanID,
                            price: parsedPrice,
                            positionMode: model.fillPositionMode,
                            positionValue: model.fillPositionMode == .all ? nil : (try? DecimalValue(parsing: model.fillSize))
                        )
                        let reply = await model.perform("execution", payload: (try? json(input)) ?? "")
                        if reply.contains("\"ok\":true") {
                            model.route = .reviewRequired
                        }
                    }
                }
            }
        }
    }
}

struct EntryReviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let plan = model.reviewWork.first?.plan?.entry
        Form {
            Text("计划 vs 实际")
            Text("运行级别 \(plan?.timeframe?.rawValue ?? "-")")
            Picker("实际运行级别", selection: $model.actualTimeframe) {
                ForEach(PlanTimeframe.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text("运行级回调 \(plan?.majorPullback?.rawValue ?? "-")")
            Picker("实际运行级回调", selection: $model.actualMajor) {
                Text("一段").tag(MajorPullback.oneLeg)
                Text("两段").tag(MajorPullback.twoLeg)
                Text("横盘").tag(MajorPullback.sideways)
            }
            Text("中周期 \(plan?.mediumPullback?.rawValue ?? "-")")
            Picker("实际中周期", selection: $model.actualMedium) {
                Text("一段").tag(MediumPullback.oneLeg)
                Text("两段").tag(MediumPullback.twoLeg)
                Text("不明确").tag(MediumPullback.unclear)
            }
            Text("底背离 \(plan?.smallDivergence?.rawValue ?? "-")")
            Picker("实际底背离", selection: $model.actualDivergence) {
                Text("5m").tag(SmallDivergenceTimeframe.m5)
                Text("15m").tag(SmallDivergenceTimeframe.m15)
                Text("30m").tag(SmallDivergenceTimeframe.m30)
                Text("1H").tag(SmallDivergenceTimeframe.h1)
                Text("2H").tag(SmallDivergenceTimeframe.h2)
                Text("4H").tag(SmallDivergenceTimeframe.h4)
            }
            Text("信号级别 \(plan?.signalTimeframe?.rawValue ?? "-")")
            Picker("实际信号级别", selection: $model.actualSignal) {
                Text("5m").tag(SignalTimeframe.m5)
                Text("30m").tag(SignalTimeframe.m30)
                Text("1H").tag(SignalTimeframe.h1)
            }
            Text("止损 \(plan?.stopPrice?.storage ?? "-")")
            TextField("实际止损", text: $model.actualStop)
            Text("仓位 \(plan?.positionValue?.storage ?? "-")")
            TextField("实际仓位", text: $model.actualPosition)
            Text("成交价格")
            TextField("成交价格", text: $model.fillPrice)
            Picker("是否按照计划执行？", selection: $model.adherence) {
                Text("完全执行").tag(PlanAdherence.exact)
                Text("有偏差").tag(PlanAdherence.deviation)
                Text("明显偏离计划").tag(PlanAdherence.significantDeviation)
            }
            if model.adherence != .exact {
                TextField("偏离原因", text: $model.deviationReason)
            }
            Button("完成复盘") { Task { await finishEntryReview(model) } }
        }
    }
}

@MainActor
private func finishEntryReview(_ model: AppModel) async {
    guard let item = model.reviewWork.first(where: { $0.kind == "entry" }),
          let stop = try? DecimalValue(parsing: model.actualStop),
          let size = try? DecimalValue(parsing: model.actualPosition),
          let fill = try? DecimalValue(parsing: model.fillPrice) else { return }
    let started = await model.perform("startReview", payload: #"{"id":"\#(item.targetID)"}"#)
    guard let review = decodeEnvelope(ReviewRecord.self, from: started) else { return }
    let actuals = EntryReviewActuals(
        timeframe: model.actualTimeframe,
        majorPullback: model.actualMajor,
        mediumPullback: model.actualMedium,
        smallDivergence: model.actualDivergence,
        signalStatus: .appeared,
        signalTimeframe: model.actualSignal,
        stopPrice: stop,
        positionMode: item.plan?.entry?.positionMode ?? .percent,
        positionValue: size,
        executionPrice: fill,
        adherence: model.adherence,
        deviationReason: model.deviationReason
    )
    let reply = await model.perform("completeEntryReview", payload: (try? json(EntryReviewPayload(reviewID: review.id, actuals: actuals))) ?? "")
    if reply.contains("\"ok\":true") {
        model.route = .home
    }
}

struct ExitReviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let plan = model.reviewWork.first?.plan?.exit
        Form {
            Text("计划 vs 实际")
            Text("运行级别 \(plan?.timeframe?.rawValue ?? "-")")
            Picker("实际运行级别", selection: $model.actualTimeframe) {
                ForEach(PlanTimeframe.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text("次级运行状态 \(plan?.secondaryState?.rawValue ?? "-")")
            Picker("实际次级状态", selection: $model.actualExitState) {
                Text("一段上涨").tag(ExitSecondaryState.oneLegUp)
                Text("两段上涨").tag(ExitSecondaryState.twoLegUp)
                Text("顶背离").tag(ExitSecondaryState.topDivergence)
                Text("不明确").tag(ExitSecondaryState.unclear)
            }
            Text("离场策略 \(plan?.exitStrategy?.rawValue ?? "-")")
            Picker("实际离场策略", selection: $model.actualExitStrategy) {
                Text("全部离场").tag(ExitStrategy.fullExitOnBreak)
                Text("减仓等待").tag(ExitStrategy.reduceAndWait)
                Text("自定义").tag(ExitStrategy.custom)
            }
            Text("离场价格 \(plan?.plannedExitPrice?.storage ?? "-")")
            TextField("实际离场价格", text: $model.actualExitPrice)
            Text("离场仓位 \(plan?.exitPositionMode?.rawValue ?? "ALL")")
            Picker("是否按计划执行", selection: $model.adherence) {
                Text("完全执行").tag(PlanAdherence.exact)
                Text("有偏差").tag(PlanAdherence.deviation)
                Text("明显偏离计划").tag(PlanAdherence.significantDeviation)
            }
            if model.adherence != .exact {
                TextField("偏离原因", text: $model.deviationReason)
            }
            Button("完成出场复盘") { Task { await finishExitReview(model) } }
        }
    }
}

@MainActor
private func finishExitReview(_ model: AppModel) async {
    guard let item = model.reviewWork.first(where: { $0.kind == "exit" }),
          let price = try? DecimalValue(parsing: model.actualExitPrice) else { return }
    let started = await model.perform("startReview", payload: #"{"id":"\#(item.targetID)"}"#)
    guard let review = decodeEnvelope(ReviewRecord.self, from: started) else { return }
    let actuals = ExitReviewActuals(
        timeframe: model.actualTimeframe,
        secondaryState: model.actualExitState,
        exitStrategy: model.actualExitStrategy,
        plannedExitPrice: price,
        exitPositionMode: item.plan?.exit?.exitPositionMode ?? .all,
        adherence: model.adherence,
        deviationReason: model.deviationReason
    )
    let reply = await model.perform("completeExitReview", payload: (try? json(ExitReviewPayload(reviewID: review.id, actuals: actuals))) ?? "")
    if reply.contains("\"ok\":true") {
        model.route = .home
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
                Button("开始 \(model.settings.emergencyCountdownSeconds) 秒倒计时") { model.emergencyArmedAt = Date() }
                    .disabled(!EmergencyGate.canStartCountdown(reason: model.emergencyReason, phrase: model.emergencyPhrase))
            } else if let armedAt = model.emergencyArmedAt,
                      !EmergencyGate.canConfirm(
                          armedAt: armedAt,
                          now: Date(),
                          countdownSeconds: model.settings.emergencyCountdownSeconds
                      )
            {
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
            Toggle("是否发生交易？", isOn: $model.emergencyDidTrade)
            Toggle("是否改变仓位？", isOn: $model.emergencyChangedPosition)
            Toggle("本次是否本可通过正常流程完成？", isOn: $model.emergencyCouldNormal)
            TextField("下次如何避免？", text: $model.emergencyNext)
            Button("完成紧急复盘") { Task { await finishEmergencyReview(model) } }
                .disabled(model.emergencyWhy.trimmingCharacters(in: .whitespaces).isEmpty || model.emergencyNext.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

@MainActor
private func finishEmergencyReview(_ model: AppModel) async {
    guard let item = model.reviewWork.first(where: { $0.kind == "emergency" }) else { return }
    let started = await model.perform("startEmergencyReview", payload: #"{"id":"\#(item.targetID)"}"#)
    guard let review = decodeEnvelope(ReviewRecord.self, from: started) else { return }
    let answers = EmergencyReviewAnswers(
        why: model.emergencyWhy,
        didTrade: model.emergencyDidTrade,
        changedPosition: model.emergencyChangedPosition,
        couldHaveUsedNormalFlow: model.emergencyCouldNormal,
        howToAvoidNextTime: model.emergencyNext
    )
    let reply = await model.perform(
        "completeEmergencyReview",
        payload: (try? json(EmergencyReviewPayload(reviewID: review.id, answers: answers))) ?? ""
    )
    if reply.contains("\"ok\":true") {
        model.route = .home
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("过去30天").font(.title3)
            Text("Unlock 次数 \(model.dashboard.unlockCount)")
            Text("Emergency Override 次数 \(model.dashboard.emergencyCount)")
            Text("交易次数 \(model.dashboard.tradeCount)")
            Text("无成交 Unlock 次数 \(model.dashboard.noExecutionUnlockCount)")
            Text(String(format: "计划执行率 %.0f%%", model.dashboard.adherenceRate * 100))
            Text("仓位偏离次数 \(model.dashboard.positionDeviationCount)")
            Text("止损偏离次数 \(model.dashboard.stopDeviationCount)")
            Text("提前进场次数 \(model.dashboard.earlyEntryCount)")
        }
        .task { await model.perform("dashboard") }
    }
}

struct JournalView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        List(model.journal, id: \.plan.id) { entry in
            Button {
                model.selectedPlanID = entry.plan.id
                model.route = .tradeDetail
            } label: {
                VStack(alignment: .leading) {
                    Text(entry.plan.symbol.normalized)
                    Text(entry.plan.application.rawValue.uppercased())
                    Text(entry.plan.planType == .entry ? "ENTRY PLAN" : "EXIT PLAN")
                    Text(entry.executions.isEmpty ? "NO EXECUTION" : "EXECUTION")
                    Text(entry.reviewCompleted ? "REVIEW" : "REVIEW REQUIRED")
                }
            }
        }
        .task { await model.perform("journal") }
    }
}

struct AuditView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack {
            TextField("日期 2026-09-25", text: $model.auditDay)
            Picker("应用", selection: $model.auditApplication) {
                Text("全部").tag("")
                Text("IBKR").tag("ibkr")
                Text("Kraken").tag("kraken")
            }
            TextField("标的", text: $model.auditSymbol)
            TextField("事件类型", text: $model.auditEventType)
            Toggle("只看 Emergency", isOn: $model.auditEmergencyOnly)
            Button("筛选") { Task { await model.perform("audit", payload: model.auditPayload()) } }
            List(model.audit, id: \.id) { event in
                Text("\(event.timestampText)  \(event.eventType.rawValue)  \(event.symbol ?? "")")
            }
        }
        .task { await model.perform("audit", payload: model.auditPayload()) }
    }
}

struct TradeDetailView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let planID = model.selectedPlanID
        let events = model.audit.filter { $0.planID == planID }
        VStack(alignment: .leading, spacing: 8) {
            Text(model.journal.first { $0.plan.id == planID }?.plan.symbol.normalized ?? "交易")
                .font(.title3)
            ForEach(model.revisions, id: \.id) { revision in
                Text("Revision \(revision.revisionNumber)  \(revision.createdAt.formatted())")
            }
            ForEach(events, id: \.id) { event in
                Text("\(tradeEventTitle(event.eventType))  \(event.timestampText)")
            }
        }
        .task {
            guard let planID else { return }
            let reply = await model.perform("revisions", payload: #"{"id":"\#(planID)"}"#)
            if let rows = decodeEnvelope([PlanRevision].self, from: reply) {
                model.revisions = rows
            }
        }
    }
}

private func tradeEventTitle(_ type: AuditEventType) -> String {
    switch type {
    case .planCreated: "计划创建"
    case .planUpdated: "计划修改"
    case .planApproved: "计划批准"
    case .yubiKeyUnlocked: "YubiKey Unlock"
    case .executionConfirmed: "成交"
    case .reviewCompleted: "复盘"
    case .noExecution: "没有交易"
    default: type.rawValue
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Picker("Unlock duration", selection: $model.settings.unlockDurationSeconds) {
                ForEach(UnlockDuration.allCases, id: \.rawValue) { Text("\($0.rawValue) sec").tag($0.rawValue) }
            }
            Stepper("Emergency countdown \(model.settings.emergencyCountdownSeconds) sec", value: $model.settings.emergencyCountdownSeconds, in: 5 ... 120)
            Toggle("Start at login", isOn: $model.settings.startAtLogin)
            Toggle("Notification", isOn: $model.settings.notificationsEnabled)
            Text("Database \(TradeGatePaths.databasePath)")
            Button("保存") {
                Task {
                    await model.perform("updateSettings", payload: (try? json(model.settings)) ?? "")
                    if model.settings.startAtLogin {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? await SMAppService.mainApp.unregister()
                    }
                }
            }
            Button("Export JSON") {
                Task { await writeExport(model, name: "tradegate-export.json", action: "export") }
            }
            Button("Export CSV") {
                Task { await writeExport(model, name: "tradegate-export.csv", action: "exportCSV") }
            }
            Button("Backup Database") {
                Task {
                    let destination = TradeGatePaths.supportDirectory
                        .appendingPathComponent("backup-\(UUID().uuidString).sqlite").path
                    await model.perform("backup", payload: #"{"path":"\#(destination)"}"#)
                }
            }
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
                    let registered = await model.perform("register", payload: #"{"id":"\#(serial)"}"#)
                    guard registered.contains("\"ok\":true") else { return }
                    let cycled = await model.perform("onboardingCycle", payload: #"{"id":"\#(serial)"}"#)
                    if cycled.contains("\"ok\":true") {
                        model.route = .home
                    }
                }
            }
        }
    }
}

@MainActor
private func writeExport(_ model: AppModel, name: String, action: String) async {
    let reply = await model.perform(action)
    guard let data = reply.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let result = object["result"]
    else { return }
    let output: Data? = if let text = result as? String {
        text.data(using: .utf8)
    } else {
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    }
    guard let output else { return }
    try? FileManager.default.createDirectory(at: TradeGatePaths.supportDirectory, withIntermediateDirectories: true)
    try? output.write(to: TradeGatePaths.supportDirectory.appendingPathComponent(name), options: .atomic)
}

private func labeled(_ title: String, _ value: String) -> some View {
    HStack { Text(title); Spacer(); Text(value) }
}

private func json(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try String(data: encoder.encode(value), encoding: .utf8) ?? ""
}

private struct Envelope<T: Decodable>: Decodable {
    var result: T?
}

func decodeEnvelope<T: Decodable>(_: T.Type, from reply: String) -> T? {
    guard let data = reply.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(Envelope<T>.self, from: data))?.result
}
