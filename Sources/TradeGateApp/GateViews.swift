import AppKit
import ServiceManagement
import SwiftUI
import TradeGateCore

struct MenuBarMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("TradeGate")
        Divider()
        Text("钥匙       \(menuYubiKeyStatus(model.snapshot.state))")
        Text("待复盘        \(model.snapshot.pendingReviewCount)")
        Text("今日解锁      \(model.snapshot.todayUnlocks)")
        if let remaining = model.snapshot.unlockSecondsRemaining {
            Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
        }
        if let warning = model.snapshot.warning {
            Text(warning)
        }
        Divider()
        Button("开始交易计划") {
            if model.snapshot.pendingReviewCount > 0 {
                showGate(.reviewRequired)
            } else {
                model.beginNewPlan()
                showGate(.chooseApp)
            }
        }
        .disabled(normalPlanDisabled(model.snapshot))
        Button("待复盘") { showGate(.reviewRequired) }
        Button("日志") { showGate(.journal) }
        Button("审计") { showGate(.audit) }
        Button("统计") { showGate(.dashboard) }
        Divider()
        Button("紧急解锁") { showGate(.emergency) }
        Button("设置") { showGate(.settings) }
        Divider()
        Button("退出") { NSApplication.shared.terminate(nil) }
    }

    private func showGate(_ route: GateRoute) {
        model.route = route
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "gate")
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "TradeGate" {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}

struct GateRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinenBackground()
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
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AquaTone.sheen)
                    .frame(height: 1)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let noteText = model.noteText {
                HStack {
                    Text(noteText)
                        .font(.callout)
                        .foregroundStyle(AquaTone.ink)
                    Spacer()
                    Button("关闭") { model.noteText = nil }
                        .aquaSecondary()
                }
                .padding(10)
                .modifier(RaisedCard())
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
                .background(LinenBackground())
            }
            if let errorText = model.errorText {
                HStack {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("关闭") { model.errorText = nil }
                        .aquaSecondary()
                }
                .padding(10)
                .modifier(RaisedCard())
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
                .background(LinenBackground())
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
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    EmbossedTitle(text: "TradeGate")
                    Spacer()
                    Text(model.snapshot.state.menuSymbol)
                        .font(.title3)
                }
                InsetCard(padding: 0) {
                    VStack(spacing: 0) {
                        labeled("钥匙", menuYubiKeyStatus(model.snapshot.state))
                            .padding(.horizontal, 14)
                        hairline()
                        labeled("待复盘", "\(model.snapshot.pendingReviewCount)")
                            .padding(.horizontal, 14)
                        hairline()
                        labeled("今日解锁", "\(model.snapshot.todayUnlocks)")
                            .padding(.horizontal, 14)
                    }
                    .padding(.vertical, 4)
                }
                if let warning = model.snapshot.warning {
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .modifier(RaisedCard())
                }
                Button("开始交易计划") { model.beginNewPlan() }
                    .disabled(normalPlanDisabled(model.snapshot))
                    .aquaPrimary(fills: true)
                HStack(spacing: 10) {
                    Button("日志") { model.route = .journal }
                    Button("审计") { model.route = .audit }
                    Button("设置") { model.route = .settings }
                }
                .aquaSecondary(fills: true)
                Button("引导设置") { model.route = .onboarding }
                    .aquaSecondary(fills: true)
            }
        }
    }
}

struct ReviewRequiredView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScreenScroll {
            VStack(spacing: 14) {
                stepBack("返回首页") { model.route = .home }
                EmbossedTitle(text: "必须复盘")
                if let item = model.reviewWork.first {
                    InsetCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(item.application.rawValue.uppercased()) / \(item.symbol)")
                                .font(.headline)
                                .foregroundStyle(AquaTone.ink)
                            Text(item.kind == "emergency" ? "紧急解锁" : (item.kind == "exit" ? "出场" : "入场"))
                                .foregroundStyle(AquaTone.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(spacing: 2) {
                    linenCaption("在完成复盘之前")
                    linenCaption("无法正常解锁钥匙")
                }
                Button("开始复盘") {
                    guard let item = model.reviewWork.first else { return }
                    model.seedReview(item)
                    switch item.kind {
                    case "emergency": model.route = .emergencyReview
                    case "exit": model.route = .exitReview
                    default: model.route = .entryReview
                    }
                }
                .aquaPrimary(fills: true)
                .disabled(model.reviewWork.isEmpty)
                .task { await model.perform("reviewQueue") }
                Button("紧急解锁 →") { model.route = .emergency }
                    .aquaDestructive(fills: true)
            }
        }
    }
}

struct ChooseAppView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScreenScroll {
            VStack(spacing: 16) {
                stepBack("返回") { model.route = .home }
                EmbossedTitle(text: "选择交易应用", size: .title3)
                HStack(spacing: 12) {
                    Button("IBKR\n股票") { model.draft.application = .ibkr; model.route = .symbol }
                    Button("Kraken\n加密货币") { model.draft.application = .kraken; model.route = .symbol }
                }
                .aquaPrimary(fills: true, tall: true)
            }
        }
    }
}

