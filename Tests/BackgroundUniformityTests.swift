import XCTest
@testable import PassCheck

/// QA-002 on 2026-08-23 found the one failure that costs a user a rejected passport
/// application: a photo with a coat hanging behind the head, and a bed rail in frame, came
/// back as a *verified pass*.
///
/// A first fix caught that particular coat and was then reviewed adversarially, which found
/// it caught little else — a beige door filling 40% of the wall still passed, and colour was
/// left on a plain mean with the identical averaging flaw. These tests pin the cases that
/// review produced, each one an input that used to pass and must not.
///
/// Everything runs on synthetic sample sets, so the decision that actually rejects a photo is
/// testable on a machine with no camera.
final class BackgroundUniformityTests: XCTestCase {

    private let wall = BackgroundAnalyzer.Sample(r: 0.86, g: 0.85, b: 0.84)

    /// `fraction` of the samples are the object, the rest are the wall.
    private func background(object: BackgroundAnalyzer.Sample,
                            covering fraction: Double,
                            wall: BackgroundAnalyzer.Sample? = nil,
                            count: Int = 1000) -> [BackgroundAnalyzer.Sample] {
        let objectCount = Int((Double(count) * fraction).rounded())
        return Array(repeating: object, count: objectCount)
             + Array(repeating: wall ?? self.wall, count: count - objectCount)
    }

    /// An evenly lit wall, or an unevenly lit one: luminance ramps across `range`.
    private func gradient(center: Double, range: Double,
                          count: Int = 1000) -> [BackgroundAnalyzer.Sample] {
        (0..<count).map { i in
            let v = center + (Double(i) / Double(count - 1) - 0.5) * range
            return BackgroundAnalyzer.Sample(r: v, g: v, b: v * 0.99)
        }
    }

    private func verdict(_ samples: [BackgroundAnalyzer.Sample]) -> BackgroundAnalyzer.Result {
        BackgroundAnalyzer.verdict(for: BackgroundAnalyzer.stats(samples: samples))
    }

    // MARK: - Backgrounds that used to pass and must not

