import Foundation

public struct AuditFilter: Equatable, Sendable, Codable {
    public var day: String?
    public var application: TradingApplication?
    public var symbol: String?
    public var eventType: AuditEventType?
    public var emergencyOnly: Bool

    public init(
        day: String? = nil,
        application: TradingApplication? = nil,
        symbol: String? = nil,
        eventType: AuditEventType? = nil,
        emergencyOnly: Bool = false
    ) {
        self.day = day
        self.application = application
        self.symbol = symbol
        self.eventType = eventType
        self.emergencyOnly = emergencyOnly
    }
}

public struct DashboardStats: Equatable, Sendable, Codable {
    public var unlockCount: Int
    public var emergencyCount: Int
    public var tradeCount: Int
    public var noExecutionUnlockCount: Int
    public var exactCount: Int
    public var deviationCount: Int
    public var significantDeviationCount: Int
    public var positionDeviationCount: Int
    public var stopDeviationCount: Int
    public var earlyEntryCount: Int

    public init(
        unlockCount: Int, emergencyCount: Int, tradeCount: Int, noExecutionUnlockCount: Int,
        exactCount: Int, deviationCount: Int, significantDeviationCount: Int,
        positionDeviationCount: Int, stopDeviationCount: Int, earlyEntryCount: Int
    ) {
        self.unlockCount = unlockCount
        self.emergencyCount = emergencyCount
        self.tradeCount = tradeCount
        self.noExecutionUnlockCount = noExecutionUnlockCount
        self.exactCount = exactCount
        self.deviationCount = deviationCount
        self.significantDeviationCount = significantDeviationCount
        self.positionDeviationCount = positionDeviationCount
        self.stopDeviationCount = stopDeviationCount
        self.earlyEntryCount = earlyEntryCount
    }

    public var adherenceRate: Double {
        let total = exactCount + deviationCount + significantDeviationCount
        guard total > 0 else { return 0 }
        return Double(exactCount) / Double(total)
    }
}

public struct JournalEntry: Equatable, Sendable, Codable {
    public var plan: TradePlan
    public var executions: [ExecutionRecord]
    public var reviewCompleted: Bool

    public init(plan: TradePlan, executions: [ExecutionRecord], reviewCompleted: Bool) {
        self.plan = plan
        self.executions = executions
        self.reviewCompleted = reviewCompleted
    }
}

extension TradeGateDatabase {
    public func listPlans() throws -> [TradePlan] {
        try locked {
            var ids: [String] = []
            try connection.query("SELECT id FROM trade_plans ORDER BY updated_at DESC;") { statement in
                if let id = columnText(statement, 0) { ids.append(id) }
            }
            return try ids.compactMap { try planLocked(id: $0) }
        }
    }

    public func recentSymbols(limit: Int = 8) throws -> [String] {
        try locked {
            var symbols: [String] = []
            try connection.query(
                """
                SELECT normalized_symbol FROM trade_plans
                GROUP BY normalized_symbol
                ORDER BY MAX(updated_at) DESC
                LIMIT ?;
                """,
                bindings: [.integer(Int64(limit))]
            ) { statement in
                if let symbol = columnText(statement, 0) { symbols.append(symbol) }
            }
            return symbols
        }
    }

    public func executions(planID: String?) throws -> [ExecutionRecord] {
        try locked {
            var rows: [ExecutionRecord] = []
            let sql: String
            let bindings: [SQLiteValue]
            if let planID {
                sql = "SELECT \(executionColumns) FROM executions WHERE plan_id = ? ORDER BY executed_at ASC;"
                bindings = [.text(planID)]
            } else {
                sql = "SELECT \(executionColumns) FROM executions ORDER BY executed_at ASC;"
                bindings = []
            }
            try connection.query(sql, bindings: bindings) { statement in
                rows.append(try readExecution(statement))
            }
            return rows
        }
    }

