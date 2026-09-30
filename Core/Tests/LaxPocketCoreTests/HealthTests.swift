import XCTest
@testable import LaxPocketCore

final class BodyUnitsTests: XCTestCase {
    func testFormatsHeight() {
        XCTAssertEqual(BodyUnits.imperial.formatHeight(162.6), "5′4″")
        XCTAssertEqual(BodyUnits.imperial.formatHeight(163.8), "5′4.5″")
        XCTAssertEqual(BodyUnits.imperial.formatHeight(182.8), "6′0″", "71.97 in carries over to the next foot")
        XCTAssertEqual(BodyUnits.imperial.formatHeight(150), "4′11.1″")
        XCTAssertEqual(BodyUnits.metric.formatHeight(162.6), "162.6 cm")
        XCTAssertEqual(BodyUnits.metric.formatHeight(163), "163 cm")
    }

    func testFormatsWeightAndChanges() {
        XCTAssertEqual(BodyUnits.imperial.formatWeight(50.8), "112 lb")
        XCTAssertEqual(BodyUnits.imperial.formatWeight(51.03), "112.5 lb")
        XCTAssertEqual(BodyUnits.metric.formatWeight(50.8), "50.8 kg")
        XCTAssertEqual(BodyUnits.metric.formatHeightChange(2.14), "+2.1 cm")
        XCTAssertEqual(BodyUnits.imperial.formatHeightChange(-2.54), "−1 in")
        XCTAssertEqual(BodyUnits.imperial.formatWeightChange(0.01), "0 lb")
        XCTAssertEqual(BodyUnits.metric.formatWeightChange(1.55), "+1.6 kg")
        XCTAssertEqual(BodyUnits.imperial.formatGrowthRate(7.2), "2.8 in/yr")
        XCTAssertEqual(BodyUnits.metric.formatGrowthRate(7.2), "7.2 cm/yr")
        XCTAssertEqual(BodyUnits.number(-0.04), "0")
        XCTAssertEqual(BodyUnits.number(50.94, decimals: 2), "50.94")
    }

    func testConvertsToStoredPrecision() {
        XCTAssertEqual(BodyUnits.imperial.centimetres(fromHeight: 64), 162.6)
        XCTAssertEqual(BodyUnits.imperial.kilograms(fromWeight: 112), 50.8)
        XCTAssertEqual(BodyUnits.metric.centimetres(fromHeight: 162.56), 162.6)
        XCTAssertEqual(BodyUnits.metric.kilograms(fromWeight: 50.805), 50.81)
        let parts = BodyUnits.feetAndInches(fromCentimetres: 162.6)
        XCTAssertEqual(parts.feet, 5)
        XCTAssertEqual(parts.inches, 4, accuracy: 1e-9)
    }

    func testParsesNumbers() {
        XCTAssertEqual(BodyUnits.parse("4,5"), 4.5)
        XCTAssertEqual(BodyUnits.parse(" 112 "), 112)
        XCTAssertNil(BodyUnits.parse(""))
        XCTAssertNil(BodyUnits.parse("tall"))
        XCTAssertNil(BodyUnits.parse("nan"))
    }
}

final class BodyInputTests: XCTestCase {
    func testImperialFields() {
        var input = BodyInput(units: .imperial)
        XCTAssertTrue(input.isBlank)
        XCTAssertFalse(input.hasError)

        input.feet = "5"
        input.height = "4"
        input.weight = "112"
        XCTAssertEqual(input.heightCm, .valid(162.6))
        XCTAssertEqual(input.weightKg, .valid(50.8))

        input.height = ""
        XCTAssertEqual(input.heightCm, .valid(152.4), "feet alone")
        input.feet = ""
        input.height = "64"
        XCTAssertEqual(input.heightCm, .valid(162.6), "inches alone")
        input.feet = "5"
        XCTAssertEqual(input.heightCm, .invalid, "5 ft 64 in is a typo")
        input.feet = "five"
        XCTAssertEqual(input.heightCm, .invalid)
        input.feet = "15"
        input.height = "0"
        XCTAssertEqual(input.heightCm, .invalid, "outside the accepted range")
        XCTAssertTrue(input.hasError)
    }

    func testMetricFields() {
        var input = BodyInput(units: .metric)
        input.feet = "5"
        XCTAssertEqual(input.heightCm, .blank, "feet are ignored in metric")
        input.height = "162,6"
        input.weight = "5"
        XCTAssertEqual(input.heightCm, .valid(162.6))
        XCTAssertEqual(input.weightKg, .invalid, "5 kg is outside the accepted range")
        input.weight = ""
        XCTAssertEqual(input.weightKg, .blank)
        XCTAssertFalse(input.isBlank)
    }