struct SymbolView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                stepBack("返回") { model.route = .chooseApp }
                EmbossedTitle(text: "交易标的", size: .title3)
                InsetCard {
                    TextField("NVDA", text: $model.symbolText)
                        .textFieldStyle(.roundedBorder)
                }
                if !model.recentSymbols.isEmpty {
                    Text("最近：")
                        .foregroundStyle(AquaTone.secondaryInk)
                        .shadow(color: AquaTone.sheen, radius: 0, y: 1)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.recentSymbols, id: \.self) { symbol in
                            Button(symbol) { model.symbolText = symbol }
                                .aquaSecondary()
                        }
                    }
                }
                Button("下一步") {
                    model.draft.symbol = Symbol(raw: model.symbolText)
                    model.route = .planType
                }
                .disabled(model.symbolText.trimmingCharacters(in: .whitespaces).isEmpty)
                .aquaPrimary(fills: true)
            }
        }
        .task { await model.perform("recentSymbols") }
    }
}

struct PlanTypeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScreenScroll {
            VStack(spacing: 12) {
                stepBack("返回") { model.route = .symbol }
                Button("入场") {
                    model.draft.planType = .entry
                    model.draft.entry = EntryPlanFields()
                    model.draft.exit = nil
                    model.route = .entryForm
                }
                .aquaPrimary(fills: true, tall: true)
                Button("出场") {
                    model.draft.planType = .exit
                    model.draft.exit = ExitPlanFields()
                    model.draft.entry = nil
                    model.route = .exitForm
                }
                .aquaPrimary(fills: true, tall: true)
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
            stepBack("返回") { model.route = .planType }
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
                TextField(model.entryPositionMode == .percent ? "百分比" : "数量", text: $model.positionText)
            }
            Button("保存计划") { Task { await save() } }
                .aquaPrimary(fills: true)
        }
        .aquaForm()
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
            stepBack("返回") { model.route = .planType }
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
                TextField(model.exitPositionMode == .percent ? "百分比" : "数量", text: $model.exitPositionText)
            }
            Button("保存计划") {
                guard let price = try? DecimalValue(parsing: model.exitPrice) else {
                    model.errorText = "离场价格要是一个正数，例如 77.4"
                    return
                }
                let size: DecimalValue?
                if model.exitPositionMode == .all {
                    size = nil
                } else {
                    guard let parsed = try? DecimalValue(parsing: model.exitPositionText) else {
                        model.errorText = "仓位请填数字，例如 50 或 50%"
                        return
                    }
                    size = parsed
                }
                model.draft.exit?.plannedExitPrice = price
                model.draft.exit?.customExitStrategy = model.exitCustom
                model.draft.exit?.exitPositionMode = model.exitPositionMode
                model.draft.exit?.exitPositionValue = size
                Task {
                    guard await model.saveDraft() else { return }
                    model.route = .confirm
                }
            }
            .aquaPrimary(fills: true)
        }
        .aquaForm()
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
        ScreenScroll {
            VStack(alignment: .leading, spacing: 14) {
                stepBack("返回首页") { model.route = .home }
                InsetCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("✓ 交易计划已保存")
                            .font(.headline)
                            .foregroundStyle(AquaTone.ink)
                        Text("进场信号尚未出现。")
                            .foregroundStyle(AquaTone.secondaryInk)
                        Text("钥匙保持锁定。")
                            .foregroundStyle(AquaTone.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("信号出现了") {
                    model.signalAppeared = true
                    model.route = .entryForm
                }
                .aquaPrimary(fills: true)
            }
        }
    }
}

struct ConfirmPlanView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 14) {
                InsetCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(model.draft.application.rawValue.uppercased()) / \(model.draft.symbol.normalized)")
                            .font(.headline)
                            .foregroundStyle(AquaTone.ink)
                        Text(model.draft.planType == .entry ? "入场计划" : "出场计划")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AquaTone.secondaryInk)
                        if model.draft.entry != nil || model.draft.exit != nil {
                            hairline()
                                .padding(.vertical, 4)
                        }
                        if let entry = model.draft.entry {
                            Text("运行级别 \(entry.timeframe?.rawValue ?? "-")")
                            Text("运行级回调 \(pullbackLabel(entry.majorPullback))")
                            Text("中周期回调 \(mediumLabel(entry.mediumPullback))")
                            Text("底背离 \(divergenceLabel(entry.smallDivergence))")
                            Text("进场信号 \(entry.signalStatus == .appeared ? "已出现" : "未出现")")
                            Text("信号级别 \(entry.signalTimeframe?.rawValue ?? "-")")
                            Text("止损 \(entry.stopPrice?.storage ?? "-")")
                            Text("计划仓位 \(positionLabel(entry.positionValue?.storage, entry.positionMode))")
                        }
                        if let exit = model.draft.exit {
                            Text("运行级别 \(exit.timeframe?.rawValue ?? "-")")
                            Text("次级运行状态 \(exitStateLabel(exit.secondaryState))")
                            Text("离场计划 \(exitStrategyLabel(exit.exitStrategy, exit.customExitStrategy))")
                            Text("离场价格 \(exit.plannedExitPrice?.storage ?? "-")")
                            Text("离场仓位 \(exitSizeLabel(exit.exitPositionMode, exit.exitPositionValue?.storage))")
                        }
                    }
                    .foregroundStyle(AquaTone.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("批准并请求解锁") {
                    Task {
                        let id = model.snapshot.activePlanID ?? model.draft.id
                        await model.perform("approve", payload: #"{"id":"\#(id)"}"#)
                    }
                }
                .aquaPrimary(fills: true)
                Button("返回修改") { model.route = model.draft.planType == .entry ? .entryForm : .exitForm }
                    .aquaSecondary(fills: true)
            }
        }
    }
}