    public func todayUnlockCount(now: Date = Date()) throws -> Int {
        let start = Timestamp.string(from: Calendar.current.startOfDay(for: now))
        return try locked {
            var count = 0
            try connection.query(
                """
                SELECT COUNT(*) FROM audit_events
                WHERE event_type = 'YUBIKEY_UNLOCKED'
                  AND timestamp >= ?
                  AND metadata_json NOT LIKE '%"context":"onboarding"%';
                """,
                bindings: [.text(start)]
            ) { statement in
                count = Int(columnInt(statement, 0))
            }
            return count
        }
    }

    public func filteredAuditEvents(_ filter: AuditFilter) throws -> [AuditEvent] {
        try auditEvents().filter { event in
            if let day = filter.day, !event.timestampText.hasPrefix(day) { return false }
            if let application = filter.application, event.application != application { return false }
            if let symbol = filter.symbol, event.symbol != symbol { return false }
            if let eventType = filter.eventType, event.eventType != eventType { return false }
            if filter.emergencyOnly {
                let emergencyTypes: Set<AuditEventType> = [
                    .emergencyOverrideRequested, .emergencyOverrideApproved
                ]
                let metadataEmergency = event.metadataJSON.contains("emergency")
                if !emergencyTypes.contains(event.eventType) && !metadataEmergency { return false }
            }
            return true
        }
    }

    public func journal() throws -> [JournalEntry] {
        let plans = try listPlans()
        return try plans.map { plan in
            let fills = try executions(planID: plan.id)
            let completed = try reviewCompleted(forPlanID: plan.id, executionIDs: fills.map(\.id))
            return JournalEntry(plan: plan, executions: fills, reviewCompleted: completed)
        }
    }

    public func dashboard(since: Date) throws -> DashboardStats {
        let sinceText = Timestamp.string(from: since)
        let events = try auditEvents().filter { $0.timestampText >= sinceText }
        let plans = try listPlans()
        var positionDeviation = 0
        var stopDeviation = 0
        var earlyEntry = 0
        var exact = 0
        var deviation = 0
        var significant = 0
        let reviews = try allReviews()
        for review in reviews where (review.completedAt ?? .distantPast) >= since {
            switch review.planAdherence {
            case .exact: exact += 1
            case .deviation: deviation += 1
            case .significantDeviation: significant += 1
            case nil: break
            }
            guard let planID = try executionPlanID(review.executionID),
                  let plan = plans.first(where: { $0.id == planID }),
                  let data = review.actualJSON.data(using: .utf8),
                  let actuals = try? JSONDecoder().decode(EntryReviewActuals.self, from: data),
                  let entry = plan.entry
            else { continue }
            if actuals.stopPrice != entry.stopPrice { stopDeviation += 1 }
            if actuals.positionMode != entry.positionMode || actuals.positionValue != entry.positionValue {
                positionDeviation += 1
            }
            if let planned = entry.signalTimeframe, let actual = actuals.signalTimeframe,
               signalRank(actual) < signalRank(planned) {
                earlyEntry += 1
            }
        }
        return DashboardStats(
            unlockCount: events.filter { $0.eventType == .yubiKeyUnlocked && !$0.metadataJSON.contains("onboarding") }.count,
            emergencyCount: events.filter { $0.eventType == .emergencyOverrideApproved }.count,
            tradeCount: events.filter { $0.eventType == .executionConfirmed }.count,
            noExecutionUnlockCount: events.filter { $0.eventType == .noExecution }.count,
            exactCount: exact,
            deviationCount: deviation,
            significantDeviationCount: significant,
            positionDeviationCount: positionDeviation,
            stopDeviationCount: stopDeviation,
            earlyEntryCount: earlyEntry
        )
    }

    public func exportDocument() throws -> TradeGateExport {
        TradeGateExport(
            plans: try listPlans(),
            revisions: try allRevisions(),
            executions: try executions(planID: nil),
            reviews: try allReviews(),
            auditEvents: try auditEvents()
        )
    }

    public func backup(to destination: String) throws {
        try locked {
            try connection.execute("PRAGMA wal_checkpoint(FULL);")
        }
        if FileManager.default.fileExists(atPath: destination) {
            throw TradeGateError.invalidState("backup destination already exists")
        }
        try FileManager.default.copyItem(atPath: path, toPath: destination)
    }

