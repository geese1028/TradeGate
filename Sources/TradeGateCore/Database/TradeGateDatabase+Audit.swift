import Foundation

extension TradeGateDatabase {
    public func appendAudit(_ draft: AuditEventDraft) throws -> AuditEvent {
        try locked {
            try transaction {
                try appendAuditLocked(draft)
            }
        }
    }

    public func auditEvents() throws -> [AuditEvent] {
        try locked { try auditEventsLocked() }
    }

    public func verifyAuditChain() throws -> AuditVerification {
        try locked {
            let events = try auditEventsLocked()
            var previous = AuditHasher.genesisPrevHash
            for event in events {
                if event.prevHash != previous {
                    throw TradeGateError.auditChainBroken("event \(event.id) prev_hash does not link")
                }
                let payload = try AuditHasher.canonicalPayload(id: event.id, event: event)
                let expected = AuditHasher.hash(prevHash: event.prevHash, canonicalPayload: payload)
                if expected != event.eventHash {
                    throw TradeGateError.auditChainBroken("event \(event.id) hash mismatch")
                }
                previous = event.eventHash
            }
            return AuditVerification(eventCount: events.count, headHash: events.last?.eventHash)
        }
    }

    func appendAuditLocked(_ draft: AuditEventDraft) throws -> AuditEvent {
        let metadataJSON = try CanonicalJSON.metadata(draft.metadata)
        let id = UUID().uuidString
        let timestamp = Timestamp.string(from: draft.timestamp)
        let previous = try latestHashLocked() ?? AuditHasher.genesisPrevHash
        let payload = try AuditHasher.canonicalPayload(
            id: id,
            timestamp: timestamp,
            eventType: draft.eventType.rawValue,
            application: draft.application?.rawValue,
            symbol: draft.symbol,
            planID: draft.planID,
            executionID: draft.executionID,
            reviewID: draft.reviewID,
            unlockSessionID: draft.unlockSessionID,
            metadataJSON: metadataJSON
        )
        let eventHash = AuditHasher.hash(prevHash: previous, canonicalPayload: payload)
        try connection.run(
            """
            INSERT INTO audit_events (
                id, timestamp, event_type, application, symbol, plan_id, execution_id, review_id,
                unlock_session_id, metadata_json, prev_hash, event_hash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(id),
                .text(timestamp),
                .text(draft.eventType.rawValue),
                textBinding(draft.application?.rawValue),
                textBinding(draft.symbol),
                textBinding(draft.planID),
                textBinding(draft.executionID),
                textBinding(draft.reviewID),
                textBinding(draft.unlockSessionID),
                .text(metadataJSON),
                .text(previous),
                .text(eventHash)
            ]
        )
        return AuditEvent(
            id: id,
            timestamp: draft.timestamp,
            eventType: draft.eventType,
            application: draft.application,
            symbol: draft.symbol,
            planID: draft.planID,
            executionID: draft.executionID,
            reviewID: draft.reviewID,
            unlockSessionID: draft.unlockSessionID,
            metadataJSON: metadataJSON,
            prevHash: previous,
            eventHash: eventHash,
            timestampText: timestamp
        )
    }

    func auditEventsLocked() throws -> [AuditEvent] {
        var rows: [AuditEvent] = []
        try connection.query(
            """
            SELECT id, timestamp, event_type, application, symbol, plan_id, execution_id, review_id,
                   unlock_session_id, metadata_json, prev_hash, event_hash
            FROM audit_events
            ORDER BY rowid ASC;
            """
        ) { statement in
            guard let eventType = AuditEventType(rawValue: columnText(statement, 2) ?? "") else {
                throw TradeGateError.invalidState("unknown audit event")
            }
            let application = columnText(statement, 3).flatMap(TradingApplication.init(rawValue:))
            let timestampText = columnText(statement, 1) ?? ""
            rows.append(
                AuditEvent(
                    id: columnText(statement, 0) ?? "",
                    timestamp: try Timestamp.date(from: timestampText),
                    eventType: eventType,
                    application: application,
                    symbol: columnText(statement, 4),
                    planID: columnText(statement, 5),
                    executionID: columnText(statement, 6),
                    reviewID: columnText(statement, 7),
                    unlockSessionID: columnText(statement, 8),
                    metadataJSON: columnText(statement, 9) ?? "{}",
                    prevHash: columnText(statement, 10) ?? "",
                    eventHash: columnText(statement, 11) ?? "",
                    timestampText: timestampText
                )
            )
        }
        return rows
    }

    private func latestHashLocked() throws -> String? {
        var hash: String?
        try connection.query(
            "SELECT event_hash FROM audit_events ORDER BY rowid DESC LIMIT 1;"
        ) { statement in
            hash = columnText(statement, 0)
        }
        return hash
    }
}
