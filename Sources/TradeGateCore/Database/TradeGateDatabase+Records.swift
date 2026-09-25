import Foundation

public extension TradeGateDatabase {
    func upsertDevice(_ device: ManagedDevice) throws -> ManagedDevice {
        try locked {
            var existingID: String?
            var createdAt: String?
            try connection.query(
                "SELECT id, created_at FROM managed_devices WHERE serial_number = ?;",
                bindings: [.text(device.serialNumber)]
            ) { statement in
                existingID = columnText(statement, 0)
                createdAt = columnText(statement, 1)
            }
            let stored = try ManagedDevice(
                id: existingID ?? device.id,
                serialNumber: device.serialNumber,
                productName: device.productName,
                firmwareVersion: device.firmwareVersion,
                managedFIDO2: device.managedFIDO2,
                managedU2F: device.managedU2F,
                createdAt: createdAt.map { try Timestamp.date(from: $0) } ?? device.createdAt,
                lastSeenAt: device.lastSeenAt,
                enabled: device.enabled
            )
            try connection.run(
                """
                INSERT INTO managed_devices (
                    id, serial_number, product_name, firmware_version, managed_fido2, managed_u2f,
                    created_at, last_seen_at, enabled
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(serial_number) DO UPDATE SET
                    product_name = excluded.product_name,
                    firmware_version = excluded.firmware_version,
                    managed_fido2 = excluded.managed_fido2,
                    managed_u2f = excluded.managed_u2f,
                    last_seen_at = excluded.last_seen_at,
                    enabled = excluded.enabled;
                """,
                bindings: [
                    .text(stored.id),
                    .text(stored.serialNumber),
                    .text(stored.productName),
                    .text(stored.firmwareVersion),
                    intBinding(stored.managedFIDO2),
                    intBinding(stored.managedU2F),
                    .text(Timestamp.string(from: stored.createdAt)),
                    .text(Timestamp.string(from: stored.lastSeenAt)),
                    intBinding(stored.enabled),
                ]
            )
            return stored
        }
    }

    func device(serialNumber: String) throws -> ManagedDevice? {
        try locked {
            var found: ManagedDevice?
            try connection.query(
                """
                SELECT id, serial_number, product_name, firmware_version, managed_fido2, managed_u2f,
                       created_at, last_seen_at, enabled
                FROM managed_devices WHERE serial_number = ?;
                """,
                bindings: [.text(serialNumber)]
            ) { statement in
                found = try ManagedDevice(
                    id: columnText(statement, 0) ?? "",
                    serialNumber: columnText(statement, 1) ?? "",
                    productName: columnText(statement, 2) ?? "",
                    firmwareVersion: columnText(statement, 3) ?? "",
                    managedFIDO2: columnBool(statement, 4),
                    managedU2F: columnBool(statement, 5),
                    createdAt: Timestamp.date(from: columnText(statement, 6) ?? ""),
                    lastSeenAt: Timestamp.date(from: columnText(statement, 7) ?? ""),
                    enabled: columnBool(statement, 8)
                )
            }
            return found
        }
    }

