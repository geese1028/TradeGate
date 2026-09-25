import Foundation

public enum DecimalValueError: Error, Equatable, Sendable {
    case invalid
}

public struct DecimalValue: Equatable, Sendable {
    public let decimal: Decimal
    public let storage: String

    public init(parsing raw: String) throws {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%") || trimmed.hasSuffix("％") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard Self.isPlainDecimal(trimmed) else {
            throw DecimalValueError.invalid
        }
        guard let decimal = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecimalValueError.invalid
        }
        self.decimal = decimal
        storage = NSDecimalNumber(decimal: decimal).stringValue
    }

    public init(decimal: Decimal) {
        self.decimal = decimal
        storage = NSDecimalNumber(decimal: decimal).stringValue
    }

    public var isPositive: Bool {
        decimal > 0
    }

    private static func isPlainDecimal(_ raw: String) -> Bool {
        guard !raw.isEmpty else { return false }
        var body = raw[...]
        if body.first == "-" {
            body = body.dropFirst()
        }
        guard !body.isEmpty else { return false }
        var dots = 0
        for character in body {
            if character == "." {
                dots += 1
                if dots > 1 {
                    return false
                }
            } else if !character.isNumber {
                return false
            }
        }
        return true
    }
}

extension DecimalValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = try Self(parsing: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }
}
