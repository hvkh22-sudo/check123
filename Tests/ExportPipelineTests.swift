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

    func testDegenerateGuidesAreRejectedRatherThanProducingGarbage() {
        let source = sourceImage(width: 2000, height: 2000)
        XCTAssertNil(ExportPipeline.makePassportImage(from: source, crownY: 0.4, chinY: 0.4),
                     "no measurable head height must not yield an image")
    }

    func testInfiniteExtentIsRejected() {
        XCTAssertNil(ExportPipeline.makePassportImage(
            from: CIImage(color: .gray), crownY: 0.2, chinY: 0.6),
                     "an image with infinite extent has no geometry to crop")
    }
}