struct UnlockedView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            EmbossedTitle(text: "钥匙")
            RecessedWell {
                VStack(spacing: 8) {
                    Text("🟢 已解锁")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AquaTone.ink)
                    if let remaining = model.snapshot.unlockSecondsRemaining {
                        Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                            .font(.system(size: 52, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(AquaTone.ink)
                            .shadow(color: AquaTone.sheen, radius: 0, y: 1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ExecutionPromptView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                InsetCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("刚才是否发生实际交易？")
                            .font(.headline)
                            .foregroundStyle(AquaTone.ink)
                        if let line = executionPlanLine(model) {
                            Text(line)
                                .foregroundStyle(AquaTone.secondaryInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !model.traded {
                    Button("没有交易") {
                        Task {
                            if let id = model.snapshot.activePlanID {
                                let reply = await model.perform("noTrade", payload: #"{"id":"\#(id)","disposition":"NO_EXECUTION"}"#)
                                if reply.contains("\"ok\":true") {
                                    model.route = .home
                                }
                            } else {
                                let reply = await model.perform("dismissExecution")
                                if reply.contains("\"ok\":true") {
                                    model.route = .home
                                }
                            }
                        }
                    }
                    .aquaSecondary(fills: true)
                    if model.snapshot.activePlanID != nil {
                        Button("取消这次计划") {
                            Task {
                                let id = model.snapshot.activePlanID ?? ""
                                let reply = await model.perform("noTrade", payload: #"{"id":"\#(id)","disposition":"CANCELLED"}"#)
                                if reply.contains("\"ok\":true") {
                                    model.route = .home
                                }
                            }
                        }
                        .aquaSecondary(fills: true)
                    }
                    Button("已成交") { model.beginExecutionReport() }
                        .aquaPrimary(fills: true)
                } else {
                    InsetCard {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("实际成交价格", text: $model.fillPrice)
                                .textFieldStyle(.roundedBorder)
                            Picker("实际成交仓位", selection: $model.fillPositionMode) {
                                Text("全部").tag(ExecutionPositionMode.all)
                                Text("百分比").tag(ExecutionPositionMode.percent)
                                Text("数量").tag(ExecutionPositionMode.quantity)
                            }
                            if model.fillPositionMode != .all {
                                TextField("仓位", text: $model.fillSize)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    Button("确认成交") {
                        Task {
                            guard let parsedPrice = try? DecimalValue(parsing: model.fillPrice) else {
                                model.errorText = "成交价格要是一个正数，例如 77.4"
                                return
                            }
                            if model.fillPositionMode != .all, (try? DecimalValue(parsing: model.fillSize)) == nil {
                                model.errorText = "仓位请填数字，例如 50 或 50%"
                                return
                            }
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
                    .aquaPrimary(fills: true)
                }
            }
        }
        .task { await model.perform("journal") }
    }
}

struct EntryReviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let plan = model.reviewWork.first?.plan?.entry
        Form {
            stepBack("返回") { model.route = .reviewRequired }
            Text("计划 vs 实际")
            Text("运行级别 \(plan?.timeframe?.rawValue ?? "-")")
            Picker("实际运行级别", selection: $model.actualTimeframe) {
                ForEach(PlanTimeframe.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text("运行级回调 \(pullbackLabel(plan?.majorPullback))")
            Picker("实际运行级回调", selection: $model.actualMajor) {
                Text("一段").tag(MajorPullback.oneLeg)
                Text("两段").tag(MajorPullback.twoLeg)
                Text("横盘").tag(MajorPullback.sideways)
            }
            Text("中周期 \(mediumLabel(plan?.mediumPullback))")
            Picker("实际中周期", selection: $model.actualMedium) {
                Text("一段").tag(MediumPullback.oneLeg)
                Text("两段").tag(MediumPullback.twoLeg)
                Text("不明确").tag(MediumPullback.unclear)
            }
            Text("底背离 \(divergenceLabel(plan?.smallDivergence))")
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
                .aquaPrimary(fills: true)
        }
        .aquaForm()
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
            stepBack("返回") { model.route = .reviewRequired }
            Text("计划 vs 实际")
            Text("运行级别 \(plan?.timeframe?.rawValue ?? "-")")
            Picker("实际运行级别", selection: $model.actualTimeframe) {
                ForEach(PlanTimeframe.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text("次级运行状态 \(exitStateLabel(plan?.secondaryState))")
            Picker("实际次级状态", selection: $model.actualExitState) {
                Text("一段上涨").tag(ExitSecondaryState.oneLegUp)
                Text("两段上涨").tag(ExitSecondaryState.twoLegUp)
                Text("顶背离").tag(ExitSecondaryState.topDivergence)
                Text("不明确").tag(ExitSecondaryState.unclear)
            }
            Text("离场策略 \(exitStrategyLabel(plan?.exitStrategy, plan?.customExitStrategy))")
            Picker("实际离场策略", selection: $model.actualExitStrategy) {
                Text("全部离场").tag(ExitStrategy.fullExitOnBreak)
                Text("减仓等待").tag(ExitStrategy.reduceAndWait)
                Text("自定义").tag(ExitStrategy.custom)
            }
            Text("离场价格 \(plan?.plannedExitPrice?.storage ?? "-")")
            TextField("实际离场价格", text: $model.actualExitPrice)
            Text("离场仓位 \(exitSizeLabel(plan?.exitPositionMode, plan?.exitPositionValue?.storage))")
            Picker("实际离场仓位", selection: $model.actualExitPositionMode) {
                Text("全部").tag(ExitPositionMode.all)
                Text("百分比").tag(ExitPositionMode.percent)
                Text("数量").tag(ExitPositionMode.quantity)
            }
            if model.actualExitPositionMode != .all {
                TextField("实际仓位", text: $model.actualExitPositionText)
            }
            Text("离场仓位 \(exitSizeLabel(plan?.exitPositionMode, nil))")
            Picker("是否按计划执行", selection: $model.adherence) {
                Text("完全执行").tag(PlanAdherence.exact)
                Text("有偏差").tag(PlanAdherence.deviation)
                Text("明显偏离计划").tag(PlanAdherence.significantDeviation)
            }
            if model.adherence != .exact {
                TextField("偏离原因", text: $model.deviationReason)
            }
            Button("完成出场复盘") { Task { await finishExitReview(model) } }
                .aquaPrimary(fills: true)
        }
        .aquaForm()
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
        exitPositionMode: model.actualExitPositionMode,
        exitPositionValue: model.actualExitPositionMode == .all ? nil : (try? DecimalValue(parsing: model.actualExitPositionText)),
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
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                stepBack("返回") { model.route = .home }
                InsetCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚠ 紧急解锁")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AquaTone.destructiveBottom)
                        Text("这次操作将永久写入审计记录。")
                            .foregroundStyle(AquaTone.secondaryInk)
                        hairline()
                        Picker("应用", selection: $model.emergencyApplication) {
                            Text("IBKR").tag(TradingApplication.ibkr)
                            Text("Kraken").tag(TradingApplication.kraken)
                        }
                        TextField("标的", text: $model.emergencySymbol)
                            .textFieldStyle(.roundedBorder)
                        Picker("原因", selection: $model.emergencyCategory) {
                            Text("持仓风险").tag(EmergencyReasonCategory.positionRisk)
                            Text("券商或系统故障").tag(EmergencyReasonCategory.brokerOrSystemFailure)
                            Text("无法完成正常计划").tag(EmergencyReasonCategory.cannotCompleteNormalPlan)
                            Text("行情异常").tag(EmergencyReasonCategory.abnormalMarket)
                            Text("其他").tag(EmergencyReasonCategory.other)
                        }
                        TextField("原因（至少 10 个字）", text: $model.emergencyReason)
                            .textFieldStyle(.roundedBorder)
                        TextField("输入确认短语 EMERGENCY UNLOCK", text: $model.emergencyPhrase)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                if model.emergencyArmedAt == nil {
                    Button("开始 \(model.settings.emergencyCountdownSeconds) 秒倒计时") { model.emergencyArmedAt = Date() }
                        .disabled(
                            model.emergencySymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || !EmergencyGate.canStartCountdown(reason: model.emergencyReason, phrase: model.emergencyPhrase)
                        )
                        .aquaDestructive(fills: true)
                } else if let armedAt = model.emergencyArmedAt,
                          !EmergencyGate.canConfirm(
                              armedAt: armedAt,
                              now: Date(),
                              countdownSeconds: model.settings.emergencyCountdownSeconds
                          )
                {
                    let remaining = max(
                        0,
                        model.settings.emergencyCountdownSeconds - Int(Date().timeIntervalSince(armedAt))
                    )
                    RecessedWell {
                        Text("倒计时 \(remaining) 秒")
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AquaTone.ink)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Button("确认紧急解锁") {
                        Task {
                            let input = EmergencyOverrideInput(
                                application: model.emergencyApplication,
                                symbol: Symbol(raw: model.emergencySymbol),
                                reasonCategory: model.emergencyCategory,
                                reasonText: model.emergencyReason,
                                confirmationPhrase: model.emergencyPhrase
                            )
                            await model.perform("emergency", payload: (try? json(input)) ?? "")
                        }
                    }
                    .aquaDestructive(fills: true)
                }
            }
        }
    }
}

struct EmergencyReviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            stepBack("返回") { model.route = .reviewRequired }
            TextField("为什么使用 Emergency Override？", text: $model.emergencyWhy)
            Toggle("是否发生交易？", isOn: $model.emergencyDidTrade)
            Toggle("是否改变仓位？", isOn: $model.emergencyChangedPosition)
            Toggle("本次是否本可通过正常流程完成？", isOn: $model.emergencyCouldNormal)
            TextField("下次如何避免？", text: $model.emergencyNext)
            Button("完成紧急复盘") { Task { await finishEmergencyReview(model) } }
                .disabled(model.emergencyWhy.trimmingCharacters(in: .whitespaces).isEmpty || model.emergencyNext.trimmingCharacters(in: .whitespaces).isEmpty)
                .aquaPrimary(fills: true)
        }
        .aquaForm()
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
        ScreenScroll {
            VStack(alignment: .leading, spacing: 14) {
                stepBack("返回首页") { model.route = .home }
                EmbossedTitle(text: "过去30天", size: .title3)
                InsetCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        statLine("解锁次数 \(model.dashboard.unlockCount)")
                        hairline()
                        statLine("紧急解锁次数 \(model.dashboard.emergencyCount)")
                        hairline()
                        statLine("交易次数 \(model.dashboard.tradeCount)")
                        hairline()
                        statLine("无成交的解锁次数 \(model.dashboard.noExecutionUnlockCount)")
                        hairline()
                        statLine(String(format: "计划执行率 %.0f%%", model.dashboard.adherenceRate * 100))
                        hairline()
                        statLine("仓位偏离次数 \(model.dashboard.positionDeviationCount)")
                        hairline()
                        statLine("止损偏离次数 \(model.dashboard.stopDeviationCount)")
                        hairline()
                        statLine("提前进场次数 \(model.dashboard.earlyEntryCount)")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task { await model.perform("dashboard") }
    }
}

struct JournalView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 8) {
            stepBack("返回首页") { model.route = .home }
            List(model.journal, id: \.plan.id) { entry in
                Button {
                    model.selectedPlanID = entry.plan.id
                    model.route = .tradeDetail
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.plan.createdAt.formatted(date: .numeric, time: .omitted))
                            .font(.headline)
                            .foregroundStyle(AquaTone.ink)
                        Text(entry.plan.symbol.normalized)
                        Text(entry.plan.application.rawValue.uppercased())
                        Text(entry.plan.planType == .entry ? "入场计划" : "出场计划")
                        Text(entry.executions.isEmpty ? "没有成交" : "已成交")
                        Text(entry.reviewCompleted ? "已复盘" : "待复盘")
                            .foregroundStyle(entry.reviewCompleted ? AquaTone.secondaryInk : Color.orange)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderless)
            }
            .aquaList()
            .task { await model.perform("journal") }
        }
    }
}

struct AuditView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            stepBack("返回首页") { model.route = .home }
            InsetCard {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("日期 2026-09-25", text: $model.auditDay)
                        .textFieldStyle(.roundedBorder)
                    Picker("应用", selection: $model.auditApplication) {
                        Text("全部").tag("")
                        Text("IBKR").tag("ibkr")
                        Text("Kraken").tag("kraken")
                    }
                    TextField("标的", text: $model.auditSymbol)
                        .textFieldStyle(.roundedBorder)
                    Picker("事件类型", selection: $model.auditEventType) {
                        Text("全部").tag("")
                        ForEach(AuditEventType.allCases, id: \.rawValue) { type in
                            Text(tradeEventTitle(type)).tag(type.rawValue)
                        }
                    }
                    Toggle("只看紧急解锁", isOn: $model.auditEmergencyOnly)
                }
            }
            Button("筛选") { Task { await model.perform("audit", payload: model.auditPayload()) } }
                .aquaPrimary(fills: true)
            if model.audit.isEmpty {
                Text("没有匹配的记录")
                    .foregroundStyle(AquaTone.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            List(model.audit, id: \.id) { event in
                Text("\(event.timestampText)  \(tradeEventTitle(event.eventType))  \(event.symbol ?? "")")
                    .foregroundStyle(AquaTone.ink)
            }
            .aquaList()
        }
        .task { await model.perform("audit", payload: model.auditPayload()) }
    }
}

struct TradeDetailView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let planID = model.selectedPlanID
        let events = model.audit.filter { $0.planID == planID }
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                stepBack("返回") { model.route = .journal }
                EmbossedTitle(text: model.journal.first { $0.plan.id == planID }?.plan.symbol.normalized ?? "交易", size: .title3)
                if !model.revisions.isEmpty || !events.isEmpty {
                    InsetCard {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.revisions, id: \.id) { revision in
                                Text("修订 \(revision.revisionNumber)  \(revision.createdAt.formatted())")
                                    .foregroundStyle(AquaTone.ink)
                            }
                            if !model.revisions.isEmpty, !events.isEmpty {
                                hairline()
                            }
                            ForEach(events, id: \.id) { event in
                                Text("\(tradeEventTitle(event.eventType))  \(event.timestampText)")
                                    .foregroundStyle(AquaTone.ink)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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
    case .appStarted: "应用启动"
    case .daemonStarted: "后台服务启动"
    case .deviceInserted: "插入钥匙"
    case .deviceRemoved: "拔出钥匙"
    case .planCreated: "计划创建"
    case .planUpdated: "计划修改"
    case .planSubmitted: "计划提交"
    case .planApproved: "计划批准"
    case .planCancelled: "计划取消"
    case .signalConfirmed: "信号确认"
    case .unlockRequested: "请求解锁"
    case .unlockApproved: "批准解锁"
    case .unlockDenied: "拒绝解锁"
    case .yubiKeyUnlocked: "钥匙解锁"
    case .yubiKeyLocked: "钥匙锁定"
    case .deviceRemovedWhileUnlocked: "解锁期间拔出"
    case .executionConfirmed: "成交"
    case .noExecution: "没有交易"
    case .reviewRequired: "需要复盘"
    case .reviewStarted: "开始复盘"
    case .reviewCompleted: "复盘完成"
    case .emergencyOverrideRequested: "请求紧急解锁"
    case .emergencyOverrideApproved: "紧急解锁"
    case .helperError: "工具错误"
    case .yubiKeyError: "钥匙错误"
    case .databaseError: "数据库错误"
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    stepBack("返回首页") { model.route = .home }
                    Spacer()
                    Button("退出") { NSApplication.shared.terminate(nil) }
                        .aquaSecondary()
                }
                Text("已登记钥匙 \(model.snapshot.managedSerial ?? "未登记")")
                Picker("解锁时长", selection: $model.settings.unlockDurationSeconds) {
                    ForEach(UnlockDuration.allCases, id: \.rawValue) { Text("\($0.rawValue) 秒").tag($0.rawValue) }
                }
                Stepper("紧急倒计时 \(model.settings.emergencyCountdownSeconds) 秒", value: $model.settings.emergencyCountdownSeconds, in: 5 ... 120)
                Toggle("登录时打开", isOn: $model.settings.startAtLogin)
                Toggle("通知", isOn: $model.settings.notificationsEnabled)
                Text("数据库 \(TradeGatePaths.databasePath)")
                    .textSelection(.enabled)
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
                .aquaPrimary(fills: true)
                Button("导出 JSON") {
                    Task { await writeExport(model, name: "tradegate-export.json", action: "export") }
                }
                .aquaSecondary(fills: true)
                Button("导出 CSV") {
                    Task { await writeExport(model, name: "tradegate-export.csv", action: "exportCSV") }
                }
                .aquaSecondary(fills: true)
                Button("备份数据库") {
                    Task {
                        let destination = TradeGatePaths.supportDirectory
                            .appendingPathComponent("backup-\(UUID().uuidString).sqlite").path
                        let reply = await model.perform("backup", payload: #"{"path":"\#(destination)"}"#)
                        if reply.contains("\"ok\":true") {
                            model.noteText = "已备份到 \(destination)"
                            model.errorText = nil
                        } else if model.errorText == nil {
                            model.errorText = "备份没有完成。"
                        }
                    }
                }
                .aquaSecondary(fills: true)
            }
        }
        .task { await model.perform("settings") }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 14) {
                stepBack("返回首页") { model.route = .home }
                InsetCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        statusLine(model.snapshot.warning?.contains("登录功能状态未知") == true ? "后台服务：未连接" : "后台服务：已连接")
                        hairline()
                        statusLine("钥匙工具：\(model.snapshot.helperStatus ?? "未知")")
                        hairline()
                        statusLine(model.snapshot.yubiKeyPresent ? "检测到钥匙 \(model.snapshot.yubiKeyProduct ?? "")" : "请插入钥匙")
                        hairline()
                        statusLine("序列号 \(model.snapshot.yubiKeySerial ?? "-")")
                        hairline()
                        statusLine("固件 \(model.snapshot.yubiKeyFirmware ?? "-")")
                        hairline()
                        statusLine(model.snapshot.yubiKeyPresent ? "登录功能：可以控制" : "登录功能：尚未检测到可管理的钥匙")
                    }
                    .padding(.vertical, 4)
                }
                InsetCard {
                    Text("TradeGate 会暂时关闭这把钥匙的登录功能，让你在登录交易账户之前多走一步。它不会删除通行密钥，也不会重置钥匙。")
                        .foregroundStyle(AquaTone.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("下面这个测试会真的把钥匙锁上、打开、再锁上，用来确认可以控制它。大约要半分钟，期间按钮会停住。")
                    .foregroundStyle(AquaTone.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(model.keyTestRunning ? "正在测试钥匙，请稍等" : "测试锁定、解锁、再锁定") {
                    Task {
                        guard let serial = model.snapshot.yubiKeySerial else {
                            model.errorText = "还没有读到钥匙序列号。请确认钥匙已经插上。"
                            return
                        }
                        model.keyTestRunning = true
                        defer { model.keyTestRunning = false }
                        let registered = await model.perform("register", payload: #"{"id":"\#(serial)"}"#)
                        guard registered.contains("\"ok\":true") else {
                            if model.errorText == nil {
                                model.errorText = "测试没有完成。请再试一次，这期间不要拔钥匙。"
                            }
                            return
                        }
                        let cycled = await model.perform("onboardingCycle", payload: #"{"id":"\#(serial)"}"#)
                        if cycled.contains("\"ok\":true") {
                            model.route = .home
                        } else if model.errorText == nil {
                            model.errorText = "测试没有完成。请再试一次，这期间不要拔钥匙。"
                        }
                    }
                }
                .disabled(model.keyTestRunning)
                .aquaPrimary(fills: true)
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
    else {
        if model.errorText == nil {
            model.errorText = "导出没有完成。"
        }
        return
    }
    let output: Data? = if let text = result as? String {
        text.data(using: .utf8)
    } else {
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    }
    guard let output else { return }
    let file = TradeGatePaths.supportDirectory.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: TradeGatePaths.supportDirectory, withIntermediateDirectories: true)
    do {
        try output.write(to: file, options: .atomic)
        model.noteText = "已导出到 \(file.path)"
        model.errorText = nil
    } catch {
        model.errorText = "导出没有完成。"
    }
}

private func menuYubiKeyStatus(_ state: GateState) -> String {
    switch state {
    case .unlocked:
        "🟢 已解锁"
    case .lockStateUnknown:
        "⚠️ 未知"
    case .errorFailClosed:
        "⚠️ 错误"
    case .reviewRequired:
        "⚠️ 待复盘"
    default:
        "🔒 已锁定"
    }
}

private func normalPlanDisabled(_ snapshot: GateSnapshot) -> Bool {
    snapshot.pendingReviewCount > 0
        || snapshot.state == .unlocked
        || snapshot.state == .lockStateUnknown
        || snapshot.state == .errorFailClosed
}

private func labeled(_ title: String, _ value: String) -> some View {
    HStack {
        Text(title)
            .foregroundStyle(AquaTone.secondaryInk)
        Spacer()
        Text(value)
            .fontWeight(.medium)
            .foregroundStyle(AquaTone.ink)
    }
    .padding(.vertical, 7)
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

private func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

private enum AquaTone {
    static let ink = adaptiveColor(
        light: NSColor(srgbRed: 0.20, green: 0.17, blue: 0.13, alpha: 1),
        dark: NSColor(srgbRed: 0.94, green: 0.91, blue: 0.84, alpha: 1)
    )
    static let secondaryInk = adaptiveColor(
        light: NSColor(srgbRed: 0.40, green: 0.35, blue: 0.28, alpha: 1),
        dark: NSColor(srgbRed: 0.74, green: 0.68, blue: 0.58, alpha: 1)
    )
    static let hairline = adaptiveColor(
        light: NSColor(srgbRed: 0.55, green: 0.49, blue: 0.40, alpha: 0.45),
        dark: NSColor(srgbRed: 0.62, green: 0.55, blue: 0.44, alpha: 0.35)
    )
    static let sheen = adaptiveColor(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.90),
        dark: NSColor(srgbRed: 1, green: 0.95, blue: 0.88, alpha: 0.16)
    )
    static let sheenSoft = adaptiveColor(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.38),
        dark: NSColor(srgbRed: 1, green: 0.95, blue: 0.88, alpha: 0.08)
    )
    static let primaryTop = Color(red: 0.49, green: 0.72, blue: 0.97)
    static let primaryBottom = Color(red: 0.13, green: 0.39, blue: 0.78)
    static let destructiveTop = Color(red: 0.90, green: 0.44, blue: 0.39)
    static let destructiveBottom = Color(red: 0.64, green: 0.15, blue: 0.13)
    static let metalTop = adaptiveColor(
        light: NSColor(srgbRed: 0.99, green: 0.985, blue: 0.965, alpha: 1),
        dark: NSColor(srgbRed: 0.38, green: 0.35, blue: 0.30, alpha: 1)
    )
    static let metalBottom = adaptiveColor(
        light: NSColor(srgbRed: 0.78, green: 0.75, blue: 0.68, alpha: 1),
        dark: NSColor(srgbRed: 0.22, green: 0.20, blue: 0.17, alpha: 1)
    )
    static let linenTop = adaptiveColor(
        light: NSColor(srgbRed: 0.94, green: 0.92, blue: 0.87, alpha: 1),
        dark: NSColor(srgbRed: 0.20, green: 0.18, blue: 0.16, alpha: 1)
    )
    static let linenBottom = adaptiveColor(
        light: NSColor(srgbRed: 0.83, green: 0.80, blue: 0.72, alpha: 1),
        dark: NSColor(srgbRed: 0.11, green: 0.10, blue: 0.09, alpha: 1)
    )
    static let cardTop = adaptiveColor(
        light: NSColor(srgbRed: 0.995, green: 0.992, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.26, green: 0.24, blue: 0.21, alpha: 1)
    )
    static let cardBottom = adaptiveColor(
        light: NSColor(srgbRed: 0.96, green: 0.95, blue: 0.925, alpha: 1),
        dark: NSColor(srgbRed: 0.18, green: 0.16, blue: 0.14, alpha: 1)
    )
    static let wellTop = adaptiveColor(
        light: NSColor(srgbRed: 0.75, green: 0.72, blue: 0.65, alpha: 1),
        dark: NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1)
    )
    static let wellBottom = adaptiveColor(
        light: NSColor(srgbRed: 0.93, green: 0.91, blue: 0.86, alpha: 1),
        dark: NSColor(srgbRed: 0.20, green: 0.18, blue: 0.16, alpha: 1)
    )
}

private struct LinenBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [AquaTone.linenTop, AquaTone.linenBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [AquaTone.sheenSoft, Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
        }
        .ignoresSafeArea()
    }
}

