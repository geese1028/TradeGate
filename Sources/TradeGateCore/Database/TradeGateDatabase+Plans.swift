import Foundation

extension TradeGateDatabase {
    public func createPlan(_ plan: TradePlan) throws -> TradePlan {
        let validation = PlanValidator.validate(plan)
        guard validation.canSave else {
            throw TradeGateError.validation(validation.errors)
        }
        var stored = plan
        stored.status = .saved
        stored.updatedAt = Date()
        if stored.createdAt.timeIntervalSince1970 == 0 {
            stored.createdAt = stored.updatedAt
        }
        return try locked {
            try transaction {
                try insertPlan(stored)
                try insertRevision(stored, number: 1)
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .planCreated,
                        application: stored.application,
                        symbol: stored.symbol.normalized,
                        planID: stored.id,
                        timestamp: stored.updatedAt
                    )
                )
                return stored
            }
        }
    }

    public func updatePlan(_ plan: TradePlan) throws -> TradePlan {
        let validation = PlanValidator.validate(plan)
        guard validation.canSave else {
            throw TradeGateError.validation(validation.errors)
        }
        return try locked {
            guard var existing = try planLocked(id: plan.id) else {
                throw TradeGateError.notFound(plan.id)
            }
            let previousSignal = existing.entry?.signalStatus
            existing.application = plan.application
            existing.symbol = plan.symbol
            existing.planType = plan.planType
            existing.entry = plan.entry
            existing.exit = plan.exit
            existing.updatedAt = Date()
            let nextNumber = try nextRevisionNumber(planID: plan.id)
            try transaction {
                try writePlan(existing)
                try insertRevision(existing, number: nextNumber)
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .planUpdated,
                        application: existing.application,
                        symbol: existing.symbol.normalized,
                        planID: existing.id,
                        metadata: ["revision": String(nextNumber)],
                        timestamp: existing.updatedAt
                    )
                )
                if previousSignal != .appeared && existing.entry?.signalStatus == .appeared {
                    _ = try appendAuditLocked(
                        AuditEventDraft(
                            eventType: .signalConfirmed,
                            application: existing.application,
                            symbol: existing.symbol.normalized,
                            planID: existing.id,
                            timestamp: existing.updatedAt
                        )
                    )
                }
            }
            return existing
        }
    }

    public func approvePlan(id: String) throws -> TradePlan {
        try locked {
            guard var existing = try planLocked(id: id) else {
                throw TradeGateError.notFound(id)
            }
            let validation = PlanValidator.validate(existing)
            if !validation.errors.isEmpty {
                throw TradeGateError.validation(validation.errors)
            }
            guard validation.canRequestUnlock else {
                throw TradeGateError.notUnlockable
            }
            existing.status = .approved
            existing.updatedAt = Date()
            let nextNumber = try nextRevisionNumber(planID: id)
            try transaction {
                try writePlan(existing)
                try insertRevision(existing, number: nextNumber)
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .planApproved,
                        application: existing.application,
                        symbol: existing.symbol.normalized,
                        planID: existing.id,
                        timestamp: existing.updatedAt
                    )
                )
            }
            return existing
        }
    }

    public func recordNoTrade(planID: String, disposition: NoTradeDisposition) throws -> TradePlan {
        try locked {
            guard var existing = try planLocked(id: planID) else {
                throw TradeGateError.notFound(planID)
            }
            existing.status = disposition == .cancelled ? .cancelled : .noExecution
            existing.updatedAt = Date()
            let nextNumber = try nextRevisionNumber(planID: planID)
            let event: AuditEventType = disposition == .cancelled ? .planCancelled : .noExecution
            try transaction {
                try writePlan(existing)
                try insertRevision(existing, number: nextNumber)
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: event,
                        application: existing.application,
                        symbol: existing.symbol.normalized,
                        planID: existing.id,
                        timestamp: existing.updatedAt
                    )
                )
            }
            return existing
        }
    }

    public func plan(id: String) throws -> TradePlan? {
        try locked { try planLocked(id: id) }
    }

    public func revisions(planID: String) throws -> [PlanRevision] {
        try locked {
            var rows: [PlanRevision] = []
            try connection.query(
                """
                SELECT id, plan_id, revision_number, created_at, snapshot_json
                FROM plan_revisions
                WHERE plan_id = ?
                ORDER BY revision_number ASC;
                """,
                bindings: [.text(planID)]
            ) { statement in
                rows.append(
                    PlanRevision(
                        id: columnText(statement, 0) ?? "",
                        planID: columnText(statement, 1) ?? "",
                        revisionNumber: Int(columnInt(statement, 2)),
                        createdAt: try Timestamp.date(from: columnText(statement, 3) ?? ""),
                        snapshotJSON: columnText(statement, 4) ?? ""
                    )
                )
            }
            return rows
        }
    }

    func planLocked(id: String) throws -> TradePlan? {
        var found: TradePlan?
        try connection.query(
            """
            SELECT id, created_at, updated_at, application, raw_symbol, normalized_symbol, plan_type, status,
                   timeframe, major_pullback, medium_pullback, small_divergence_timeframe, small_divergence_custom,
                   signal_status, signal_timeframe, stop_price, position_mode, position_value,
                   secondary_state, exit_strategy, custom_exit_strategy, planned_exit_price,
                   exit_position_mode, exit_position_value
            FROM trade_plans WHERE id = ?;
            """,
            bindings: [.text(id)]
        ) { statement in
            found = try readPlan(statement)
        }
        return found
    }

    func insertPlan(_ plan: TradePlan) throws {
        try connection.run(planInsertSQL, bindings: planBindings(plan))
    }

    func writePlan(_ plan: TradePlan) throws {
        var bindings = Array(planBindings(plan).dropFirst())
        bindings.append(.text(plan.id))
        try connection.run(
            """
            UPDATE trade_plans SET
                created_at = ?, updated_at = ?, application = ?, raw_symbol = ?, normalized_symbol = ?,
                plan_type = ?, status = ?, timeframe = ?, major_pullback = ?, medium_pullback = ?,
                small_divergence_timeframe = ?, small_divergence_custom = ?, signal_status = ?,
                signal_timeframe = ?, stop_price = ?, position_mode = ?, position_value = ?,
                secondary_state = ?, exit_strategy = ?, custom_exit_strategy = ?, planned_exit_price = ?,
                exit_position_mode = ?, exit_position_value = ?
            WHERE id = ?;
            """,
            bindings: bindings
        )
    }

    func insertRevision(_ plan: TradePlan, number: Int) throws {
        let snapshot = try CanonicalJSON.encode(plan)
        try connection.run(
            """
            INSERT INTO plan_revisions (id, plan_id, revision_number, created_at, snapshot_json)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(UUID().uuidString),
                .text(plan.id),
                .integer(Int64(number)),
                .text(Timestamp.string(from: plan.updatedAt)),
                .text(snapshot)
            ]
        )
    }

    func nextRevisionNumber(planID: String) throws -> Int {
        var number: Int64 = 0
        try connection.query(
            "SELECT COALESCE(MAX(revision_number), 0) FROM plan_revisions WHERE plan_id = ?;",
            bindings: [.text(planID)]
        ) { statement in
            number = columnInt(statement, 0)
        }
        return Int(number) + 1
    }
}

private let planInsertSQL = """
INSERT INTO trade_plans (
    id, created_at, updated_at, application, raw_symbol, normalized_symbol, plan_type, status,
    timeframe, major_pullback, medium_pullback, small_divergence_timeframe, small_divergence_custom,
    signal_status, signal_timeframe, stop_price, position_mode, position_value,
    secondary_state, exit_strategy, custom_exit_strategy, planned_exit_price,
    exit_position_mode, exit_position_value
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
"""

private func planBindings(_ plan: TradePlan) -> [SQLiteValue] {
    let entry = plan.planType == .entry ? plan.entry : nil
    let exit = plan.planType == .exit ? plan.exit : nil
    return [
        .text(plan.id),
        .text(Timestamp.string(from: plan.createdAt)),
        .text(Timestamp.string(from: plan.updatedAt)),
        .text(plan.application.rawValue),
        .text(plan.symbol.raw),
        .text(plan.symbol.normalized),
        .text(plan.planType.rawValue),
        .text(plan.status.rawValue),
        textBinding(entry?.timeframe?.rawValue ?? exit?.timeframe?.rawValue),
        textBinding(entry?.majorPullback?.rawValue),
        textBinding(entry?.mediumPullback?.rawValue),
        textBinding(entry?.smallDivergence?.rawValue),
        textBinding(entry?.smallDivergenceCustom),
        textBinding(entry?.signalStatus?.rawValue),
        textBinding(entry?.signalTimeframe?.rawValue),
        textBinding(entry?.stopPrice?.storage),
        textBinding(entry?.positionMode?.rawValue),
        textBinding(entry?.positionValue?.storage),
        textBinding(exit?.secondaryState?.rawValue),
        textBinding(exit?.exitStrategy?.rawValue),
        textBinding(exit?.customExitStrategy),
        textBinding(exit?.plannedExitPrice?.storage),
        textBinding(exit?.exitPositionMode?.rawValue),
        textBinding(exit?.exitPositionValue?.storage)
    ]
}

private func readPlan(_ statement: OpaquePointer) throws -> TradePlan {
    let id = columnText(statement, 0) ?? ""
    let createdAt = try Timestamp.date(from: columnText(statement, 1) ?? "")
    let updatedAt = try Timestamp.date(from: columnText(statement, 2) ?? "")
    guard let application = TradingApplication(rawValue: columnText(statement, 3) ?? ""),
          let planType = PlanType(rawValue: columnText(statement, 6) ?? ""),
          let status = PlanStatus(rawValue: columnText(statement, 7) ?? "")
    else {
        throw TradeGateError.invalidState("plan \(id) has unknown enum values")
    }
    let symbol = Symbol(raw: columnText(statement, 4) ?? "")
    var entry: EntryPlanFields?
    var exit: ExitPlanFields?
    if planType == .entry {
        entry = EntryPlanFields(
            timeframe: columnText(statement, 8).flatMap(PlanTimeframe.init(rawValue:)),
            majorPullback: columnText(statement, 9).flatMap(MajorPullback.init(rawValue:)),
            mediumPullback: columnText(statement, 10).flatMap(MediumPullback.init(rawValue:)),
            smallDivergence: columnText(statement, 11).flatMap(SmallDivergenceTimeframe.init(rawValue:)),
            smallDivergenceCustom: columnText(statement, 12),
            signalStatus: columnText(statement, 13).flatMap(SignalStatus.init(rawValue:)),
            signalTimeframe: columnText(statement, 14).flatMap(SignalTimeframe.init(rawValue:)),
            stopPrice: try decimalColumn(statement, 15),
            positionMode: columnText(statement, 16).flatMap(PositionMode.init(rawValue:)),
            positionValue: try decimalColumn(statement, 17)
        )
    } else {
        exit = ExitPlanFields(
            timeframe: columnText(statement, 8).flatMap(PlanTimeframe.init(rawValue:)),
            secondaryState: columnText(statement, 18).flatMap(ExitSecondaryState.init(rawValue:)),
            exitStrategy: columnText(statement, 19).flatMap(ExitStrategy.init(rawValue:)),
            customExitStrategy: columnText(statement, 20),
            plannedExitPrice: try decimalColumn(statement, 21),
            exitPositionMode: columnText(statement, 22).flatMap(ExitPositionMode.init(rawValue:)),
            exitPositionValue: try decimalColumn(statement, 23)
        )
    }
    return TradePlan(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        application: application,
        symbol: symbol,
        planType: planType,
        status: status,
        entry: entry,
        exit: exit
    )
}
