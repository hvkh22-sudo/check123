import XCTest
import CoreGraphics
@testable import PassCheck

/// The background thresholds are uncalibrated, and whether the verdict should measure the
/// exported square rather than the whole frame is undecided. Pre-release builds show both
/// shares under the background row so one device session can answer both. These pin the
/// geometry of that second measurement and the read-out itself — and that neither touches
/// the verdict.
final class CalibrationReadoutTests: XCTestCase {

    // MARK: - Sampling grid

    func testFullFrameGridSpansTheFrame() {
        let first = BackgroundAnalyzer.samplePoint(ix: 0, iy: 0, steps: 40, in: BackgroundAnalyzer.fullFrame)
        let last = BackgroundAnalyzer.samplePoint(ix: 39, iy: 39, steps: 40, in: BackgroundAnalyzer.fullFrame)
        XCTAssertEqual(first.x, 0.0125, accuracy: 1e-9)
        XCTAssertEqual(first.y, 0.0125, accuracy: 1e-9)
        XCTAssertEqual(last.x, 0.9875, accuracy: 1e-9)
        XCTAssertEqual(last.y, 0.9875, accuracy: 1e-9)
    }

    /// A grid laid over a region never samples outside it.
    func testRegionGridStaysInsideTheRegion() {
        let region = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
        for (ix, iy) in [(0, 0), (39, 0), (0, 39), (39, 39), (20, 17)] {
            let p = BackgroundAnalyzer.samplePoint(ix: ix, iy: iy, steps: 40, in: region)
            XCTAssertGreaterThan(p.x, Double(region.minX))
            XCTAssertLessThan(p.x, Double(region.maxX))
            XCTAssertGreaterThan(p.y, Double(region.minY))
            XCTAssertLessThan(p.y, Double(region.maxY))
        }
    }

    // MARK: - The region is the square the export keeps

    func testRegionIsTheExportSquareInFractions() throws {
        let w: CGFloat = 576, h: CGFloat = 768
        let region = try XCTUnwrap(VisionComplianceEngine.backgroundRegion(
            crownY: 0.30, chinY: 0.55, centerX: 0.45, imageWidth: w, imageHeight: h))
        // Square in pixels, not in fractions.
        XCTAssertEqual(region.width * w, region.height * h, accuracy: 1.5)
        // It holds the head it was built around.
        XCTAssertLessThanOrEqual(region.minY, 0.30)
        XCTAssertGreaterThanOrEqual(region.maxY, 0.55)
        XCTAssertGreaterThanOrEqual(region.minX, 0)
        XCTAssertLessThanOrEqual(region.maxX, 1.0 + 1e-9)
    }

    func testCollapsedGuidesGiveNoRegion() {
        XCTAssertNil(VisionComplianceEngine.backgroundRegion(
            crownY: 0.40, chinY: 0.41, centerX: 0.5, imageWidth: 576, imageHeight: 768))
    }

    // MARK: - The read-out

    private func result(frame: Double?, crop: Double?) -> BackgroundAnalyzer.Result {
        var r = BackgroundAnalyzer.Result(ok: false, message: "Background isn't plain",
                                          luminance: 0.8, reason: .notPlain,
                                          outlierFraction: frame)
        r.regionOutlierFraction = crop
        return r
    }

    func testReadOutShowsBothShares() {
        XCTAssertEqual(VisionComplianceEngine.backgroundDiagnostic(for: result(frame: 0.042, crop: 0.187)),
                       "calibration · frame 4.2% · crop 18.7%")
    }

    func testReadOutWithoutARegionShowsTheFrameOnly() {
        XCTAssertEqual(VisionComplianceEngine.backgroundDiagnostic(for: result(frame: 0.042, crop: nil)),
                       "calibration · frame 4.2%")
    }

    func testNothingMeasuredMeansNoReadOut() {
        XCTAssertNil(VisionComplianceEngine.backgroundDiagnostic(for: result(frame: nil, crop: 0.2)))
        XCTAssertNil(VisionComplianceEngine.backgroundDiagnostic(for: result(frame: .nan, crop: 0.2)))
    }

    /// The regional share is calibration only. A huge crop share with a small frame share
    /// grades exactly as the frame share alone does.
    func testRegionalShareNeverChangesTheVerdict() {
        let small = result(frame: 0.03, crop: nil)
        let smallWithHugeCrop = result(frame: 0.03, crop: 0.60)
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: small),
                       VisionComplianceEngine.backgroundStatus(for: smallWithHugeCrop))
        XCTAssertEqual(VisionComplianceEngine.backgroundStatus(for: smallWithHugeCrop), .confirm)
    }
}
