import Foundation
import Testing
@testable import TradeGateCore

@Test func signalNotAppearedCanBeSavedButNotUnlocked() throws {
    var plan = try Fixtures.entryPlan()
    plan.entry?.signalStatus = .notAppeared
    plan.entry?.signalTimeframe = nil
    plan.entry?.stopPrice = nil
    plan.entry?.positionMode = nil
    plan.entry?.positionValue = nil
    let result = PlanValidator.validate(plan)
    #expect(result.canSave)
    #expect(!result.canRequestUnlock)
    #expect(result.errors.isEmpty)
}

@Test func appearedSignalRequiresTimeframeAndStop() throws {
    var plan = try Fixtures.entryPlan()
    plan.entry?.signalTimeframe = nil
    plan.entry?.stopPrice = nil
    let result = PlanValidator.validate(plan)
    #expect(!result.canSave)
    #expect(result.errors.contains(.missingSignalTimeframe))
    #expect(result.errors.contains(.missingStopPrice))
}

@Test func stopPriceMustBePositive() throws {
    var plan = try Fixtures.entryPlan()
    plan.entry?.stopPrice = try DecimalValue(parsing: "0")
    #expect(PlanValidator.validate(plan).errors.contains(.stopPriceNotPositive))
}

@Test func percentPositionMustBeLegal() throws {
    var plan = try Fixtures.entryPlan()
    plan.entry?.positionValue = try DecimalValue(parsing: "101")
    #expect(PlanValidator.validate(plan).errors.contains(.percentOutOfRange))
    plan.entry?.positionValue = try DecimalValue(parsing: "0")
    #expect(PlanValidator.validate(plan).errors.contains(.positionNotPositive))
    plan.entry?.positionValue = try DecimalValue(parsing: "20")
    #expect(PlanValidator.validate(plan).canRequestUnlock)
}

@Test func symbolNormalization() {
    let symbol = Symbol(raw: " nvda ")
    #expect(symbol.raw == " nvda ")
    #expect(symbol.normalized == "NVDA")
}

@Test func decimalRejectsFloatText() throws {
    #expect(throws: DecimalValueError.invalid) {
        try DecimalValue(parsing: "1e2")
    }
    #expect(throws: DecimalValueError.invalid) {
        try DecimalValue(parsing: "abc")
    }
    let value = try DecimalValue(parsing: "182.50")
    #expect(value.storage == "182.5")
    #expect(value.decimal == Decimal(string: "182.5"))
    let percent = try DecimalValue(parsing: "50%")
    #expect(percent.storage == "50")
    let widePercent = try DecimalValue(parsing: "50％")
    #expect(widePercent.storage == "50")
}

@Test func emergencyPhraseMustMatch() {
    let input = EmergencyOverrideInput(
        application: .ibkr,
        symbol: Symbol(raw: "NVDA"),
        reasonCategory: .positionRisk,
        reasonText: "need to cut risk",
        confirmationPhrase: "emergency unlock"
    )
    #expect(EmergencyValidator.validate(input) == [.confirmationPhraseMismatch])
}

@Test func deviationReasonRequired() throws {
    var actuals = try Fixtures.entryReview()
    actuals.adherence = .deviation
    actuals.deviationReason = "  "
    #expect(ReviewValidator.validate(entry: actuals) == [.missingDeviationReason])
}

enum Fixtures {
    static func entryPlan() throws -> TradePlan {
        try TradePlan(
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
                stopPrice: DecimalValue(parsing: "182.50"),
                positionMode: .percent,
                positionValue: DecimalValue(parsing: "20")
            )
        )
    }

    static func entryReview() throws -> EntryReviewActuals {
        try EntryReviewActuals(
            timeframe: .threeDay,
            majorPullback: .twoLeg,
            mediumPullback: .oneLeg,
            smallDivergence: .m5,
            signalStatus: .appeared,
            signalTimeframe: .m5,
            stopPrice: DecimalValue(parsing: "181"),
            positionMode: .percent,
            positionValue: DecimalValue(parsing: "30"),
            executionPrice: DecimalValue(parsing: "188.30"),
            adherence: .exact
        )
    }
}
