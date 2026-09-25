import Foundation
import SQLite3
import Testing
@testable import TradeGateCore

@Test func storeUsesWALForeignKeysAndDecimalText() throws {
    let database = try makeDatabase()
    let status = try database.status()
    #expect(status.schemaVersion == 1)
    #expect(status.foreignKeysEnabled)
    #expect(status.journalMode == "wal")
    let settings = try database.settings()
    #expect(settings.unlockDurationSeconds == 120)
    #expect(settings.emergencyCountdownSeconds == 20)

    var plan = try entryPlan()
    plan.symbol = Symbol(raw: " nvda ")
    let saved = try database.createPlan(plan)
    #expect(saved.symbol.normalized == "NVDA")
    #expect(saved.entry?.stopPrice?.storage == "182.5")
    #expect(try priceColumnType(path: database.path) == "TEXT")
}

@Test func revisionsKeepOlderPlans() throws {
    let database = try makeDatabase()
    var plan = try database.createPlan(try entryPlan())
    plan.entry?.stopPrice = try DecimalValue(parsing: "175")
    plan.entry?.positionValue = try DecimalValue(parsing: "30")
    let updated = try database.updatePlan(plan)
    let revisions = try database.revisions(planID: updated.id)
    #expect(revisions.count == 2)
    #expect(revisions[0].snapshotJSON.contains("182.5"))
    #expect(revisions[1].snapshotJSON.contains("175"))
    #expect(try database.plan(id: updated.id)?.entry?.stopPrice?.storage == "175")
}

@Test func signalNotAppearedCannotBeApproved() throws {
    let database = try makeDatabase()
    var plan = try entryPlan()
    plan.entry?.signalStatus = .notAppeared
    plan.entry?.signalTimeframe = nil
    plan.entry?.stopPrice = nil
    plan.entry?.positionMode = nil
    plan.entry?.positionValue = nil
    let saved = try database.createPlan(plan)
    #expect(throws: TradeGateError.notUnlockable) {
        try database.approvePlan(id: saved.id)
    }
}

@Test func executionRequiresReviewUntilCompleted() throws {
    let database = try makeDatabase()
    let plan = try database.createPlan(try entryPlan())
    #expect(try database.pendingReviewCount() == 0)
    let execution = try database.confirmExecution(
        ExecutionInput(
            planID: plan.id,
            price: try DecimalValue(parsing: "188.30"),
            positionMode: .percent,
            positionValue: try DecimalValue(parsing: "30")
        )
    )
    #expect(execution.reviewRequired)
    #expect(try database.pendingReviewCount() == 1)
    let review = try database.startReview(executionID: execution.id)
    _ = try database.completeEntryReview(reviewID: review.id, actuals: try entryReview())
    #expect(try database.pendingReviewCount() == 0)
    let verification = try database.verifyAuditChain()
    #expect(verification.eventCount > 0)
}

@Test func noExecutionDoesNotRequireReview() throws {
    let database = try makeDatabase()
    let plan = try database.createPlan(try entryPlan())
    let closed = try database.recordNoTrade(planID: plan.id, disposition: .noExecution)
    #expect(closed.status == .noExecution)
    #expect(try database.pendingReviewCount() == 0)
    #expect(try database.auditEvents().map(\.eventType).contains(.noExecution))
}

@Test func emergencyOverrideLeavesReview() throws {
    let database = try makeDatabase()
    let override = try database.recordEmergencyOverride(
        EmergencyOverrideInput(
            application: .kraken,
            symbol: Symbol(raw: "btc"),
            reasonCategory: .brokerOrSystemFailure,
            reasonText: "broker page would not load",
            confirmationPhrase: "EMERGENCY UNLOCK"
        )
    )
    #expect(override.symbol.normalized == "BTC")
    #expect(override.reviewRequired)
    #expect(try database.pendingReviewCount() == 1)
    let types = try database.auditEvents().map(\.eventType)
    #expect(types.contains(.emergencyOverrideRequested))
    #expect(types.contains(.emergencyOverrideApproved))
    #expect(types.contains(.reviewRequired))
    let review = try database.startEmergencyReview(overrideID: override.id)
    _ = try database.completeEmergencyReview(
        reviewID: review.id,
        answers: EmergencyReviewAnswers(
            why: "broker login was broken",
            didTrade: false,
            changedPosition: false,
            couldHaveUsedNormalFlow: false,
            howToAvoidNextTime: "wait for the site"
        )
    )
    #expect(try database.pendingReviewCount() == 0)
    _ = try database.verifyAuditChain()
}