private struct EmbossedTitle: View {
    var text: String
    var size: Font = .title2.weight(.semibold)

    var body: some View {
        Text(text)
            .font(size)
            .foregroundStyle(AquaTone.ink)
            .shadow(color: AquaTone.sheen, radius: 0, y: 1)
    }
}

private struct InsetCard<Content: View>: View {
    var padding: CGFloat
    private var content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .modifier(RaisedCard())
    }
}

private struct RaisedCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [AquaTone.cardTop, AquaTone.cardBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [AquaTone.sheen, AquaTone.hairline],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 3)
                    .blur(radius: 1.2)
                    .mask(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black, Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 1.5, y: 1)
    }
}

private struct RecessedWell<Content: View>: View {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(
                LinearGradient(
                    colors: [AquaTone.wellTop, AquaTone.wellBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.28), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 4)
                    .blur(radius: 1.5)
                    .mask(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black, Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: AquaTone.sheen, radius: 0, y: 1)
    }
}

@MainActor
private func executionPlanLine(_ model: AppModel) -> String? {
    if let id = model.snapshot.activePlanID, let entry = model.journal.first(where: { $0.plan.id == id }) {
        let kind = entry.plan.planType == .entry ? "入场" : "出场"
        return "\(entry.plan.application.rawValue.uppercased()) / \(entry.plan.symbol.normalized) · \(kind)"
    }
    guard !model.draft.symbol.normalized.isEmpty else { return nil }
    let kind = model.draft.planType == .entry ? "入场" : "出场"
    return "\(model.draft.application.rawValue.uppercased()) / \(model.draft.symbol.normalized) · \(kind)"
}

