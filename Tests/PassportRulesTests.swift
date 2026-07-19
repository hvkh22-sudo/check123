import XCTest
@testable import PassCheck

// First tests — give CI something real to run (B0). Grows into the engine test suite (backlog B2.9).
final class PassportRulesTests: XCTestCase {

    func testHeadHeightBandIsValid() {
        XCTAssertLessThan(PassportRules.headHeightMinPct, PassportRules.headHeightMaxPct)
    }

    func testPixelBounds() {
        XCTAssertLessThan(PassportRules.pixelMin, PassportRules.pixelMax)
    }

    func testHeadHeightInBand() {
        XCTAssertTrue(PassportRules.headHeightInBand(61.5))
        XCTAssertFalse(PassportRules.headHeightInBand(42.0))
        XCTAssertFalse(PassportRules.headHeightInBand(75.0))
    }

    func testEmptyReportPasses() {
        let report = ComplianceReport(results: [], engineVersion: "0.1")
        XCTAssertEqual(report.overall, .pass)
    }

    func testVerifiedFailMakesReportFail() {
        let r = RuleResult(id: "bg.white", status: .verifiedFail, measured: nil, unit: nil,
                           message: "Background too dark")
        let report = ComplianceReport(results: [r], engineVersion: "0.1")
        XCTAssertEqual(report.overall, .fail)
    }

    func testAssistedMakesNeedsAttention() {
        let r = RuleResult(id: "head.height", status: .assisted, measured: 61.5, unit: "%",
                           message: "Aligned with your guides")
        let report = ComplianceReport(results: [r], engineVersion: "0.1")
        XCTAssertEqual(report.overall, .needsAttention)
    }
}
