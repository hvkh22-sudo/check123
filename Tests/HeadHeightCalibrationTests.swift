import XCTest
@testable import PassCheck

/// Pins the head-height calibration seam (spike R-A).
///
/// Vision's face bounding box stops near the hairline, so it under-measures the
/// chin-to-crown height the passport spec requires. `crownExtensionFactor` is the
/// correction, derived from labelled device photos. These tests fix the behaviour of
/// the conversion so that calibrating it later is a one-constant change with a
/// guaranteed effect, and so an accidental edit to the band is caught immediately.
final class HeadHeightCalibrationTests: XCTestCase {

    // MARK: Compliant band boundaries (50-69% of frame height)

    func testBandAcceptsItsEndpoints() {
        XCTAssertTrue(PassportRules.headHeightInBand(50.0))
        XCTAssertTrue(PassportRules.headHeightInBand(69.0))
        XCTAssertTrue(PassportRules.headHeightInBand(60.0))
    }

    func testBandRejectsJustOutside() {
        XCTAssertFalse(PassportRules.headHeightInBand(49.9))
        XCTAssertFalse(PassportRules.headHeightInBand(69.1))
    }

    func testBandRejectsDegenerateValues() {
        XCTAssertFalse(PassportRules.headHeightInBand(0))
        XCTAssertFalse(PassportRules.headHeightInBand(100))
        XCTAssertFalse(PassportRules.headHeightInBand(-10))
    }

    // MARK: Face box -> estimated chin-to-crown height

    func testUncalibratedFactorReportsVisionBoxUnchanged() {
        // Guards the honest default: until we have real photos we must not invent a
        // correction. If this fails, someone set a factor — update isHeadHeightCalibrated
        // expectations and the assisted-status handling in VisionComplianceEngine too.
        XCTAssertEqual(PassportRules.crownExtensionFactor, 1.0, accuracy: 0.0001)
        XCTAssertFalse(PassportRules.isHeadHeightCalibrated)
        XCTAssertEqual(
            PassportRules.estimatedHeadHeightPct(faceBoxHeightFraction: 0.55),
            55.0, accuracy: 0.0001)
    }

    func testEstimateIsMonotonicInFaceBoxHeight() {
        let small = PassportRules.estimatedHeadHeightPct(faceBoxHeightFraction: 0.30)
        let medium = PassportRules.estimatedHeadHeightPct(faceBoxHeightFraction: 0.55)
        let large = PassportRules.estimatedHeadHeightPct(faceBoxHeightFraction: 0.80)
        XCTAssertLessThan(small, medium)
        XCTAssertLessThan(medium, large)
    }

    func testEstimateIsClampedToAPercentage() {
        XCTAssertEqual(PassportRules.estimatedHeadHeightPct(faceBoxHeightFraction: 0), 0)
        XCTAssertEqual(PassportRules.estimatedHeadHeightPct(faceBoxHeightFraction: 1.5), 100)
        XCTAssertEqual(PassportRules.estimatedHeadHeightPct(faceBoxHeightFraction: -0.2), 0)
    }

    /// The whole point of the seam: a face box that reads as too small today must be
    /// able to land inside the band once the factor reflects reality. This documents the
    /// arithmetic the calibration will rely on, without asserting any particular factor.
    func testCalibrationCanMoveAnUnderMeasuredFaceIntoTheBand() {
        let faceBox = 0.42                       // typical framing that reads low today
        let uncalibrated = faceBox * 1.0 * 100
        XCTAssertFalse(PassportRules.headHeightInBand(uncalibrated),
                       "0.42 must read as out-of-band before calibration")

        let calibrated = faceBox * 1.35 * 100    // illustrative factor, not a claim
        XCTAssertTrue(PassportRules.headHeightInBand(calibrated),
                      "a plausible correction must be able to bring it in-band")
    }
}