private func pullbackLabel(_ value: MajorPullback?) -> String {
    switch value {
    case .oneLeg: "一段回调"
    case .twoLeg: "两段回调"
    case .sideways: "横盘"
    case nil: "-"
    }
}

private func mediumLabel(_ value: MediumPullback?) -> String {
    switch value {
    case .oneLeg: "一段回调"
    case .twoLeg: "两段回调"
    case .unclear: "不明确"
    case nil: "-"
    }
}

private func divergenceLabel(_ value: SmallDivergenceTimeframe?) -> String {
    switch value {
    case .notYet: "尚未出现"
    case .other: "其他"
    case nil: "-"
    default: value?.rawValue ?? "-"
    }
}

private func positionLabel(_ amount: String?, _ mode: PositionMode?) -> String {
    switch mode {
    case .percent: "\(amount ?? "-")%"
    case .quantity: "\(amount ?? "-") 数量"
    case nil: amount ?? "-"
    }
}

private func exitStateLabel(_ value: ExitSecondaryState?) -> String {
    switch value {
    case .oneLegUp: "一段上涨"
    case .twoLegUp: "两段上涨"
    case .topDivergence: "顶背离"
    case .unclear: "不明确"
    case nil: "-"
    }
}

private func exitStrategyLabel(_ value: ExitStrategy?, _ custom: String?) -> String {
    switch value {
    case .fullExitOnBreak: "跌破次级别全部离场"
    case .reduceAndWait: "减仓等待"
    case .custom: custom?.isEmpty == false ? "自定义：\(custom ?? "")" : "自定义"
    case nil: "-"
    }
}