    public func setFlag(_ key: String, _ value: String) throws {
        try locked {
            try connection.run(
                """
                INSERT INTO settings (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value;
                """,
                bindings: [.text(key), .text(value)]
            )
        }
    }

    public func flag(_ key: String) throws -> String? {
        try locked {
            var value: String?
            try connection.query("SELECT value FROM settings WHERE key = ?;", bindings: [.text(key)]) { statement in
                value = columnText(statement, 0)
            }
            return value
        }
    }

    private func reviewCompleted(forPlanID planID: String, executionIDs: [String]) throws -> Bool {
        let status = try planLocked(id: planID)?.status
        if status == .noExecution || status == .cancelled {
            return true
        }
        guard !executionIDs.isEmpty else { return false }
        for id in executionIDs {
            var done = false
            try connection.query(
                "SELECT 1 FROM reviews WHERE execution_id = ? AND completed_at IS NOT NULL;",
                bindings: [.text(id)]
            ) { _ in
                done = true
            }
            if !done { return false }
        }
        return true
    }

    private func allReviews() throws -> [ReviewRecord] {
        try locked {
            var rows: [ReviewRecord] = []
            try connection.query(
                """
                SELECT id, execution_id, emergency_override_id, created_at, completed_at, actual_json,
                       plan_adherence, deviation_reason, notes
                FROM reviews ORDER BY created_at ASC;
                """
            ) { statement in
                rows.append(
                    ReviewRecord(
                        id: columnText(statement, 0) ?? "",
                        executionID: columnText(statement, 1),
                        emergencyOverrideID: columnText(statement, 2),
                        createdAt: try Timestamp.date(from: columnText(statement, 3) ?? ""),
                        completedAt: try columnText(statement, 4).map { try Timestamp.date(from: $0) },
                        actualJSON: columnText(statement, 5) ?? "{}",
                        planAdherence: columnText(statement, 6).flatMap(PlanAdherence.init(rawValue:)),
                        deviationReason: columnText(statement, 7),
                        notes: columnText(statement, 8)
                    )
                )
            }
            return rows
        }
    }

    private func allRevisions() throws -> [PlanRevision] {
        let plans = try listPlans()
        return try plans.flatMap { try revisions(planID: $0.id) }
    }

    private func executionPlanID(_ executionID: String?) throws -> String? {
        guard let executionID else { return nil }
        return try locked {
            var planID: String?
            try connection.query(
                "SELECT plan_id FROM executions WHERE id = ?;",
                bindings: [.text(executionID)]
            ) { statement in
                planID = columnText(statement, 0)
            }
            return planID
        }
    }
}

private let executionColumns = """
id, plan_id, executed_at, execution_price, execution_position_mode, execution_position_value, confirmed_by_user, review_required
"""

private func readExecution(_ statement: OpaquePointer) throws -> ExecutionRecord {
    guard let mode = ExecutionPositionMode(rawValue: columnText(statement, 4) ?? "") else {
        throw TradeGateError.invalidState("bad execution position mode")
    }
    return ExecutionRecord(
        id: columnText(statement, 0) ?? "",
        planID: columnText(statement, 1),
        executedAt: try Timestamp.date(from: columnText(statement, 2) ?? ""),
        executionPrice: try DecimalValue(parsing: columnText(statement, 3) ?? ""),
        executionPositionMode: mode,
        executionPositionValue: try decimalColumn(statement, 5),
        confirmedByUser: columnBool(statement, 6),
        reviewRequired: columnBool(statement, 7)
    )
}

private func signalRank(_ timeframe: SignalTimeframe) -> Int {
    switch timeframe {
    case .m5: return 1
    case .m30: return 2
    case .h1: return 3
    }
}

public struct TradeGateExport: Equatable, Sendable, Codable {
    public var plans: [TradePlan]
    public var revisions: [PlanRevision]
    public var executions: [ExecutionRecord]
    public var reviews: [ReviewRecord]
    public var auditEvents: [AuditEvent]
}
