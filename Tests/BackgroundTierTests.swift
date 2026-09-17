import XCTest
@testable import PassCheck

/// On 2026-09-14 a device ran the fixed background check against the original QA-002 scene —
/// a hanging coat and a bed rail — and the check *found* it: "Background isn't plain". The
/// finding was then graded as advice, filed under "double-check", and the screen said
/// "Passed every automatic check" and sold the export. Being right was not enough.
///
/// The advisory grade exists for a reason that is still true: the statistic cannot tell a
/// soft shadow from a light switch, and a false lock traps a user in an ordinary room. These
/// tests pin the missing tier — when the share of foreign samples is large there is no
/// shadow story left, and the finding is a verified failure that closes the export.
final class BackgroundTierTests: XCTestCase {

    private let wall = BackgroundAnalyzer.Sample(r: 0.86, g: 0.85, b: 0.84)

    private func background(object: BackgroundAnalyzer.Sample,
                            covering fraction: Double,
                            count: Int = 1000) -> [BackgroundAnalyzer.Sample] {
        let objectCount = Int((Double(count) * fraction).rounded())
        return Array(repeating: object, count: objectCount)
             + Array(repeating: wall, count: count - objectCount)
    }

    private func result(_ samples: [BackgroundAnalyzer.Sample]) -> BackgroundAnalyzer.Result {
        BackgroundAnalyzer.verdict(for: BackgroundAnalyzer.stats(samples: samples))
    }

    private func notPlain(share: Double?) -> BackgroundAnalyzer.Result {
        BackgroundAnalyzer.Result(ok: false, message: "Background isn't plain — something is behind you, or a shadow is on the wall.",
                                  luminance: 0.74, reason: .notPlain, outlierFraction: share)
    }

    // MARK: - The tier

    /// The scene from the owner's photographs: a coat and a bed rail over a large part of
    /// the background. Must block, not advise.
    func testCoatAndRailBlockTheExport() {
        let r = result(background(object: .init(r: 0.10, g: 0.10, b: 0.11), covering: 0.30))
        XCTAssertEqual(r.reason, .notPlain)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: r), .verifiedFail,
                       "30% of the wall is a coat. That is not a shadow.")
    }

    /// A light switch, or a soft shadow: a small share stays advice, exactly as before.
    func testSmallShareStaysAdvisory() {
        let r = result(background(object: .init(r: 0.10, g: 0.10, b: 0.11), covering: 0.05))
        XCTAssertEqual(r.reason, .notPlain)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: r), .confirm)
    }

    /// The boundary is the constant, inclusive, so the constant is the whole policy.
    func testHardThresholdIsInclusive() {
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(
            for: notPlain(share: PassportRules.bgOutlierFractionHard)), .verifiedFail)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(
            for: notPlain(share: PassportRules.bgOutlierFractionHard - 0.001)), .confirm)
    }

    /// The hard tier is also inside the range the advisory budget already flags — it is a
    /// second line above the first, never a hole between them.
    func testHardTierSitsAboveAdvisoryBudget() {
        XCTAssertGreaterThan(PassportRules.bgOutlierFractionHard, PassportRules.bgOutlierFractionMax)
    }

    /// No share measured means no grounds to block. "Couldn't measure" must never harden
    /// into a failure by accident — that is a different bug in the other direction.
    func testMissingShareStaysAdvisory() {
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: notPlain(share: nil)), .confirm)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: notPlain(share: .nan)), .confirm)
    }

    /// The tier is about objects. Uneven lighting keeps its grade whatever the share says,
    /// and the two reasons that were always hard stay hard.
    func testTierAppliesToNotPlainOnly() {
        let uneven = BackgroundAnalyzer.Result(ok: false, message: "uneven", luminance: 0.7,
                                               reason: .unevenLighting, outlierFraction: 0.5)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: uneven), .confirm)
        let dark = BackgroundAnalyzer.Result(ok: false, message: "dark", luminance: 0.3,
                                             reason: .tooDark, outlierFraction: 0.0)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: dark), .verifiedFail)
        let plain = BackgroundAnalyzer.Result(ok: true, message: "plain", luminance: 0.8,
                                              reason: .plain, outlierFraction: 0.0)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: plain), .verifiedPass)
    }

    // MARK: - What the row shows

    /// The number under a "not plain" row is the share that decided it, not the wall's
    /// brightness. The screenshot said "74%" and the 74 was brightness.
    func testNotPlainRowShowsTheShare() {
        let m = VisionComplianceEngine.backgroundMeasure(for: notPlain(share: 0.31))
        XCTAssertEqual(m.value ?? -1, 31, accuracy: 0.001)
        XCTAssertEqual(m.unit, "% of background")
    }

    func testPlainRowStillShowsBrightness() {
        let plain = BackgroundAnalyzer.Result(ok: true, message: "plain", luminance: 0.74,
                                              reason: .plain, outlierFraction: 0.0)
        let m = VisionComplianceEngine.backgroundMeasure(for: plain)
        XCTAssertEqual(m.value ?? -1, 74, accuracy: 0.001)
        XCTAssertEqual(m.unit, "%")
    }

    /// The verdict carries the share it was made on, so the tier above can read it.
    func testVerdictCarriesTheOutlierShare() {
        let r = result(background(object: .init(r: 0.10, g: 0.10, b: 0.11), covering: 0.30))
        XCTAssertEqual(r.outlierFraction ?? -1, 0.30, accuracy: 0.005)
    }

    // MARK: - The report end to end

    /// A hard background finding closes the review screen's export path.
    func testHardBackgroundFindingBlocksTheReport() {
        let r = result(background(object: .init(r: 0.10, g: 0.10, b: 0.11), covering: 0.30))
        let measure = VisionComplianceEngine.backgroundMeasure(for: r)
        let report = ComplianceReport(results: [
            RuleResult(id: "head.tilt", status: .verifiedPass, measured: 0, unit: "°", message: "Head is straight."),
            RuleResult(id: "bg.plain", status: VisionComplianceEngine.backgroundStatus(for: r),
                       measured: measure.value, unit: measure.unit, message: r.message)
        ], engineVersion: "test", suggestedCrownY: nil, suggestedChinY: nil)
        XCTAssertEqual(report.reviewVerdict, .blocked(count: 1))
        XCTAssertEqual(report.overall, .fail)
    }
}