private func exitSizeLabel(_ mode: ExitPositionMode?, _ amount: String?) -> String {
    switch mode {
    case .all: "全部"
    case .percent: "\(amount ?? "-")%"
    case .quantity: "\(amount ?? "-") 数量"
    case nil: "-"
    }
}

private func stepBack(_ title: String, _ action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .buttonStyle(.plain)
        .foregroundStyle(AquaTone.secondaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
}

private struct ScreenScroll<Content: View>: View {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
        }
    }
}

private struct AquaPushStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }

    var kind: Kind
    var fills = false
    var tall = false

    func makeBody(configuration: Configuration) -> some View {
        AquaPushFace(
            kind: kind,
            fills: fills,
            tall: tall,
            isPressed: configuration.isPressed,
            label: configuration.label
        )
    }
}

private struct AquaPushFace<Label: View>: View {
    var kind: AquaPushStyle.Kind
    var fills: Bool
    var tall: Bool
    var isPressed: Bool
    var label: Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(textColor)
            .shadow(color: textShadow, radius: 0, y: kind == .secondary ? 1 : -1)
            .padding(.horizontal, 16)
            .padding(.vertical, tall ? 14 : 8)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: tall ? 72 : 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(faceGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                AquaTone.sheen,
                                Color.black.opacity(0.32),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .overlay {
                if isPressed, isEnabled {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.28), lineWidth: 3)
                        .blur(radius: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: Color.black.opacity(isPressed ? 0.04 : 0.18), radius: isPressed ? 0.4 : 1.4, y: isPressed ? 0 : 1)
            .offset(y: isPressed && isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.48)
            .saturation(isEnabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var textColor: Color {
        kind == .secondary ? AquaTone.ink : Color.white
    }

    private var textShadow: Color {
        kind == .secondary ? AquaTone.sheen : Color.black.opacity(0.25)
    }

    private var faceGradient: LinearGradient {
        let top: Color
        let bottom: Color
        switch kind {
        case .primary:
            top = AquaTone.primaryTop
            bottom = AquaTone.primaryBottom
        case .destructive:
            top = AquaTone.destructiveTop
            bottom = AquaTone.destructiveBottom
        case .secondary:
            top = AquaTone.metalTop
            bottom = AquaTone.metalBottom
        }
        if isPressed, isEnabled {
            return LinearGradient(colors: [bottom, bottom.opacity(0.92)], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            stops: [
                .init(color: top, location: 0),
                .init(color: top.opacity(0.92), location: 0.42),
                .init(color: bottom, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private extension View {
    func aquaPrimary(fills: Bool = false, tall: Bool = false) -> some View {
        buttonStyle(AquaPushStyle(kind: .primary, fills: fills, tall: tall))
    }

    func aquaSecondary(fills: Bool = false, tall: Bool = false) -> some View {
        buttonStyle(AquaPushStyle(kind: .secondary, fills: fills, tall: tall))
    }

    func aquaDestructive(fills: Bool = false, tall: Bool = false) -> some View {
        buttonStyle(AquaPushStyle(kind: .destructive, fills: fills, tall: tall))
    }

    func aquaForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }

    func aquaList() -> some View {
        listStyle(.bordered(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
    }
}

private func hairline() -> some View {
    Rectangle()
        .fill(AquaTone.hairline)
        .frame(height: 1)
}

private func linenCaption(_ text: String) -> some View {
    Text(text)
        .font(.callout)
        .foregroundStyle(AquaTone.secondaryInk)
        .shadow(color: AquaTone.sheen, radius: 0, y: 1)
}

private func statLine(_ text: String) -> some View {
    Text(text)
        .foregroundStyle(AquaTone.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
}

private func statusLine(_ text: String) -> some View {
    Text(text)
        .foregroundStyle(AquaTone.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
}
