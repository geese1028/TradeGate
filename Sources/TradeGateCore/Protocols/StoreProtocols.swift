import Foundation

public enum TradeGateError: Error, Equatable, Sendable {
    case validation([PlanValidationError])
    case emergencyValidation([EmergencyValidationError])
    case reviewValidation([ReviewValidationError])
    case notUnlockable
    case notFound(String)
    case sqlite(String)
    case auditChainBroken(String)
    case invalidState(String)
    case invalidSettings(String)
}

public struct StoreStatus: Equatable, Sendable {
    public var schemaVersion: Int
    public var foreignKeysEnabled: Bool
    public var journalMode: String

    public init(schemaVersion: Int, foreignKeysEnabled: Bool, journalMode: String) {
        self.schemaVersion = schemaVersion
        self.foreignKeysEnabled = foreignKeysEnabled
        self.journalMode = journalMode
    }
}

public protocol PlanStoring: AnyObject {
    func createPlan(_ plan: TradePlan) throws -> TradePlan
    func updatePlan(_ plan: TradePlan) throws -> TradePlan
    func plan(id: String) throws -> TradePlan?
    func revisions(planID: String) throws -> [PlanRevision]
}

public protocol AuditVerifying: AnyObject {
    func verifyAuditChain() throws -> AuditVerification
}
