import XCTest
import CoreImage
import ImageIO
import UIKit
@testable import PassCheck

/// What the customer pays for leaves the app as a file, and the government uploader judges
/// the file: type (JPG, JPEG, PNG, HEIC or HEIF) and size (54 KB – 10 MB). The export used to
/// hand SwiftUI an `Image` and let it choose both. These pin that it is now a JPEG with the
/// pixel dimensions the export screen prints.
final class ExportFileTests: XCTestCase {

    private func exportedImage() throws -> UIImage {
        let source = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 1800, height: 2400))
        let square = try XCTUnwrap(ExportPipeline.makePassportImage(from: source, crownY: 0.30, chinY: 0.55))
        return try XCTUnwrap(ExportPipeline.renderUIImage(square))
    }

    func testTheSharedFileIsAJPEG() throws {
        let file = try XCTUnwrap(PassportPhotoFile(image: try exportedImage()))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(file.jpeg as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
    }

    /// The file has the pixels the export screen's "1,200 × 1,200 px" label claims — not a
    /// screen-scale multiple of them.
    func testTheSharedFileHasTheExportedPixelSize() throws {
        let image = try exportedImage()
        let file = try XCTUnwrap(PassportPhotoFile(image: image))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(file.jpeg as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertEqual(width, height)
        XCTAssertEqual(Double(width), Double(ExportPipeline.outputSize), accuracy: 1)
        XCTAssertLessThan(file.jpeg.count, 10 * 1024 * 1024, "The uploader's ceiling is 10 MB.")
    }
}
