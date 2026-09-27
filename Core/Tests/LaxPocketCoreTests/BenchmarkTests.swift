import XCTest
@testable import LaxPocketCore

final class BenchmarkTests: XCTestCase {
    func testHigherIsBetterTiersU15Women() {
        XCTAssertEqual(NDTPStandards.tier(for: 250, metric: .gripLeft, group: .u15Women), .developing)
        XCTAssertEqual(NDTPStandards.tier(for: 280, metric: .gripLeft, group: .u15Women), .competitive)
        XCTAssertEqual(NDTPStandards.tier(for: 300, metric: .gripRight, group: .u15Women), .competitive)
        XCTAssertEqual(NDTPStandards.tier(for: 307, metric: .gripRight, group: .u15Women), .elite)
        XCTAssertEqual(NDTPStandards.tier(for: 10.7, metric: .squatJump, group: .u15Women), .elite, "The cut-off itself is Elite (10.7″+)")
        XCTAssertEqual(NDTPStandards.tier(for: 11.9, metric: .countermovementJump, group: .u15Women), .elite)
        XCTAssertEqual(NDTPStandards.tier(for: 9.9, metric: .countermovementJump, group: .u15Women), .developing)
    }

    func testLowerIsBetterTiersU15Women() {
        XCTAssertEqual(NDTPStandards.tier(for: 1.91, metric: .sprint10m, group: .u15Women), .elite)
        XCTAssertEqual(NDTPStandards.tier(for: 1.92, metric: .sprint10m, group: .u15Women), .competitive, "Elite is strictly under 1.92 s")
        XCTAssertEqual(NDTPStandards.tier(for: 2.00, metric: .sprint10m, group: .u15Women), .competitive)
        XCTAssertEqual(NDTPStandards.tier(for: 2.01, metric: .sprint10m, group: .u15Women), .developing)
        XCTAssertEqual(NDTPStandards.tier(for: 4.91, metric: .proAgilityRight, group: .u15Women), .elite)
        XCTAssertEqual(NDTPStandards.tier(for: 5.11, metric: .proAgilityLeft, group: .u15Women), .developing)
    }

    func testWomenHaveNo20mStandard() {
        XCTAssertNil(NDTPStandards.thresholds(for: .sprint20m, in: .u15Women))
        XCTAssertNil(NDTPStandards.tier(for: 3.3, metric: .sprint20m, group: .u17Women))
        XCTAssertNotNil(NDTPStandards.thresholds(for: .sprint20m, in: .u15Men))
    }

    func testEveryGroupCoversTheCoreBattery() {
        let core: [CombineMetric] = [.gripLeft, .squatJump, .countermovementJump, .sprint10m, .proAgilityLeft]
        for group in BenchmarkGroup.allCases {
            for metric in core {
                XCTAssertNotNil(NDTPStandards.thresholds(for: metric, in: group), "\(group) missing \(metric)")
            }
        }
    }

    func testThresholdsAreOrderedSensibly() {
        for group in BenchmarkGroup.allCases {
            for metric in CombineMetric.allCases {
                guard let t = NDTPStandards.thresholds(for: metric, in: group) else { continue }
                if metric.lowerIsBetter {
                    XCTAssertLessThan(t.elite, t.competitive, "\(group) \(metric)")
                } else {
                    XCTAssertGreaterThan(t.elite, t.competitive, "\(group) \(metric)")
                }
            }
        }
    }

    func testGapToNextTier() throws {
        let dev = try XCTUnwrap(NDTPStandards.assess(268, metric: .gripLeft, group: .u15Women))
        XCTAssertEqual(dev.tier, .developing)
        XCTAssertEqual(dev.nextTier, .competitive)
        XCTAssertEqual(try XCTUnwrap(dev.gapToNextTier), 12, accuracy: 1e-9)

        let comp = try XCTUnwrap(NDTPStandards.assess(1.95, metric: .sprint10m, group: .u15Women))
        XCTAssertEqual(comp.tier, .competitive)
        XCTAssertEqual(try XCTUnwrap(comp.gapToNextTier), 0.03, accuracy: 1e-9)

        let elite = try XCTUnwrap(NDTPStandards.assess(12.3, metric: .countermovementJump, group: .u15Women))
        XCTAssertEqual(elite.tier, .elite)
        XCTAssertNil(elite.nextTier)
        XCTAssertEqual(try XCTUnwrap(elite.marginPastElite), 0.4, accuracy: 1e-9)
    }

    func testGapDescriptions() {
        XCTAssertEqual(NDTPStandards.gapDescription(292, metric: .gripRight, group: .u15Women), "15 N to Elite (307 N+)")
        XCTAssertEqual(NDTPStandards.gapDescription(268, metric: .gripLeft, group: .u15Women), "12 N to Competitive (280 N+)")
        XCTAssertEqual(NDTPStandards.gapDescription(10.7, metric: .squatJump, group: .u15Women), "Right on the Elite line (10.7″)")
        XCTAssertEqual(NDTPStandards.gapDescription(1.95, metric: .sprint10m, group: .u15Women), "0.030 s off Elite (under 1.92 s)")
        XCTAssertEqual(NDTPStandards.gapDescription(4.90, metric: .proAgilityLeft, group: .u15Women), "0.02 s under the Elite line (4.92 s)")
        XCTAssertEqual(NDTPStandards.gapDescription(5.20, metric: .proAgilityLeft, group: .u15Women), "0.10 s off Competitive (5.10 s)")
    }

    func testTierCountsAndNextGroup() {
        let result = CombineResult(date: Date(), event: "Test", measurements: [
            .init(metric: .gripLeft, value: 250),     // developing
            .init(metric: .gripRight, value: 290),    // competitive
            .init(metric: .squatJump, value: 11.0),   // elite
            .init(metric: .sprint20m, value: 3.2)     // no women's standard — ignored
        ])
        let counts = result.tierCounts(in: .u15Women)
        XCTAssertEqual(counts[.developing], 1)
        XCTAssertEqual(counts[.competitive], 1)
        XCTAssertEqual(counts[.elite], 1)
        XCTAssertEqual(BenchmarkGroup.u15Women.next, .u17Women)
        XCTAssertNil(BenchmarkGroup.u19Women.next)
    }

    func testFormatting() {
        XCTAssertEqual(CombineMetric.squatJump.format(10.7), "10.7″")
        XCTAssertEqual(CombineMetric.gripLeft.format(268), "268 N")
        XCTAssertEqual(CombineMetric.sprint10m.format(1.927), "1.927 s")
        XCTAssertEqual(CombineMetric.sprint10m.formatThreshold(1.92), "1.92 s")
    }
}
