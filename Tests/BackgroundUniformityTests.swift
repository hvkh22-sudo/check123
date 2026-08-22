import XCTest
@testable import PassCheck

/// QA-002 on 2026-08-23 found the one failure that costs a user a rejected passport
/// application: a photo with a coat hanging behind the head, and a bed rail, was returned as
/// a *verified pass*. These pin the statistic that let it through, and the statistic that
/// catches it now.
///
/// Everything here runs on synthetic sample arrays rather than photos, so the decision that
/// actually rejects a photo is testable on a machine with no camera.
final class BackgroundUniformityTests: XCTestCase {

    /// Builds a background sample set: `fraction` of the samples at `luminance`, the rest
    /// at `wall`.
    private func samples(wall: Double,
                         object luminance: Double,
                         covering fraction: Double,
                         count: Int = 1000) -> [Double] {
        let objectCount = Int((Double(count) * fraction).rounded())
        return Array(repeating: luminance, count: objectCount)
             + Array(repeating: wall, count: count - objectCount)
    }

    private func stats(_ lums: [Double], saturation: Double = 0.05) -> BackgroundAnalyzer.Stats {
        BackgroundAnalyzer.stats(luminances: lums, meanSaturation: saturation)
    }

    // MARK: - The regression

    /// The exact shape of the QA-002 failure: a dark coat against a light wall, covering a
    /// realistic share of the visible background.
    func testHangingCoatIsRejected() {
        let s = stats(samples(wall: 0.85, object: 0.10, covering: 0.06))
        let result = BackgroundAnalyzer.verdict(for: s)

        XCTAssertFalse(result.ok, "A coat covering 6% of the background must not pass.")
        XCTAssertTrue(result.message.contains("behind you"),
                      "Got: \(result.message)")
    }

    /// Why it passed before: standard deviation averages a localised object into the wall
    /// around it. This asserts the old statistic on the same samples, so the regression can
    /// never be reintroduced by "simplifying" back to a single spread measure.
    func testStandardDeviationAloneWouldHavePassedTheCoat() {
        let s = stats(samples(wall: 0.85, object: 0.10, covering: 0.06))

        XCTAssertLessThanOrEqual(s.stdDev, PassportRules.bgUniformityMax,
                                 "The coat stays inside the spread threshold — that was the bug.")
        XCTAssertGreaterThan(s.outlierFraction, PassportRules.bgOutlierFractionMax,
                             "The outlier share is what has to catch it instead.")
    }

    /// The worst case of the old statistic: anything at 0.50 luminance or lighter could not
    /// trip the spread threshold at *any* coverage, so a pale object was invisible to it.
    func testMidToneObjectIsCaughtEvenAtLargeCoverage() {
        let s = stats(samples(wall: 0.85, object: 0.55, covering: 0.20))

        XCTAssertLessThanOrEqual(s.stdDev, PassportRules.bgUniformityMax,
                                 "Spread alone never sees this one, at any size.")
        XCTAssertFalse(BackgroundAnalyzer.verdict(for: s).ok)
    }

    // MARK: - What must still pass

    func testPlainWallPasses() {
        let result = BackgroundAnalyzer.verdict(for: stats(Array(repeating: 0.85, count: 1000)))
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.message, "Background looks plain and light.")
    }

    /// Grout lines and wall texture sit close to the wall's own luminance. They must stay
    /// inside the outlier band — the spread threshold was loosened for exactly these, and
    /// the new check must not undo that.
    func testTexturedWallWithGroutLinesStillPasses() {
        let s = stats(samples(wall: 0.85, object: 0.65, covering: 0.10))
        XCTAssertLessThanOrEqual(s.outlierFraction, PassportRules.bgOutlierFractionMax)
        XCTAssertTrue(BackgroundAnalyzer.verdict(for: s).ok)
    }

    /// A background can be empty and still be too dark. That verdict must survive.
    func testUniformlyDarkWallStillReportsDarkness() {
        let result = BackgroundAnalyzer.verdict(for: stats(Array(repeating: 0.40, count: 1000)))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("too dark"), "Got: \(result.message)")
    }

    func testColouredWallStillReportsColour() {
        let s = stats(Array(repeating: 0.80, count: 1000), saturation: 0.45)
        let result = BackgroundAnalyzer.verdict(for: s)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("too much color"), "Got: \(result.message)")
    }

    /// A strong lighting gradient is a global problem, not an object. It must still fail;
    /// which of the two "not plain" sentences it earns is not pinned, because the samples
    /// carry no position and a gradient cannot be told from a large object without one.
    func testStrongGradientStillFails() {
        let gradient = (0..<1000).map { 0.20 + (Double($0) / 999.0) * 0.80 }
        XCTAssertFalse(BackgroundAnalyzer.verdict(for: stats(gradient)).ok)
    }

    // MARK: - The message the user reads

    /// QA-B1: "too dark" was checked first and therefore masked every other reason, so the
    /// sentence about objects behind you was unreachable whenever brightness also failed.
    /// A dim *and* cluttered background must now name the clutter, which is the thing the
    /// user can actually act on.
    func testClutterOutranksDarknessWhenBothFail() {
        let s = stats(samples(wall: 0.70, object: 0.05, covering: 0.15))
        let result = BackgroundAnalyzer.verdict(for: s)

        XCTAssertLessThan(s.luminance, PassportRules.bgLuminanceMin,
                          "This background is genuinely dim as well — that is the point.")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("behind you"),
                      "Darkness masked the actionable reason. Got: \(result.message)")
    }

    /// A degenerate sample set makes every statistic NaN, and every comparison against NaN
    /// is false — which would have filtered out all four failure checks and returned a
    /// silent pass. It must fail closed instead.
    func testDegenerateSamplesFailClosed() {
        let result = BackgroundAnalyzer.verdict(for: stats([]))
        XCTAssertFalse(result.ok, "NaN statistics must never read as a plain background.")
        XCTAssertNil(result.luminance)
    }

    /// The median, not the mean, anchors the outlier test: an object large enough to drag
    /// the mean toward itself would otherwise start hiding behind its own influence.
    func testMedianAnchorsTheOutlierTest() {
        let s = stats(samples(wall: 0.90, object: 0.10, covering: 0.30))
        XCTAssertGreaterThan(s.outlierFraction, 0.25,
                             "A large object must still register as outliers, not move the anchor.")
    }
}
