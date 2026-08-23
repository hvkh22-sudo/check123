import XCTest
import CoreImage
@testable import PassCheck

/// The export pipeline is what the user pays for: without it the "export" is the untouched
/// camera photo. These tests assert the two properties the passport spec actually requires —
/// the output is square, and the head occupies the target share of it.
final class ExportPipelineTests: XCTestCase {

    /// A stand-in photo. Content is irrelevant; only geometry is under test.
    private func sourceImage(width: CGFloat, height: CGFloat) -> CIImage {
        CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func testOutputIsASquareOfTheSpecifiedSize() throws {
        let source = sourceImage(width: 3024, height: 4032)   // typical iPhone portrait
        let result = try XCTUnwrap(
            ExportPipeline.makePassportImage(from: source, crownY: 0.20, chinY: 0.55))

        XCTAssertEqual(result.extent.width, ExportPipeline.outputSize, accuracy: 1)
        XCTAssertEqual(result.extent.height, ExportPipeline.outputSize, accuracy: 1)
    }

    func testOutputSizeIsInsideTheAllowedPixelRange() throws {
        XCTAssertGreaterThanOrEqual(Int(ExportPipeline.outputSize), PassportRules.pixelMin)
        XCTAssertLessThanOrEqual(Int(ExportPipeline.outputSize), PassportRules.pixelMax)
    }

    func testHeadEndsUpAtTheTargetFractionOfTheFrame() throws {
        let height: CGFloat = 4000
        let source = sourceImage(width: 3000, height: height)
        let crownY: CGFloat = 0.25
        let chinY: CGFloat = 0.55

        let result = try XCTUnwrap(
            ExportPipeline.makePassportImage(from: source, crownY: crownY, chinY: chinY))

        // The crop side was chosen as headPixels / targetHeadFraction, then scaled to
        // outputSize — so in the output the head must span that same fraction.
        let headPixelsInSource = (chinY - crownY) * height
        let cropSide = headPixelsInSource / ExportPipeline.targetHeadFraction
        let headInOutput = headPixelsInSource * (ExportPipeline.outputSize / cropSide)
        let fraction = headInOutput / result.extent.height

        XCTAssertEqual(fraction, ExportPipeline.targetHeadFraction, accuracy: 0.01)
        XCTAssertTrue(PassportRules.headHeightInBand(Double(fraction) * 100),
                      "the framing target must land inside the compliant 50-69% band")
    }

    func testGuideOrderDoesNotMatter() throws {
        let source = sourceImage(width: 3000, height: 4000)
        let a = try XCTUnwrap(ExportPipeline.makePassportImage(from: source, crownY: 0.25, chinY: 0.55))
        let b = try XCTUnwrap(ExportPipeline.makePassportImage(from: source, crownY: 0.55, chinY: 0.25))
        XCTAssertEqual(a.extent, b.extent)
    }

    func testCropStaysInsideTheSourceEvenWhenTheHeadIsNearAnEdge() throws {
        let source = sourceImage(width: 2000, height: 2000)
        // Crown at the very top: naive maths would place the crop above the image.
        let result = try XCTUnwrap(
            ExportPipeline.makePassportImage(from: source, crownY: 0.0, chinY: 0.30))
        XCTAssertEqual(result.extent.width, ExportPipeline.outputSize, accuracy: 1)
        XCTAssertEqual(result.extent.height, ExportPipeline.outputSize, accuracy: 1)
    }

    /// This test used to assert the opposite, and in doing so pinned a defect in place.
    ///
    /// Guides on top of each other measure no head, and the pipeline answered with a centred
    /// square taken from the upper part of the frame — bearing no relation to where the head
    /// actually was — and returned it with no failure reason, so the export screen stamped it
    /// "Ready to export ✓ 1200 × 1200 px". "Never dead-end" is not a kindness when the way out
    /// is selling someone an arbitrary square as their passport photo.
    func testDegenerateGuidesAreRejectedRatherThanGuessedAt() {
        let source = sourceImage(width: 2000, height: 2000)
        let result = ExportPipeline.make(from: source, crownY: 0.4, chinY: 0.4)

        XCTAssertNil(result.image, "An unmeasurable head must not produce an export.")
        XCTAssertNotNil(result.reason, "And the screen must be able to say why.")
    }

    // MARK: - What the crop actually delivers

    /// The defect this file previously could not see. The crop side is clamped to the
    /// source's short edge when the ideal square does not fit, and nothing recomputed the
    /// head fraction that resulted — so a head-and-shoulders photo shipped at ~80% head
    /// height under a green seal, to be rejected for head size.
    ///
    /// 1800 × 2400 is the real worst case: every import is capped at 2400px on the long edge.
    func testHeadTooLargeForTheFrameIsRejectedRatherThanShippedOutOfBand() {
        let source = sourceImage(width: 1800, height: 2400)
        let result = ExportPipeline.make(from: source, crownY: 0.18, chinY: 0.78)

        XCTAssertNil(result.image, "80% head height is outside the 50–69% band and must not export.")
        XCTAssertEqual(result.reason?.contains("further") ?? false, true,
                       "The reason must tell the user what to do. Got: \(result.reason ?? "nil")")
    }

    /// The same clamp can push the square's bottom edge above the chin. A photo missing part
    /// of the chin is not a passport photo, however square it is.
    func testCropThatWouldCutTheChinIsRejected() {
        let source = sourceImage(width: 1800, height: 2400)
        XCTAssertNil(ExportPipeline.make(from: source, crownY: 0.05, chinY: 0.76).image)
    }

    /// The band's edge must still be usable — the fix must reject what is out of band, not
    /// everything the clamp touches. Here the clamp engages and the result lands at exactly
    /// the 69% limit.
    func testHeadAtTheTopOfTheBandStillExports() throws {
        let source = sourceImage(width: 1800, height: 2400)
        let result = try XCTUnwrap(
            ExportPipeline.makePassportImage(from: source, crownY: 0.20, chinY: 0.7175),
            "69% is inside the compliant band and must still be exportable")
        XCTAssertEqual(result.extent.width, ExportPipeline.outputSize, accuracy: 1)
    }

    /// The measurement itself, independent of any image: this is what was never computed.
    func testDeliveredGeometryIsMeasuredAgainstTheCropThatWillBeUsed() {
        // A 1800-wide square holding a head that spans 1440px: 80% of the square. The whole
        // head is inside the crop, so head fraction is the only thing wrong — which is the
        // failure this measurement exists to see.
        let clamped = ExportPipeline.delivered(
            cropRect: CGRect(x: 0, y: 0, width: 1800, height: 1800),
            crownPx: 100, chinPx: 1540)
        XCTAssertTrue(clamped.containsCrown)
        XCTAssertTrue(clamped.containsChin)
        XCTAssertEqual(clamped.headHeightPct, 80, accuracy: 0.01)
        XCTAssertFalse(clamped.isCompliant)

        // The same head in the square it actually needed: 1440 / 0.64 = 2250.
        let correct = ExportPipeline.delivered(
            cropRect: CGRect(x: 0, y: 0, width: 2250, height: 2250),
            crownPx: 100, chinPx: 1540)
        XCTAssertEqual(correct.headHeightPct, 64, accuracy: 0.01)
        XCTAssertTrue(correct.isCompliant)
    }

    /// A crop that stops short of the chin is not compliant even when the arithmetic on the
    /// head fraction alone would say it is.
    func testACropMissingTheChinIsNotCompliantEvenAtAPlausibleHeadFraction() {
        // 1200px of head in an 1800px square is 66.7% — inside the band. But the chin sits
        // at 1850 and the crop stops at 1800, so 50px of it is not in the photo.
        let cut = ExportPipeline.delivered(
            cropRect: CGRect(x: 0, y: 0, width: 1800, height: 1800),
            crownPx: 650, chinPx: 1850)
        XCTAssertTrue(PassportRules.headHeightInBand(cut.headHeightPct),
                      "the head fraction alone looks fine, which is the point")
        XCTAssertFalse(cut.containsChin)
        XCTAssertFalse(cut.isCompliant)
    }

    /// The user has to be told which way to move, not merely that something is wrong.
    func testRejectionTellsTheUserWhichWayToMove() {
        let tooBig = ExportPipeline.Delivered(headHeightPct: 80, containsCrown: true, containsChin: true)
        XCTAssertTrue(ExportPipeline.rejection(for: tooBig).contains("further"))

        let tooSmall = ExportPipeline.Delivered(headHeightPct: 30, containsCrown: true, containsChin: true)
        XCTAssertTrue(ExportPipeline.rejection(for: tooSmall).contains("closer"))
    }

    func testInfiniteExtentIsRejected() {
        XCTAssertNil(ExportPipeline.makePassportImage(
            from: CIImage(color: .gray), crownY: 0.2, chinY: 0.6),
                     "an image with infinite extent has no geometry to crop")
    }
}