    func confirmExecution(_ input: ExecutionInput) throws -> ExecutionRecord {
        if !input.price.isPositive {
            throw TradeGateError.reviewValidation([.priceNotPositive])
        }
        switch input.positionMode {
        case .all:
            break
        case .percent:
            guard let value = input.positionValue else {
                throw TradeGateError.reviewValidation([.missingPosition])
            }
            if !value.isPositive {
                throw TradeGateError.reviewValidation([.positionNotPositive])
            }
            if value.decimal > 100 {
                throw TradeGateError.reviewValidation([.percentOutOfRange])
            }
        case .quantity:
            guard let value = input.positionValue, value.isPositive else {
                throw TradeGateError.reviewValidation([.positionNotPositive])
            }
        }
        return try locked {
            var plan: TradePlan?
            if let planID = input.planID {
                guard let found = try planLocked(id: planID) else {
                    throw TradeGateError.notFound(planID)
                }
                plan = found
            }
            let record = ExecutionRecord(
                id: UUID().uuidString,
                planID: plan?.id,
                executedAt: input.executedAt,
                executionPrice: input.price,
                executionPositionMode: input.positionMode,
                executionPositionValue: input.positionMode == .all ? nil : input.positionValue,
                confirmedByUser: true,
                reviewRequired: true
            )
            try transaction {
                try connection.run(
                    """
                    INSERT INTO executions (
                        id, plan_id, executed_at, execution_price, execution_position_mode,
                        execution_position_value, confirmed_by_user, review_required
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(record.id),
                        textBinding(record.planID),
                        .text(Timestamp.string(from: record.executedAt)),
                        .text(record.executionPrice.storage),
                        .text(record.executionPositionMode.rawValue),
                        textBinding(record.executionPositionValue?.storage),
                        intBinding(true),
                        intBinding(true),
                    ]
                )
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .executionConfirmed,
                        application: plan?.application,
                        symbol: plan?.symbol.normalized,
                        planID: plan?.id,
                        executionID: record.id,
                        timestamp: record.executedAt
                    )
                )
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .reviewRequired,
                        application: plan?.application,
                        symbol: plan?.symbol.normalized,
                        planID: plan?.id,
                        executionID: record.id,
                        timestamp: record.executedAt
                    )
                )
            }
            return record
        }
    }

    func startReview(executionID: String) throws -> ReviewRecord {
        try locked {
            guard try executionExists(executionID) else {
                throw TradeGateError.notFound(executionID)
            }
            if try completedReviewExists(executionID: executionID) {
                throw TradeGateError.invalidState("review already completed")
            }
            if try openReviewExists(executionID: executionID) {
                throw TradeGateError.invalidState("review already started")
            }
            let review = ReviewRecord(
                id: UUID().uuidString,
                executionID: executionID,
                emergencyOverrideID: nil,
                createdAt: Date(),
                completedAt: nil,
                actualJSON: "{}",
                planAdherence: nil,
                deviationReason: nil,
                notes: nil
            )
            try transaction {
                try insertReview(review)
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .reviewStarted,
                        executionID: executionID,
                        reviewID: review.id,
                        timestamp: review.createdAt
                    )
                )
            }
            return review
        }
    }

    func completeEntryReview(reviewID: String, actuals: EntryReviewActuals) throws -> ReviewRecord {
        let errors = ReviewValidator.validate(entry: actuals)
        guard errors.isEmpty else { throw TradeGateError.reviewValidation(errors) }
        let json = try CanonicalJSON.encode(actuals)
        return try completeReview(
            reviewID: reviewID,
            actualJSON: json,
            adherence: actuals.adherence,
            deviationReason: actuals.deviationReason,
            notes: actuals.notes
        )
    }

    func completeExitReview(reviewID: String, actuals: ExitReviewActuals) throws -> ReviewRecord {
        let errors = ReviewValidator.validate(exit: actuals)
        guard errors.isEmpty else { throw TradeGateError.reviewValidation(errors) }
        let json = try CanonicalJSON.encode(actuals)
        return try completeReview(
            reviewID: reviewID,
            actualJSON: json,
            adherence: actuals.adherence,
            deviationReason: actuals.deviationReason,
            notes: actuals.notes
        )
    }

    func recordEmergencyOverride(_ input: EmergencyOverrideInput) throws -> EmergencyOverride {
        let errors = EmergencyValidator.validate(input)
        guard errors.isEmpty else { throw TradeGateError.emergencyValidation(errors) }
        let createdAt = Date()
        let record = EmergencyOverride(
            id: UUID().uuidString,
            application: input.application,
            symbol: input.symbol,
            reasonCategory: input.reasonCategory,
            reasonText: input.reasonText.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt,
            reviewRequired: true
        )
        return try locked {
            try transaction {
                try connection.run(
                    """
                    INSERT INTO emergency_overrides (
                        id, application, raw_symbol, normalized_symbol, reason_category, reason_text,
                        created_at, review_required
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 1);
                    """,
                    bindings: [
                        .text(record.id),
                        .text(record.application.rawValue),
                        .text(record.symbol.raw),
                        .text(record.symbol.normalized),
                        .text(record.reasonCategory.rawValue),
                        .text(record.reasonText),
                        .text(Timestamp.string(from: record.createdAt)),
                    ]
                )
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .emergencyOverrideRequested,
                        application: record.application,
                        symbol: record.symbol.normalized,
                        metadata: ["emergency_override_id": record.id],
                        timestamp: createdAt
                    )
                )
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .emergencyOverrideApproved,
                        application: record.application,
                        symbol: record.symbol.normalized,
                        metadata: ["emergency_override_id": record.id],
                        timestamp: createdAt
                    )
                )
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .reviewRequired,
                        application: record.application,
                        symbol: record.symbol.normalized,
                        metadata: ["emergency_override_id": record.id],
                        timestamp: createdAt
                    )
                )
            }
            return record
        }
    }

    func startEmergencyReview(overrideID: String) throws -> ReviewRecord {
        try locked {
            guard try emergencyExists(overrideID) else {
                throw TradeGateError.notFound(overrideID)
            }
            let review = ReviewRecord(
                id: UUID().uuidString,
                executionID: nil,
                emergencyOverrideID: overrideID,
                createdAt: Date(),
                completedAt: nil,
                actualJSON: "{}",
                planAdherence: nil,
                deviationReason: nil,
                notes: nil
            )
            try transaction {
                try insertReview(review)
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .reviewStarted,
                        reviewID: review.id,
                        metadata: ["emergency_override_id": overrideID],
                        timestamp: review.createdAt
                    )
                )
            }
            return review
        }
    }

    func completeEmergencyReview(reviewID: String, answers: EmergencyReviewAnswers) throws -> ReviewRecord {
        let errors = ReviewValidator.validate(emergency: answers)
        guard errors.isEmpty else { throw TradeGateError.reviewValidation(errors) }
        let json = try CanonicalJSON.encode(answers)
        return try completeReview(
            reviewID: reviewID,
            actualJSON: json,
            adherence: nil,
            deviationReason: nil,
            notes: nil
        )
    }

    func pendingReviewCount() throws -> Int {
        try locked {
            var count = 0
            try connection.query(
                """
                SELECT
                    (SELECT COUNT(*) FROM executions e
                     WHERE e.review_required = 1
                       AND NOT EXISTS (
                           SELECT 1 FROM reviews r
                           WHERE r.execution_id = e.id AND r.completed_at IS NOT NULL
                       ))
                    +
                    (SELECT COUNT(*) FROM emergency_overrides o
                     WHERE o.review_required = 1
                       AND NOT EXISTS (
                           SELECT 1 FROM reviews r
                           WHERE r.emergency_override_id = o.id AND r.completed_at IS NOT NULL
                       ));
                """
            ) { statement in
                count = Int(columnInt(statement, 0))
            }
            return count
        }
    }

    func insertUnlockSession(_ session: UnlockSession) throws {
        try locked {
            try connection.run(
                """
                INSERT INTO unlock_sessions (
                    id, application, symbol, plan_id, requested_at, approved_at, unlocked_at, locked_at,
                    duration_seconds, result
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(session.id),
                    .text(session.application.rawValue),
                    .text(session.symbol),
                    textBinding(session.planID),
                    .text(Timestamp.string(from: session.requestedAt)),
                    textBinding(session.approvedAt.map(Timestamp.string(from:))),
                    textBinding(session.unlockedAt.map(Timestamp.string(from:))),
                    textBinding(session.lockedAt.map(Timestamp.string(from:))),
                    session.durationSeconds.map { .integer(Int64($0)) } ?? .null,
                    .text(session.result.rawValue),
                ]
            )
        }
    }

    private func completeReview(
        reviewID: String,
        actualJSON: String,
        adherence: PlanAdherence?,
        deviationReason: String?,
        notes: String?
    ) throws -> ReviewRecord {
        try locked {
            guard var review = try reviewLocked(id: reviewID) else {
                throw TradeGateError.notFound(reviewID)
            }
            guard review.completedAt == nil else {
                throw TradeGateError.invalidState("review already completed")
            }
            review.completedAt = Date()
            review.actualJSON = actualJSON
            review.planAdherence = adherence
            review.deviationReason = deviationReason
            review.notes = notes
            try transaction {
                try connection.run(
                    """
                    UPDATE reviews
                    SET completed_at = ?, actual_json = ?, plan_adherence = ?, deviation_reason = ?, notes = ?
                    WHERE id = ?;
                    """,
                    bindings: [
                        .text(Timestamp.string(from: review.completedAt ?? Date())),
                        .text(actualJSON),
                        textBinding(adherence?.rawValue),
                        textBinding(deviationReason),
                        textBinding(notes),
                        .text(reviewID),
                    ]
                )
                _ = try appendAuditLocked(
                    AuditEventDraft(
                        eventType: .reviewCompleted,
                        executionID: review.executionID,
                        reviewID: review.id,
                        metadata: review.emergencyOverrideID.map { ["emergency_override_id": $0] } ?? [:],
                        timestamp: review.completedAt ?? Date()
                    )
                )
            }
            return review
        }
    }

    private func insertReview(_ review: ReviewRecord) throws {
        try connection.run(
            """
            INSERT INTO reviews (
                id, execution_id, emergency_override_id, created_at, completed_at, actual_json,
                plan_adherence, deviation_reason, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(review.id),
                textBinding(review.executionID),
                textBinding(review.emergencyOverrideID),
                .text(Timestamp.string(from: review.createdAt)),
                textBinding(review.completedAt.map(Timestamp.string(from:))),
                .text(review.actualJSON),
                textBinding(review.planAdherence?.rawValue),
                textBinding(review.deviationReason),
                textBinding(review.notes),
            ]
        )
    }

    private func reviewLocked(id: String) throws -> ReviewRecord? {
        var found: ReviewRecord?
        try connection.query(
            """
            SELECT id, execution_id, emergency_override_id, created_at, completed_at, actual_json,
                   plan_adherence, deviation_reason, notes
            FROM reviews WHERE id = ?;
            """,
            bindings: [.text(id)]
        ) { statement in
            found = try ReviewRecord(
                id: columnText(statement, 0) ?? "",
                executionID: columnText(statement, 1),
                emergencyOverrideID: columnText(statement, 2),
                createdAt: Timestamp.date(from: columnText(statement, 3) ?? ""),
                completedAt: columnText(statement, 4).map { try Timestamp.date(from: $0) },
                actualJSON: columnText(statement, 5) ?? "{}",
                planAdherence: columnText(statement, 6).flatMap(PlanAdherence.init(rawValue:)),
                deviationReason: columnText(statement, 7),
                notes: columnText(statement, 8)
            )
        }
        return found
    }

    private func executionExists(_ id: String) throws -> Bool {
        var found = false
        try connection.query("SELECT 1 FROM executions WHERE id = ?;", bindings: [.text(id)]) { _ in
            found = true
        }
        return found
    }

    private func emergencyExists(_ id: String) throws -> Bool {
        var found = false
        try connection.query(
            "SELECT 1 FROM emergency_overrides WHERE id = ?;",
            bindings: [.text(id)]
        ) { _ in
            found = true
        }
        return found
    }

    private func completedReviewExists(executionID: String) throws -> Bool {
        var found = false
        try connection.query(
            "SELECT 1 FROM reviews WHERE execution_id = ? AND completed_at IS NOT NULL;",
            bindings: [.text(executionID)]
        ) { _ in
            found = true
        }
        return found
    }

    private func openReviewExists(executionID: String) throws -> Bool {
        var found = false
        try connection.query(
            "SELECT 1 FROM reviews WHERE execution_id = ? AND completed_at IS NULL;",
            bindings: [.text(executionID)]
        ) { _ in
            found = true
        }
        return found
    }
}