    /// The original QA-002 photo: a dark coat hanging behind the head.
    func testHangingCoatIsRejected() {
        let s = BackgroundAnalyzer.stats(samples: background(
            object: .init(r: 0.10, g: 0.10, b: 0.11), covering: 0.06))

        XCTAssertLessThanOrEqual(s.stdDev, PassportRules.bgUniformityMax,
                                 "The coat stays inside the spread threshold — that was the bug.")
        let result = BackgroundAnalyzer.verdict(for: s)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("isn't plain"), "Got: \(result.message)")
    }

    /// The same coat, mostly hidden behind the head so only a sliver shows. The first fix
    /// used a 4% budget and let this through; the coverage a partly occluded object produces
    /// is exactly the range that matters.
    func testCoatSliverIsRejected() {
        let result = verdict(background(object: .init(r: 0.10, g: 0.10, b: 0.11),
                                        covering: 0.025))
        XCTAssertFalse(result.ok, "A 2.5% sliver of a black coat must not pass.")
    }

    /// A beige door, a cream curtain, a light wooden rail: far enough from the wall to be
    /// obvious to a human, close enough that a fixed deviation band missed it at *any* size.
    func testMidToneObjectIsRejectedEvenThoughItIsCloseToTheWall() {
        let s = BackgroundAnalyzer.stats(samples: background(
            object: .init(r: 0.66, g: 0.64, b: 0.60), covering: 0.40))

        XCTAssertLessThanOrEqual(s.stdDev, PassportRules.bgUniformityMax,
                                 "Spread cannot see this: two populations 0.23 apart never reach 0.20.")
        XCTAssertGreaterThan(s.luminance, PassportRules.bgLuminanceMin,
                             "Nor is it dark enough to fail on brightness.")
        XCTAssertFalse(BackgroundAnalyzer.verdict(for: s).ok,
                       "A door covering 40% of the wall must not pass.")
    }

    /// Colour had the same averaging flaw as spread, and the first fix left it there: a pink
    /// curtain over 30% of the background averages down to a mean saturation well under the
    /// threshold. Deviation is measured per channel now, so it no longer hides.
    func testColouredObjectIsRejectedDespiteAcceptableMeanSaturation() {
        let s = BackgroundAnalyzer.stats(samples: background(
            object: .init(r: 0.95, g: 0.65, b: 0.65), covering: 0.30))

        XCTAssertLessThanOrEqual(s.saturation, PassportRules.bgSaturationMax,
                                 "The mean says this background is white enough. It is 30% pink.")
        XCTAssertFalse(BackgroundAnalyzer.verdict(for: s).ok)
    }

    /// A wardrobe or an open doorway filling half the frame. With an interpolated median the
    /// anchor lands in the empty space between the two populations and neither is an outlier.
    func testBackgroundSplitInHalfIsRejected() {
        let result = verdict(background(object: .init(r: 0.53, g: 0.52, b: 0.51),
                                        covering: 0.50,
                                        wall: BackgroundAnalyzer.Sample(r: 0.91, g: 0.90, b: 0.89)))
        XCTAssertFalse(result.ok, "Half wall, half object must not read as plain.")
    }

    /// A shadow the subject casts on the wall beside their own head.
    func testCastShadowIsRejected() {
        let result = verdict(background(object: .init(r: 0.46, g: 0.45, b: 0.44),
                                        covering: 0.12))
        XCTAssertFalse(result.ok)
    }

    // MARK: - Backgrounds that must still pass

    func testPlainWallPasses() {
        let result = verdict(Array(repeating: wall, count: 1000))
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.message, "Background looks plain and light.")
    }

    /// Ordinary indoor light falls off across a wall. Because the band scales with how
    /// varied the wall already is, a smooth ramp does not read as an object.
    func testEvenlyRampedLightingPasses() {
        let result = verdict(gradient(center: 0.82, range: 0.52))
        XCTAssertTrue(result.ok, "A lit-from-one-side wall must not be called cluttered. Got: \(result.message)")
    }

    /// A light switch or socket is small. It must not condemn the photo.
    func testSmallFixtureOnTheWallPasses() {
        let result = verdict(background(object: .init(r: 0.55, g: 0.55, b: 0.55),
                                        covering: 0.01))
        XCTAssertTrue(result.ok, "Got: \(result.message)")
    }

    // MARK: - The message the user reads

    /// The uneven-lighting sentence must be reachable. In the first fix it was not: the
    /// outlier margin outranked it in every case that could occur, so one unreachable
    /// message had simply replaced another.
    func testWideUnevenLightingReportsLightingNotClutter() {
        let result = verdict(gradient(center: 0.70, range: 0.80))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("Lighting"), "Got: \(result.message)")
    }

    func testUniformlyDarkWallStillReportsDarkness() {
        let result = verdict(Array(repeating: .init(r: 0.41, g: 0.40, b: 0.39), count: 1000))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("too dark"), "Got: \(result.message)")
    }

    func testColouredWallStillReportsColour() {
        let result = verdict(Array(repeating: .init(r: 0.86, g: 0.55, b: 0.52), count: 1000))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("too much color"), "Got: \(result.message)")
    }

    // MARK: - How much authority each finding gets

    /// A real device on 2026-08-23 was told, correctly, that a shadow was on the wall — and
    /// then could not continue, because a verified failure disables the export button. Being
    /// right is not the same as being certain enough to stop someone, and this measurement is
    /// the least certain of the four: it leans on a person mask, on a threshold not yet
    /// calibrated against real photographs, and it cannot tell an object from a shadow.
    func testNotPlainAdvisesRatherThanBlocks() {
        let cluttered = verdict(background(object: .init(r: 0.10, g: 0.10, b: 0.11),
                                           covering: 0.06))

        XCTAssertFalse(cluttered.ok, "The finding itself does not soften.")
        XCTAssertEqual(cluttered.reason, .notPlain)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: cluttered.reason), .confirm)
        XCTAssertNotEqual(VisionComplianceEngine.backgroundStatus(for: cluttered.reason),
                          .verifiedFail,
                          "A verified failure disables the export button — this must not.")
    }

    /// Brightness and colour keep their authority. They are means over the whole background
    /// and they behave predictably, so a wall that is genuinely too dark still stops the flow.
    func testBrightnessAndColourStillBlock() {
        let dark = verdict(Array(repeating: .init(r: 0.41, g: 0.40, b: 0.39), count: 1000))
        XCTAssertEqual(dark.reason, .tooDark)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: dark.reason), .verifiedFail)

        let coloured = verdict(Array(repeating: .init(r: 0.86, g: 0.55, b: 0.52), count: 1000))
        XCTAssertEqual(coloured.reason, .tooColoured)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: coloured.reason), .verifiedFail)
    }

    /// A plain wall passes outright, and an unmeasurable one asks rather than either passing
    /// or blocking.
    func testPlainPassesAndUnmeasurableAsks() {
        let plain = verdict(Array(repeating: wall, count: 1000))
        XCTAssertEqual(plain.reason, .plain)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: plain.reason), .verifiedPass)

        let unknown = verdict([])
        XCTAssertEqual(unknown.reason, .couldNotMeasure)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: unknown.reason), .confirm)
    }

    // MARK: - The statistic itself

    /// The one design decision the implementation comment singles out. A large object drags
    /// the mean towards itself until the wall is as far from the mean as the object is — and
    /// because the band is scaled from the *median deviation*, a mean anchor also widens its
    /// own threshold to swallow both. Anchoring on the median keeps the wall as the reference.
    ///
    /// CI caught an earlier version of this test comparing mean-anchored deviations against
    /// the *median-anchored* threshold, which is not a comparison of anchors at all. The whole
    /// algorithm is re-run below with the mean substituted for the median, threshold included.
    func testMedianAnchorSurvivesAnObjectLargeEnoughToMoveTheMean() {
        let samples = background(object: .init(r: 0.51, g: 0.50, b: 0.49),
                                 covering: 0.45,
                                 wall: BackgroundAnalyzer.Sample(r: 0.91, g: 0.90, b: 0.89))
        let stats = BackgroundAnalyzer.stats(samples: samples)

        let n = Double(samples.count)
        let meanL = samples.reduce(0.0) { $0 + $1.luminance } / n
        let meanR = samples.reduce(0.0) { $0 + $1.r } / n
        let meanG = samples.reduce(0.0) { $0 + $1.g } / n
        let meanB = samples.reduce(0.0) { $0 + $1.b } / n
        let meanDeviations = samples.map { sample in
            max(abs(sample.luminance - meanL),
                abs(sample.r - meanR), abs(sample.g - meanG), abs(sample.b - meanB))
        }
        let meanThreshold = max(
            PassportRules.bgOutlierScale * BackgroundAnalyzer.lowerMedian(meanDeviations),
            PassportRules.bgOutlierFloor)
        let meanAnchoredOutliers = meanDeviations.filter { $0 > meanThreshold }.count

        XCTAssertEqual(meanAnchoredOutliers, 0,
                       "Anchored on the mean, every sample sits a similar distance from it, the "
                       + "band widens to match, and a background that is 45% wardrobe looks plain.")
        XCTAssertGreaterThan(stats.outlierFraction, 0.4,
                             "Anchored on the median, the wall stays the reference and the object shows.")
        XCTAssertFalse(BackgroundAnalyzer.verdict(for: stats).ok)
    }

    /// For an even count the lower median must be a value that occurs in the image, not the
    /// midpoint between the two central ones.
    func testLowerMedianReturnsAnObservedValue() {
        XCTAssertEqual(BackgroundAnalyzer.lowerMedian([0.2, 0.4, 0.6, 0.8]), 0.4, accuracy: 1e-12)
        XCTAssertEqual(BackgroundAnalyzer.lowerMedian([0.5, 0.1, 0.9]), 0.5, accuracy: 1e-12)
    }

    /// A degenerate sample set makes every statistic NaN, and every comparison against NaN is
    /// false — which would filter out all four failure checks and read as a plain background.
    func testDegenerateSamplesNeverReadAsPlain() {
        let result = BackgroundAnalyzer.verdict(for: BackgroundAnalyzer.stats(samples: []))
        XCTAssertFalse(result.ok)
        XCTAssertNil(result.luminance, "A nil measurement is what tells the caller it is unknown.")
    }

    /// The sample-count floor and the outlier budget have to agree: a 2% budget over 20
    /// samples tolerates no outlier at all, which would make a single mask-edge pixel fatal.
    func testSampleFloorIsLargeEnoughForTheOutlierBudgetToMeanAnything() {
        XCTAssertGreaterThanOrEqual(
            Double(PassportRules.bgMinBackgroundSamples) * PassportRules.bgOutlierFractionMax, 1.0,
            "Below one whole sample, the budget is a coin flip rather than a tolerance.")
    }
}
