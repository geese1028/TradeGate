import Foundation

public enum TradingApplication: String, Codable, Sendable, CaseIterable {
    case ibkr
    case kraken
}

public enum PlanType: String, Codable, Sendable {
    case entry
    case exit
}

public enum PlanStatus: String, Codable, Sendable {
    case saved = "SAVED"
    case approved = "APPROVED"
    case cancelled = "CANCELLED"
    case noExecution = "NO_EXECUTION"
}

public enum PlanTimeframe: String, Codable, Sendable, CaseIterable {
    case oneDay = "1D"
    case twoDay = "2D"
    case threeDay = "3D"
    case oneWeek = "1W"
    case twoWeek = "2W"
    case oneMonth = "1M"
}

public enum MajorPullback: String, Codable, Sendable {
    case oneLeg = "ONE_LEG"
    case twoLeg = "TWO_LEG"
    case sideways = "SIDEWAYS"
}

public enum MediumPullback: String, Codable, Sendable {
    case oneLeg = "ONE_LEG"
    case twoLeg = "TWO_LEG"
    case unclear = "UNCLEAR"
}

public enum SmallDivergenceTimeframe: String, Codable, Sendable {
    case m5 = "5m"
    case m15 = "15m"
    case m30 = "30m"
    case h1 = "1H"
    case h2 = "2H"
    case h4 = "4H"
    case notYet = "NOT_YET"
    case other = "OTHER"
}

public enum SignalStatus: String, Codable, Sendable {
    case appeared = "APPEARED"
    case notAppeared = "NOT_APPEARED"
}

public enum SignalTimeframe: String, Codable, Sendable {
    case m5 = "5m"
    case m30 = "30m"
    case h1 = "1H"
}

public enum PositionMode: String, Codable, Sendable {
    case percent = "PERCENT"
    case quantity = "QUANTITY"
}

public enum ExecutionPositionMode: String, Codable, Sendable {
    case percent = "PERCENT"
    case quantity = "QUANTITY"
    case all = "ALL"
}

public enum ExitSecondaryState: String, Codable, Sendable {
    case oneLegUp = "ONE_LEG_UP"
    case twoLegUp = "TWO_LEG_UP"
    case topDivergence = "TOP_DIVERGENCE"
    case unclear = "UNCLEAR"
}

public enum ExitStrategy: String, Codable, Sendable {
    case fullExitOnBreak = "FULL_EXIT_ON_BREAK"
    case reduceAndWait = "REDUCE_AND_WAIT"
    case custom = "CUSTOM"
}

public enum ExitPositionMode: String, Codable, Sendable {
    case all = "ALL"
    case percent = "PERCENT"
    case quantity = "QUANTITY"
}

public enum UnlockResult: String, Codable, Sendable {
    case normal = "NORMAL"
    case denied = "DENIED"
    case timeout = "TIMEOUT"
    case emergency = "EMERGENCY"
    case error = "ERROR"
    case removedWhileUnlocked = "REMOVED_WHILE_UNLOCKED"
}

public enum PlanAdherence: String, Codable, Sendable {
    case exact = "EXACT"
    case deviation = "DEVIATION"
    case significantDeviation = "SIGNIFICANT_DEVIATION"
}

public enum EmergencyReasonCategory: String, Codable, Sendable {
    case positionRisk = "POSITION_RISK"
    case brokerOrSystemFailure = "BROKER_OR_SYSTEM_FAILURE"
    case cannotCompleteNormalPlan = "CANNOT_COMPLETE_NORMAL_PLAN"
    case abnormalMarket = "ABNORMAL_MARKET"
    case other = "OTHER"
}

public enum NoTradeDisposition: String, Sendable {
    case cancelled = "CANCELLED"
    case noExecution = "NO_EXECUTION"
}

public enum UnlockDuration: Int, Codable, Sendable, CaseIterable {
    case sec30 = 30
    case sec60 = 60
    case sec90 = 90
    case sec120 = 120
    case sec180 = 180
}