@Test func auditRejectsUpdateAndDelete() throws {
    let database = try makeDatabase()
    _ = try database.appendAudit(AuditEventDraft(eventType: .daemonStarted))
    #expect(throws: TradeGateError.self) {
        try mutateAudit(path: database.path, sql: "UPDATE audit_events SET event_type = 'APP_STARTED';")
    }
    #expect(throws: TradeGateError.self) {
        try mutateAudit(path: database.path, sql: "DELETE FROM audit_events;")
    }
    #expect(try database.auditEvents().count == 1)
    _ = try database.verifyAuditChain()
}

@Test func foreignKeyRejectsUnknownPlan() throws {
    let database = try makeDatabase()
    #expect(throws: TradeGateError.self) {
        try database.confirmExecution(
            ExecutionInput(
                planID: "missing",
                price: try DecimalValue(parsing: "1"),
                positionMode: .quantity,
                positionValue: try DecimalValue(parsing: "1")
            )
        )
    }
}

@Test func reviewQueueSeparatesExitAndEmergency() throws {
    let database = try makeDatabase()
    var exit = TradePlan(
        application: .ibkr,
        symbol: Symbol(raw: "QQQ"),
        planType: .exit,
        exit: ExitPlanFields(
            timeframe: .oneDay,
            secondaryState: .oneLegUp,
            exitStrategy: .fullExitOnBreak,
            plannedExitPrice: try DecimalValue(parsing: "500"),
            exitPositionMode: .all
        )
    )
    exit = try database.createPlan(exit)
    _ = try database.confirmExecution(ExecutionInput(
        planID: exit.id,
        price: try DecimalValue(parsing: "501"),
        positionMode: .all
    ))
    _ = try database.recordEmergencyOverride(EmergencyOverrideInput(
        application: .kraken,
        symbol: Symbol(raw: "BTC"),
        reasonCategory: .positionRisk,
        reasonText: "need to cut risk",
        confirmationPhrase: "EMERGENCY UNLOCK"
    ))
    let queue = try database.reviewQueue()
    #expect(queue.contains { $0.kind == "exit" && $0.symbol == "QQQ" })
    #expect(queue.contains { $0.kind == "emergency" && $0.symbol == "BTC" })
    let emergency = try #require(queue.first { $0.kind == "emergency" })
    let review = try database.startEmergencyReview(overrideID: emergency.targetID)
    _ = try database.completeEmergencyReview(
        reviewID: review.id,
        answers: EmergencyReviewAnswers(
            why: "risk was live",
            didTrade: false,
            changedPosition: false,
            couldHaveUsedNormalFlow: false,
            howToAvoidNextTime: "write the plan earlier"
        )
    )
    #expect(!(try database.reviewQueue().contains { $0.kind == "emergency" }))
}

private func entryPlan() throws -> TradePlan {
    TradePlan(
        application: .ibkr,
        symbol: Symbol(raw: "NVDA"),
        planType: .entry,
        entry: EntryPlanFields(
            timeframe: .threeDay,
            majorPullback: .twoLeg,
            mediumPullback: .oneLeg,
            smallDivergence: .m15,
            signalStatus: .appeared,
            signalTimeframe: .m30,
            stopPrice: try DecimalValue(parsing: "182.50"),
            positionMode: .percent,
            positionValue: try DecimalValue(parsing: "20")
        )
    )
}

private func entryReview() throws -> EntryReviewActuals {
    EntryReviewActuals(
        timeframe: .threeDay,
        majorPullback: .twoLeg,
        mediumPullback: .oneLeg,
        smallDivergence: .m5,
        signalStatus: .appeared,
        signalTimeframe: .m5,
        stopPrice: try DecimalValue(parsing: "181"),
        positionMode: .percent,
        positionValue: try DecimalValue(parsing: "30"),
        executionPrice: try DecimalValue(parsing: "188.30"),
        adherence: .exact
    )
}

private func makeDatabase() throws -> TradeGateDatabase {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tradegate-\(UUID().uuidString).sqlite")
    return try TradeGateDatabase(path: url.path)
}

private func priceColumnType(path: String) throws -> String {
    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK else {
        throw TradeGateError.sqlite("open failed")
    }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA table_info(trade_plans);", -1, &statement, nil) == SQLITE_OK else {
        throw TradeGateError.sqlite("prepare failed")
    }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW {
        guard let nameRaw = sqlite3_column_text(statement, 1),
              let typeRaw = sqlite3_column_text(statement, 2) else {
            continue
        }
        if String(cString: nameRaw) == "stop_price" {
            return String(cString: typeRaw)
        }
    }
    return ""
}

private func mutateAudit(path: String, sql: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK else {
        throw TradeGateError.sqlite("open failed")
    }
    defer { sqlite3_close(db) }
    sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    var error: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &error)
    if rc != SQLITE_OK {
        let message = error.map { String(cString: $0) } ?? "sqlite \(rc)"
        sqlite3_free(error)
        throw TradeGateError.sqlite(message)
    }
}
