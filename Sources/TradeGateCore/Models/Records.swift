import Foundation

public struct ManagedDevice: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var serialNumber: String
    public var productName: String
    public var firmwareVersion: String
    public var managedFIDO2: Bool
    public var managedU2F: Bool
    public var createdAt: Date
    public var lastSeenAt: Date
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString,
        serialNumber: String,
        productName: String,
        firmwareVersion: String,
        managedFIDO2: Bool,
        managedU2F: Bool,
        createdAt: Date = Date(),
        lastSeenAt: Date = Date(),
        enabled: Bool = true
    ) {
        self.id = id
        self.serialNumber = serialNumber
        self.productName = productName
        self.firmwareVersion = firmwareVersion
        self.managedFIDO2 = managedFIDO2
        self.managedU2F = managedU2F
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.enabled = enabled
    }
}

public struct ExecutionRecord: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var planID: String?
    public var executedAt: Date
    public var executionPrice: DecimalValue
    public var executionPositionMode: ExecutionPositionMode
    public var executionPositionValue: DecimalValue?
    public var confirmedByUser: Bool
    public var reviewRequired: Bool

    public init(
        id: String,
        planID: String?,
        executedAt: Date,
        executionPrice: DecimalValue,
        executionPositionMode: ExecutionPositionMode,
        executionPositionValue: DecimalValue?,
        confirmedByUser: Bool,
        reviewRequired: Bool
    ) {
        self.id = id
        self.planID = planID
        self.executedAt = executedAt
        self.executionPrice = executionPrice
        self.executionPositionMode = executionPositionMode
        self.executionPositionValue = executionPositionValue
        self.confirmedByUser = confirmedByUser
        self.reviewRequired = reviewRequired
    }
}

public struct ExecutionInput: Equatable, Sendable, Codable {
    public var planID: String?
    public var executedAt: Date
    public var price: DecimalValue
    public var positionMode: ExecutionPositionMode
    public var positionValue: DecimalValue?

    public init(
        planID: String?,
        executedAt: Date = Date(),
        price: DecimalValue,
        positionMode: ExecutionPositionMode,
        positionValue: DecimalValue? = nil
    ) {
        self.planID = planID
        self.executedAt = executedAt
        self.price = price
        self.positionMode = positionMode
        self.positionValue = positionValue
    }
}

public struct ReviewRecord: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var executionID: String?
    public var emergencyOverrideID: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var actualJSON: String
    public var planAdherence: PlanAdherence?
    public var deviationReason: String?
    public var notes: String?

    public init(
        id: String,
        executionID: String?,
        emergencyOverrideID: String?,
        createdAt: Date,
        completedAt: Date?,
        actualJSON: String,
        planAdherence: PlanAdherence?,
        deviationReason: String?,
        notes: String?
    ) {
        self.id = id
        self.executionID = executionID
        self.emergencyOverrideID = emergencyOverrideID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.actualJSON = actualJSON
        self.planAdherence = planAdherence
        self.deviationReason = deviationReason
        self.notes = notes
    }
}

public struct EntryReviewActuals: Equatable, Sendable, Codable {
    public var timeframe: PlanTimeframe
    public var majorPullback: MajorPullback
    public var mediumPullback: MediumPullback
    public var smallDivergence: SmallDivergenceTimeframe
    public var smallDivergenceCustom: String?
    public var signalStatus: SignalStatus
    public var signalTimeframe: SignalTimeframe?
    public var stopPrice: DecimalValue
    public var positionMode: PositionMode
    public var positionValue: DecimalValue
    public var executionPrice: DecimalValue
    public var adherence: PlanAdherence
    public var deviationReason: String?
    public var notes: String?

    public init(
        timeframe: PlanTimeframe,
        majorPullback: MajorPullback,
        mediumPullback: MediumPullback,
        smallDivergence: SmallDivergenceTimeframe,
        smallDivergenceCustom: String? = nil,
        signalStatus: SignalStatus,
        signalTimeframe: SignalTimeframe? = nil,
        stopPrice: DecimalValue,
        positionMode: PositionMode,
        positionValue: DecimalValue,
        executionPrice: DecimalValue,
        adherence: PlanAdherence,
        deviationReason: String? = nil,
        notes: String? = nil
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
        self.executionPrice = executionPrice
        self.adherence = adherence
        self.deviationReason = deviationReason
        self.notes = notes
    }
}

public struct ExitReviewActuals: Equatable, Sendable, Codable {
    public var timeframe: PlanTimeframe
    public var secondaryState: ExitSecondaryState
    public var exitStrategy: ExitStrategy
    public var customExitStrategy: String?
    public var plannedExitPrice: DecimalValue
    public var exitPositionMode: ExitPositionMode
    public var exitPositionValue: DecimalValue?
    public var adherence: PlanAdherence
    public var deviationReason: String?
    public var notes: String?