    func testFillsAndConvertsFields() {
        let filled = BodyInput(units: .imperial, heightCm: 163.8, weightKg: 51.03)
        XCTAssertEqual(filled.feet, "5")
        XCTAssertEqual(filled.height, "4.5")
        XCTAssertEqual(filled.weight, "112.5")

        let metric = filled.converted(to: .metric)
        XCTAssertEqual(metric.feet, "")
        XCTAssertEqual(metric.height, "163.8")
        XCTAssertEqual(metric.weight, "51.03")

        var broken = filled
        broken.weight = "heavy"
        XCTAssertEqual(broken.converted(to: .metric).weight, "", "a field that isn't a number is cleared")
    }

    /// Opening and saving an entry doesn't nudge its values through a unit conversion.
    func testUntouchedFieldsKeepStoredValues() {
        let entry = BodyMeasurement(date: Fixtures.day(0), heightCm: 162.7, weightKg: 50.83)
        let untouched = BodyInput(units: .imperial, heightCm: entry.heightCm, weightKg: entry.weightKg)
        XCTAssertEqual(untouched.applied(to: entry), entry)

        var edited = untouched
        edited.weight = "115"
        let saved = edited.applied(to: entry)
        XCTAssertEqual(saved.heightCm, 162.7)
        XCTAssertEqual(saved.weightKg, 52.16)

        edited.feet = ""
        edited.height = ""
        XCTAssertNil(edited.applied(to: entry).heightCm, "clearing a field removes the value")
    }
}

final class BodyTrendsTests: XCTestCase {
    private func entry(_ day: Int, height: Double? = nil, weight: Double? = nil) -> BodyMeasurement {
        BodyMeasurement(date: Fixtures.day(day), heightCm: height, weightKg: weight)
    }

    func testLatestValuesSkipMissingOnes() {
        let entries = [entry(10, height: 160, weight: 48), entry(0, height: 159, weight: 47), entry(20, weight: 49)]
        XCTAssertEqual(BodyTrends.heights(entries).map(\.value), [159, 160])
        XCTAssertEqual(BodyTrends.weights(entries).map(\.value), [47, 48, 49])
        XCTAssertEqual(BodyTrends.summary(entries, units: .metric), "160 cm · 49 kg")
        XCTAssertNil(BodyTrends.summary([], units: .metric))
        XCTAssertEqual(BodyTrends.summary([entry(0, weight: 50.8)], units: .imperial), "112 lb")
    }

    func testChangeSince() {
        let points = BodyTrends.weights([entry(0, weight: 47), entry(30, weight: 48), entry(60, weight: 48.5)])
        XCTAssertEqual(try XCTUnwrap(BodyTrends.change(points)), 1.5, accuracy: 1e-9)
        let recent = BodyTrends.points(points, since: Fixtures.day(30))
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(try XCTUnwrap(BodyTrends.change(recent)), 0.5, accuracy: 1e-9)
        XCTAssertNil(BodyTrends.change(Array(points.prefix(1))))
        XCTAssertEqual(BodyTrends.points(points, since: nil).count, 3)
    }

    func testGrowthRateUsesAtLeastThreeMonths() throws {
        // Measured 60 days apart: too close together for a rate.
        XCTAssertNil(BodyTrends.growthRate([entry(0, height: 150), entry(60, height: 151)]))

        // The latest height against the most recent one at least 90 days earlier (day 100, not day 0).
        let entries = [entry(0, height: 150), entry(100, height: 152), entry(150, height: 153), entry(190, height: 154.5), entry(195, weight: 45)]
        let rate = try XCTUnwrap(BodyTrends.growthRate(entries))
        XCTAssertEqual(rate.from, Fixtures.day(100))
        XCTAssertEqual(rate.to, Fixtures.day(190))
        XCTAssertEqual(rate.gainedCm, 2.5, accuracy: 1e-9)
        XCTAssertEqual(rate.cmPerYear, 2.5 / (90 / 365.25), accuracy: 1e-9)
        XCTAssertTrue(rate.isSpurtPace)

        let steady = try XCTUnwrap(BodyTrends.growthRate([entry(0, height: 150), entry(182, height: 152.5)]))
        XCTAssertEqual(steady.cmPerYear, 2.5 / (182 / 365.25), accuracy: 1e-9)
        XCTAssertFalse(steady.isSpurtPace)
    }

    func testReadsProfilesSavedBeforeHeightAndWeight() throws {
        let json = """
        {"firstName": "Sam", "classYear": 2031, "positions": "Attack", "benchmarkGroup": "u15Women",
         "mentalCoachName": "", "weeklyGoalHours": 10, "season": "2026/27"}
        """
        let profile = try AppData.decoder.decode(AthleteProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.bodyUnits, .imperial)
        XCTAssertEqual(profile.weeklyGoalHours, 10)

        var metric = profile
        metric.bodyUnits = .metric
        XCTAssertEqual(try AppData.decoder.decode(AthleteProfile.self, from: AppData.encoder.encode(metric)), metric)
    }
}
