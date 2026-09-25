import Foundation

public enum PlanValidationError: String, Error, Equatable, Sendable {
    case emptySymbol
    case conflictingPlanFields
    case missingTimeframe
    case missingMajorPullback
    case missingMediumPullback
    case missingSmallDivergence
    case missingCustomDivergence
    case missingSignalStatus
    case missingSignalTimeframe
    case missingStopPrice
    case stopPriceNotPositive
    case missingPosition
    case positionNotPositive
    case percentOutOfRange
    case missingSecondaryState
    case missingExitStrategy
    case missingCustomExitStrategy
    case missingPlannedExitPrice
    case exitPriceNotPositive
    case missingExitPosition
}

public struct PlanValidation: Equatable, Sendable {
    public var errors: [PlanValidationError]
    public var canSave: Bool
    public var canRequestUnlock: Bool

    public init(errors: [PlanValidationError], canSave: Bool, canRequestUnlock: Bool) {
        self.errors = errors
        self.canSave = canSave
        self.canRequestUnlock = canRequestUnlock
    }
}

public enum PlanValidator {
    public static func validate(_ plan: TradePlan) -> PlanValidation {
        var errors: [PlanValidationError] = []
        if plan.symbol.isEmpty {
            errors.append(.emptySymbol)
        }

        switch plan.planType {
        case .entry:
            if plan.exit != nil || plan.entry == nil {
                errors.append(.conflictingPlanFields)
            }
            if let entry = plan.entry {
                errors.append(contentsOf: validateEntry(entry))
            }
        case .exit:
            if plan.entry != nil || plan.exit == nil {
                errors.append(.conflictingPlanFields)
            }
            if let exit = plan.exit {
                errors.append(contentsOf: validateExit(exit))
            }
        }

        let canSave = errors.isEmpty
        let signalReady = plan.planType == .exit || plan.entry?.signalStatus == .appeared
        return PlanValidation(
            errors: errors,
            canSave: canSave,
            canRequestUnlock: canSave && signalReady
        )
    }

    private static func validateEntry(_ entry: EntryPlanFields) -> [PlanValidationError] {
        var errors: [PlanValidationError] = []
        if entry.timeframe == nil { errors.append(.missingTimeframe) }
        if entry.majorPullback == nil { errors.append(.missingMajorPullback) }
        if entry.mediumPullback == nil { errors.append(.missingMediumPullback) }
        if entry.smallDivergence == nil {
            errors.append(.missingSmallDivergence)
        } else if entry.smallDivergence == .other {
            let custom = entry.smallDivergenceCustom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if custom.isEmpty { errors.append(.missingCustomDivergence) }
        }
        guard let signal = entry.signalStatus else {
            errors.append(.missingSignalStatus)
            return errors
        }
        guard signal == .appeared else {
            return errors
        }
        if entry.signalTimeframe == nil { errors.append(.missingSignalTimeframe) }
        if entry.stopPrice == nil {
            errors.append(.missingStopPrice)
        } else if entry.stopPrice?.isPositive != true {
            errors.append(.stopPriceNotPositive)
        }
        errors.append(contentsOf: validatePosition(mode: entry.positionMode, value: entry.positionValue))
        return errors
    }

    private static func validateExit(_ exit: ExitPlanFields) -> [PlanValidationError] {
        var errors: [PlanValidationError] = []
        if exit.timeframe == nil { errors.append(.missingTimeframe) }
        if exit.secondaryState == nil { errors.append(.missingSecondaryState) }
        if exit.exitStrategy == nil {
            errors.append(.missingExitStrategy)
        } else if exit.exitStrategy == .custom {
            let custom = exit.customExitStrategy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if custom.isEmpty { errors.append(.missingCustomExitStrategy) }
        }
        if exit.plannedExitPrice == nil {
            errors.append(.missingPlannedExitPrice)
        } else if exit.plannedExitPrice?.isPositive != true {
            errors.append(.exitPriceNotPositive)
        }
        switch exit.exitPositionMode {
        case nil:
            errors.append(.missingExitPosition)
        case .all:
            break
        case .percent:
            errors.append(contentsOf: validatePercent(exit.exitPositionValue))
        case .quantity:
            if exit.exitPositionValue == nil {
                errors.append(.missingPosition)
            } else if exit.exitPositionValue?.isPositive != true {
                errors.append(.positionNotPositive)
            }
        }
        return errors
    }

    private static func validatePosition(mode: PositionMode?, value: DecimalValue?) -> [PlanValidationError] {
        switch mode {
        case nil:
            return [.missingPosition]
        case .percent:
            return validatePercent(value)
        case .quantity:
            if value == nil { return [.missingPosition] }
            if value?.isPositive != true { return [.positionNotPositive] }
            return []
        }
    }

    private static func validatePercent(_ value: DecimalValue?) -> [PlanValidationError] {
        guard let value else { return [.missingPosition] }
        if !value.isPositive { return [.positionNotPositive] }
        if value.decimal > 100 { return [.percentOutOfRange] }
        return []
    }
}