    public init(
        timeframe: PlanTimeframe,
        secondaryState: ExitSecondaryState,
        exitStrategy: ExitStrategy,
        customExitStrategy: String? = nil,
        plannedExitPrice: DecimalValue,
        exitPositionMode: ExitPositionMode,
        exitPositionValue: DecimalValue? = nil,
        adherence: PlanAdherence,
        deviationReason: String? = nil,
        notes: String? = nil
    ) {
        self.timeframe = timeframe
        self.secondaryState = secondaryState
        self.exitStrategy = exitStrategy
        self.customExitStrategy = customExitStrategy
        self.plannedExitPrice = plannedExitPrice
        self.exitPositionMode = exitPositionMode
        self.exitPositionValue = exitPositionValue
        self.adherence = adherence
        self.deviationReason = deviationReason
        self.notes = notes
    }
}

public struct EmergencyReviewAnswers: Equatable, Sendable, Codable {
    public var why: String
    public var didTrade: Bool
    public var changedPosition: Bool
    public var couldHaveUsedNormalFlow: Bool
    public var howToAvoidNextTime: String

    public init(
        why: String,
        didTrade: Bool,
        changedPosition: Bool,
        couldHaveUsedNormalFlow: Bool,
        howToAvoidNextTime: String
    ) {
        self.why = why
        self.didTrade = didTrade
        self.changedPosition = changedPosition
        self.couldHaveUsedNormalFlow = couldHaveUsedNormalFlow
        self.howToAvoidNextTime = howToAvoidNextTime
    }
}

public struct UnlockSession: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var application: TradingApplication
    public var symbol: String
    public var planID: String?
    public var requestedAt: Date
    public var approvedAt: Date?
    public var unlockedAt: Date?
    public var lockedAt: Date?
    public var durationSeconds: Int?
    public var result: UnlockResult

    public init(
        id: String = UUID().uuidString,
        application: TradingApplication,
        symbol: String,
        planID: String? = nil,
        requestedAt: Date = Date(),
        approvedAt: Date? = nil,
        unlockedAt: Date? = nil,
        lockedAt: Date? = nil,
        durationSeconds: Int? = nil,
        result: UnlockResult
    ) {
        self.id = id
        self.application = application
        self.symbol = symbol
        self.planID = planID
        self.requestedAt = requestedAt
        self.approvedAt = approvedAt
        self.unlockedAt = unlockedAt
        self.lockedAt = lockedAt
        self.durationSeconds = durationSeconds
        self.result = result
    }
}

public struct EmergencyOverride: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var application: TradingApplication
    public var symbol: Symbol
    public var reasonCategory: EmergencyReasonCategory
    public var reasonText: String
    public var createdAt: Date
    public var reviewRequired: Bool

    public init(
        id: String,
        application: TradingApplication,
        symbol: Symbol,
        reasonCategory: EmergencyReasonCategory,
        reasonText: String,
        createdAt: Date,
        reviewRequired: Bool
    ) {
        self.id = id
        self.application = application
        self.symbol = symbol
        self.reasonCategory = reasonCategory
        self.reasonText = reasonText
        self.createdAt = createdAt
        self.reviewRequired = reviewRequired
    }
}

public struct EmergencyOverrideInput: Equatable, Sendable, Codable {
    public var application: TradingApplication
    public var symbol: Symbol
    public var reasonCategory: EmergencyReasonCategory
    public var reasonText: String
    public var confirmationPhrase: String

    public init(
        application: TradingApplication,
        symbol: Symbol,
        reasonCategory: EmergencyReasonCategory,
        reasonText: String,
        confirmationPhrase: String
    ) {
        self.application = application
        self.symbol = symbol
        self.reasonCategory = reasonCategory
        self.reasonText = reasonText
        self.confirmationPhrase = confirmationPhrase
    }
}

public struct TradeGateSettings: Equatable, Sendable, Codable {
    public var unlockDurationSeconds: Int
    public var emergencyCountdownSeconds: Int
    public var startAtLogin: Bool
    public var notificationsEnabled: Bool
    public var databaseLocation: String?

    public init(
        unlockDurationSeconds: Int = UnlockDuration.sec120.rawValue,
        emergencyCountdownSeconds: Int = 20,
        startAtLogin: Bool = false,
        notificationsEnabled: Bool = true,
        databaseLocation: String? = nil
    ) {
        self.unlockDurationSeconds = unlockDurationSeconds
        self.emergencyCountdownSeconds = emergencyCountdownSeconds
        self.startAtLogin = startAtLogin
        self.notificationsEnabled = notificationsEnabled
        self.databaseLocation = databaseLocation
    }
}
