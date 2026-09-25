import CryptoKit
import Foundation

public struct AuditEvent: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var timestamp: Date
    public var eventType: AuditEventType
    public var application: TradingApplication?
    public var symbol: String?
    public var planID: String?
    public var executionID: String?
    public var reviewID: String?
    public var unlockSessionID: String?
    public var metadataJSON: String
    public var prevHash: String
    public var eventHash: String
    public var timestampText: String

    public init(
        id: String,
        timestamp: Date,
        eventType: AuditEventType,
        application: TradingApplication?,
        symbol: String?,
        planID: String?,
        executionID: String?,
        reviewID: String?,
        unlockSessionID: String?,
        metadataJSON: String,
        prevHash: String,
        eventHash: String,
        timestampText: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.application = application
        self.symbol = symbol
        self.planID = planID
        self.executionID = executionID
        self.reviewID = reviewID
        self.unlockSessionID = unlockSessionID
        self.metadataJSON = metadataJSON
        self.prevHash = prevHash
        self.eventHash = eventHash
        self.timestampText = timestampText
    }
}

public struct AuditEventDraft: Equatable, Sendable {
    public var eventType: AuditEventType
    public var application: TradingApplication?
    public var symbol: String?
    public var planID: String?
    public var executionID: String?
    public var reviewID: String?
    public var unlockSessionID: String?
    public var metadata: [String: String]
    public var timestamp: Date

    public init(
        eventType: AuditEventType,
        application: TradingApplication? = nil,
        symbol: String? = nil,
        planID: String? = nil,
        executionID: String? = nil,
        reviewID: String? = nil,
        unlockSessionID: String? = nil,
        metadata: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.eventType = eventType
        self.application = application
        self.symbol = symbol
        self.planID = planID
        self.executionID = executionID
        self.reviewID = reviewID
        self.unlockSessionID = unlockSessionID
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

public struct AuditVerification: Equatable, Sendable, Codable {
    public var eventCount: Int
    public var headHash: String?

    public init(eventCount: Int, headHash: String?) {
        self.eventCount = eventCount
        self.headHash = headHash
    }
}

public enum AuditHasher {
    public static let genesisPrevHash = String(repeating: "0", count: 64)

    public static func canonicalPayload(id: String, event: AuditEvent) throws -> String {
        try canonicalPayload(
            id: id,
            timestamp: event.timestampText,
            eventType: event.eventType.rawValue,
            application: event.application?.rawValue,
            symbol: event.symbol,
            planID: event.planID,
            executionID: event.executionID,
            reviewID: event.reviewID,
            unlockSessionID: event.unlockSessionID,
            metadataJSON: event.metadataJSON
        )
    }

    public static func canonicalPayload(
        id: String,
        timestamp: String,
        eventType: String,
        application: String?,
        symbol: String?,
        planID: String?,
        executionID: String?,
        reviewID: String?,
        unlockSessionID: String?,
        metadataJSON: String
    ) throws -> String {
        let object: [String: Any] = [
            "id": id,
            "timestamp": timestamp,
            "event_type": eventType,
            "application": application ?? NSNull(),
            "symbol": symbol ?? NSNull(),
            "plan_id": planID ?? NSNull(),
            "execution_id": executionID ?? NSNull(),
            "review_id": reviewID ?? NSNull(),
            "unlock_session_id": unlockSessionID ?? NSNull(),
            "metadata_json": metadataJSON,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw TradeGateError.invalidState("audit payload was not UTF-8")
        }
        return text
    }

    public static func hash(prevHash: String, canonicalPayload: String) -> String {
        let digest = SHA256.hash(data: Data((prevHash + canonicalPayload).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
