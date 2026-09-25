import Foundation

public enum EmergencyValidationError: String, Error, Equatable, Sendable {
    case emptySymbol
    case reasonTooShort
    case confirmationPhraseMismatch
}

public enum EmergencyGate {
    public static func canStartCountdown(reason: String, phrase: String) -> Bool {
        reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= EmergencyValidator.minimumReasonLength
            && phrase == EmergencyValidator.confirmationPhrase
    }

    public static func canConfirm(armedAt: Date, now: Date, countdownSeconds: Int) -> Bool {
        now.timeIntervalSince(armedAt) >= TimeInterval(countdownSeconds)
    }
}

public enum EmergencyValidator {
    public static let confirmationPhrase = "EMERGENCY UNLOCK"
    public static let minimumReasonLength = 10

    public static func validate(_ input: EmergencyOverrideInput) -> [EmergencyValidationError] {
        var errors: [EmergencyValidationError] = []
        if input.symbol.isEmpty {
            errors.append(.emptySymbol)
        }
        let reason = input.reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.count < minimumReasonLength {
            errors.append(.reasonTooShort)
        }
        if input.confirmationPhrase != confirmationPhrase {
            errors.append(.confirmationPhraseMismatch)
        }
        return errors
    }
}

public enum ReviewValidationError: String, Error, Equatable, Sendable {
    case missingDeviationReason
    case priceNotPositive
    case positionNotPositive
    case percentOutOfRange
    case missingPosition
    case missingAnswer
}

public enum ReviewValidator {
    public static func validate(entry: EntryReviewActuals) -> [ReviewValidationError] {
        var errors: [ReviewValidationError] = []
        if !entry.stopPrice.isPositive || !entry.executionPrice.isPositive {
            errors.append(.priceNotPositive)
        }
        switch entry.positionMode {
        case .percent:
            if !entry.positionValue.isPositive {
                errors.append(.positionNotPositive)
            } else if entry.positionValue.decimal > 100 {
                errors.append(.percentOutOfRange)
            }
        case .quantity:
            if !entry.positionValue.isPositive {
                errors.append(.positionNotPositive)
            }
        }
        errors.append(contentsOf: deviationErrors(entry.adherence, entry.deviationReason))
        return errors
    }

    public static func validate(exit: ExitReviewActuals) -> [ReviewValidationError] {
        var errors: [ReviewValidationError] = []
        if !exit.plannedExitPrice.isPositive {
            errors.append(.priceNotPositive)
        }
        switch exit.exitPositionMode {
        case .all:
            break
        case .percent:
            guard let value = exit.exitPositionValue else {
                errors.append(.missingPosition)
                break
            }
            if !value.isPositive {
                errors.append(.positionNotPositive)
            } else if value.decimal > 100 {
                errors.append(.percentOutOfRange)
            }
        case .quantity:
            guard let value = exit.exitPositionValue else {
                errors.append(.missingPosition)
                break
            }
            if !value.isPositive {
                errors.append(.positionNotPositive)
            }
        }
        errors.append(contentsOf: deviationErrors(exit.adherence, exit.deviationReason))
        return errors
    }

    public static func validate(emergency: EmergencyReviewAnswers) -> [ReviewValidationError] {
        let why = emergency.why.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = emergency.howToAvoidNextTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if why.isEmpty || next.isEmpty {
            return [.missingAnswer]
        }
        return []
    }

    private static func deviationErrors(_ adherence: PlanAdherence, _ reason: String?) -> [ReviewValidationError] {
        guard adherence != .exact else { return [] }
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? [.missingDeviationReason] : []
    }
}
