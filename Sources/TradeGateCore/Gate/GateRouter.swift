import Foundation

public enum GateRouter {
    public static func perform(
        coordinator: GateCoordinator,
        database: TradeGateDatabase,
        action: String,
        payload: String
    ) async -> String {
        do {
            let result = try await handle(coordinator: coordinator, database: database, action: action, payload: payload)
            return #"{"ok":true,"result":\#(result)}"#
        } catch {
            if case TradeGateError.sqlite = error {
                _ = try? database.appendAudit(AuditEventDraft(eventType: .databaseError, metadata: ["message": "\(error)"]))
            }
            let message = String(describing: error)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return #"{"ok":false,"error":"\#(message)"}"#
        }
    }

    private static func handle(
        coordinator: GateCoordinator,
        database: TradeGateDatabase,
        action: String,
        payload: String
    ) async throws -> String {
        let data = Data(payload.utf8)
        switch action {
        case "snapshot":
            let probe = !payload.contains("\"probe\":false")
            return try await json(coordinator.snapshot(probeHardware: probe))
        case "createPlan":
            return try await json(coordinator.createPlan(decode(TradePlan.self, from: data)))
        case "updatePlan":
            return try await json(coordinator.updatePlan(decode(TradePlan.self, from: data)))
        case "approve":
            let body = try decode(IDPayload.self, from: data)
            try await coordinator.approveAndUnlock(planID: body.id)
            return try await json(coordinator.snapshot())
        case "noTrade":
            let body = try decode(NoTradePayload.self, from: data)
            return try await json(coordinator.recordNoTrade(planID: body.id, disposition: body.disposition))
        case "dismissExecution":
            await coordinator.dismissExecutionPrompt()
            return try await json(coordinator.snapshot())
        case "execution":
            return try await json(coordinator.confirmExecution(decode(ExecutionInput.self, from: data)))
        case "emergency":
            return try await json(coordinator.emergencyUnlock(decode(EmergencyOverrideInput.self, from: data)))
        case "journal":
            return try json(database.journal())
        case "audit":
            return try json(database.filteredAuditEvents(payload.isEmpty ? AuditFilter() : decode(AuditFilter.self, from: data)))
        case "dashboard":
            return try json(database.dashboard(since: Date().addingTimeInterval(-30 * 24 * 3600)))
        case "plans":
            return try json(database.listPlans())
        case "plan":
            let body = try decode(IDPayload.self, from: data)
            return try json(database.plan(id: body.id))
        case "revisions":
            let body = try decode(IDPayload.self, from: data)
            return try json(database.revisions(planID: body.id))
        case "recentSymbols":
            return try json(database.recentSymbols())
        case "settings":
            return try json(database.settings())
        case "updateSettings":
            let settings = try decode(TradeGateSettings.self, from: data)
            try database.updateSettings(settings)
            return try json(database.settings())
        case "acknowledge":
            try await coordinator.acknowledgeError()
            return try await json(coordinator.snapshot())
        case "register":
            let body = try decode(IDPayload.self, from: data)
            try await coordinator.registerDevice(serial: body.id)
            return try await json(coordinator.snapshot())
        case "onboardingCycle":
            let body = try decode(IDPayload.self, from: data)
            try await coordinator.onboardingLockCycle(serial: body.id)
            return try await json(coordinator.snapshot())
        case "startReview":
            let body = try decode(IDPayload.self, from: data)
            return try json(database.startReview(executionID: body.id))
        case "completeEntryReview":
            let body = try decode(EntryReviewPayload.self, from: data)
            return try json(database.completeEntryReview(reviewID: body.reviewID, actuals: body.actuals))
        case "completeExitReview":
            let body = try decode(ExitReviewPayload.self, from: data)
            return try json(database.completeExitReview(reviewID: body.reviewID, actuals: body.actuals))
        case "startEmergencyReview":
            let body = try decode(IDPayload.self, from: data)
            return try json(database.startEmergencyReview(overrideID: body.id))
        case "completeEmergencyReview":
            let body = try decode(EmergencyReviewPayload.self, from: data)
            return try json(database.completeEmergencyReview(reviewID: body.reviewID, answers: body.answers))
        case "pendingReviews":
            return try json(PendingReviews(count: database.pendingReviewCount(), executions: database.executions(planID: nil)))
        case "reviewQueue":
            return try json(database.reviewQueue())
        case "export":
            return try json(database.exportDocument())
        case "exportCSV":
            return try json(database.exportCSV())
        case "backup":
            let body = try decode(PathPayload.self, from: data)
            try database.backup(to: body.path)
            return #"{"copied":true}"#
        case "verify":
            return try json(database.verifyAuditChain())
        case "appStarted":
            return try json(database.appendAudit(AuditEventDraft(eventType: .appStarted)))
        default:
            throw TradeGateError.invalidState("unknown action \(action)")
        }
    }

    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

public struct IDPayload: Codable, Sendable {
    public var id: String
    public init(id: String) {
        self.id = id
    }
}

public struct PathPayload: Codable, Sendable {
    public var path: String
    public init(path: String) {
        self.path = path
    }
}

public struct NoTradePayload: Codable, Sendable {
    public var id: String
    public var disposition: NoTradeDisposition
    public init(id: String, disposition: NoTradeDisposition) {
        self.id = id
        self.disposition = disposition
    }
}

public struct EntryReviewPayload: Codable, Sendable {
    public var reviewID: String
    public var actuals: EntryReviewActuals
    public init(reviewID: String, actuals: EntryReviewActuals) {
        self.reviewID = reviewID
        self.actuals = actuals
    }
}

public struct ExitReviewPayload: Codable, Sendable {
    public var reviewID: String
    public var actuals: ExitReviewActuals
    public init(reviewID: String, actuals: ExitReviewActuals) {
        self.reviewID = reviewID
        self.actuals = actuals
    }
}

public struct EmergencyReviewPayload: Codable, Sendable {
    public var reviewID: String
    public var answers: EmergencyReviewAnswers
    public init(reviewID: String, answers: EmergencyReviewAnswers) {
        self.reviewID = reviewID
        self.answers = answers
    }
}

public struct PendingReviews: Codable, Sendable {
    public var count: Int
    public var executions: [ExecutionRecord]
}
