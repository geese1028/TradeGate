import Foundation

public struct EntryPlanFields: Equatable, Sendable, Codable {
    public var timeframe: PlanTimeframe?
    public var majorPullback: MajorPullback?
    public var mediumPullback: MediumPullback?
    public var smallDivergence: SmallDivergenceTimeframe?
    public var smallDivergenceCustom: String?
    public var signalStatus: SignalStatus?
    public var signalTimeframe: SignalTimeframe?
    public var stopPrice: DecimalValue?
    public var positionMode: PositionMode?
    public var positionValue: DecimalValue?

    public init(
        timeframe: PlanTimeframe? = nil,
        majorPullback: MajorPullback? = nil,
        mediumPullback: MediumPullback? = nil,
        smallDivergence: SmallDivergenceTimeframe? = nil,
        smallDivergenceCustom: String? = nil,
        signalStatus: SignalStatus? = nil,
        signalTimeframe: SignalTimeframe? = nil,
        stopPrice: DecimalValue? = nil,
        positionMode: PositionMode? = nil,
        positionValue: DecimalValue? = nil
    ) {
        self.timeframe = timeframe
        self.majorPullback = majorPullback
        self.mediumPullback = mediumPullback
        self.smallDivergence = smallDivergence
        self.smallDivergenceCustom = smallDivergenceCustom
        self.signalStatus = signalStatus
        self.signalTimeframe = signalTimeframe
        self.stopPrice = stopPrice
        self.positionMode = positionMode
        self.positionValue = positionValue
    }
}

public struct ExitPlanFields: Equatable, Sendable, Codable {
    public var timeframe: PlanTimeframe?
    public var secondaryState: ExitSecondaryState?
    public var exitStrategy: ExitStrategy?
    public var customExitStrategy: String?
    public var plannedExitPrice: DecimalValue?
    public var exitPositionMode: ExitPositionMode?
    public var exitPositionValue: DecimalValue?

    public init(
        timeframe: PlanTimeframe? = nil,
        secondaryState: ExitSecondaryState? = nil,
        exitStrategy: ExitStrategy? = nil,
        customExitStrategy: String? = nil,
        plannedExitPrice: DecimalValue? = nil,
        exitPositionMode: ExitPositionMode? = nil,
        exitPositionValue: DecimalValue? = nil
    ) {
        self.timeframe = timeframe
        self.secondaryState = secondaryState
        self.exitStrategy = exitStrategy
        self.customExitStrategy = customExitStrategy
        self.plannedExitPrice = plannedExitPrice
        self.exitPositionMode = exitPositionMode
        self.exitPositionValue = exitPositionValue
    }
}

public struct TradePlan: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    public var application: TradingApplication
    public var symbol: Symbol
    public var planType: PlanType
    public var status: PlanStatus
    public var entry: EntryPlanFields?
    public var exit: ExitPlanFields?

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        application: TradingApplication,
        symbol: Symbol,
        planType: PlanType,
        status: PlanStatus = .saved,
        entry: EntryPlanFields? = nil,
        exit: ExitPlanFields? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.application = application
        self.symbol = symbol
        self.planType = planType
        self.status = status
        self.entry = entry
        self.exit = exit
    }
}

public struct PlanRevision: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let planID: String
    public let revisionNumber: Int
    public let createdAt: Date
    public let snapshotJSON: String

    public init(
        id: String,
        planID: String,
        revisionNumber: Int,
        createdAt: Date,
        snapshotJSON: String
    ) {
        self.id = id
        self.planID = planID
        self.revisionNumber = revisionNumber
        self.createdAt = createdAt
        self.snapshotJSON = snapshotJSON
    }
}
