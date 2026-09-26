import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import PassCheck

final class PrivacyResourceTests: XCTestCase {
    func testImportRejectsEncodedDataOverBudgetBeforeDecode() {
        let limits = ImageImportLimits(
            maxEncodedBytes: 10,
            maxDimension: 1_000,
            maxPixelCount: 1_000_000,
            targetDimension: 100
        )

        XCTAssertThrowsError(try ImageImportProcessor.prepare(
            data: Data(repeating: 0, count: 11),
            supportedContentTypes: [.jpeg],
            limits: limits
        )) { error in
            XCTAssertEqual(error as? ImageImportError, .encodedDataTooLarge)
        }
    }

    func testFileImportRejectsOversizedAssetBeforeReadingContents() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("passcheck-import-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data(repeating: 0, count: 11).write(to: fileURL)

        let limits = ImageImportLimits(
            maxEncodedBytes: 10,
            maxDimension: 1_000,
            maxPixelCount: 1_000_000,
            targetDimension: 100
        )
        XCTAssertThrowsError(try ImageImportProcessor.prepare(
            fileURL: fileURL,
            supportedContentTypes: [.image],
            limits: limits
        )) { error in
            XCTAssertEqual(error as? ImageImportError, .encodedDataTooLarge)
        }
    }

    func testImportRejectsCorruptImage() {
        XCTAssertThrowsError(try ImageImportProcessor.prepare(
            data: Data([0x00, 0x01, 0x02, 0x03]),
            supportedContentTypes: [.jpeg]
        )) { error in
            XCTAssertEqual(error as? ImageImportError, .invalidImage)
        }
    }

    func testImportRejectsImageTypeOutsideExplicitAllowlist() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image {
            UIColor.white.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            encoded as CFMutableData,
            UTType.gif.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        XCTAssertThrowsError(try ImageImportProcessor.prepare(
            data: encoded as Data,
            supportedContentTypes: [.image]
        )) { error in
            XCTAssertEqual(error as? ImageImportError, .unsupportedType)
        }
    }

    func testImportRejectsExcessiveDimensionsBeforeDecode() throws {
        let data = try XCTUnwrap(makePNG(width: 100, height: 50))
        let limits = ImageImportLimits(
            maxEncodedBytes: data.count + 1,
            maxDimension: 80,
            maxPixelCount: 100_000,
            targetDimension: 40
        )

        XCTAssertThrowsError(try ImageImportProcessor.prepare(
            data: data,
            supportedContentTypes: [.png],
            limits: limits
        )) { error in
            XCTAssertEqual(error as? ImageImportError, .dimensionsTooLarge)
        }
    }

    func testImportRejectsExcessivePixelCountIndependently() throws {
        let data = try XCTUnwrap(makePNG(width: 100, height: 50))
        let limits = ImageImportLimits(
            maxEncodedBytes: data.count + 1,
            maxDimension: 1_000,
            maxPixelCount: 4_000,
            targetDimension: 40
        )

        XCTAssertThrowsError(try ImageImportProcessor.prepare(
            data: data,
            supportedContentTypes: [.png],
            limits: limits
        )) { error in
            XCTAssertEqual(error as? ImageImportError, .dimensionsTooLarge)
        }
    }

    func testImportDownsamplesWithoutFullResolutionOutput() throws {
        let data = try XCTUnwrap(makePNG(width: 100, height: 50))
        let limits = ImageImportLimits(
            maxEncodedBytes: data.count + 1,
            maxDimension: 1_000,
            maxPixelCount: 1_000_000,
            targetDimension: 20
        )

        let image = try ImageImportProcessor.prepare(
            data: data,
            supportedContentTypes: [.png],
            limits: limits
        )

        XCTAssertGreaterThan(image.extent.width, 0)
        XCTAssertGreaterThan(image.extent.height, 0)
        XCTAssertLessThanOrEqual(max(image.extent.width, image.extent.height), 20)
    }

    func testTimeoutCancelsCooperativeAnalysisAndReturnsPromptly() async {
        let started = Date()
        let report = await RootView.analyzeWithTimeout(
            SlowCancellableEngine(),
            CIImage.empty(),
            seconds: 0.02
        )

        XCTAssertEqual(report.engineVersion, "timeout")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testRetryForwardNavigationDoesNotDiscardNewSession() {
        XCTAssertFalse(RootView.shouldDiscardSession(
            previousPathCount: 1,
            currentPathCount: 2,
            hasSensitiveData: true
        ))
    }

    /// After a retake, going back from Adjust to the review screen must keep the new check.
    /// With the old `[capture]` retake stack, the review sat at depth 2 and this discarded it.
    func testGoingBackToTheReviewAfterARetakeKeepsTheCheck() {
        let reviewDepth = RootView.retakeStack().count + 1
        XCTAssertFalse(RootView.shouldDiscardSession(
            previousPathCount: reviewDepth + 1,
            currentPathCount: reviewDepth,
            hasSensitiveData: true
        ))
    }

    /// A retake lands on the same stack as a first pass, so every later screen keeps its depth.
    func testRetakeStackMatchesAFirstPass() {
        XCTAssertEqual(RootView.retakeStack(), [.documentType, .capture])
    }

    func testBackwardNavigationToCaptureDiscardsSession() {
        XCTAssertTrue(RootView.shouldDiscardSession(
            previousPathCount: 3,
            currentPathCount: 2,
            hasSensitiveData: true
        ))
    }

    private func makePNG(width: Int, height: Int) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: CGFloat(width), height: CGFloat(height)),
            format: format
        )
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }.pngData()
    }
}

private struct SlowCancellableEngine: ComplianceEngine {
    func analyze(_ image: CIImage) async -> ComplianceReport {
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return ComplianceReport(results: [], engineVersion: "finished")
        } catch {
            return ComplianceReport(results: [], engineVersion: "cancelled")
        }
    }
}
