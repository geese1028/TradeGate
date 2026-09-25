import Foundation

public struct Symbol: Equatable, Sendable {
    public var raw: String
    public var normalized: String

    public init(raw: String) {
        self.raw = raw
        normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public var isEmpty: Bool {
        normalized.isEmpty
    }
}

extension Symbol: Codable {
    enum CodingKeys: String, CodingKey {
        case raw
        case normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .raw)
        self.init(raw: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(raw, forKey: .raw)
        try container.encode(normalized, forKey: .normalized)
    }
}
