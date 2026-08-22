import XCTest
import Foundation
import UIKit

/// Produces the App Store screenshot set from the simulator at exact device pixel sizes.
///
/// Why this exists: the studio has no Mac, and the one thing a hand-held capture keeps
/// getting wrong is the pixel size — App Store Connect rejects the upload after the shoot
/// is over. Capturing on a known simulator makes the dimensions a property of the runner,
/// not of whoever held the phone.
///
/// What it cannot do: the review, crop and export screens need a real face, and the only
/// face this app may ship in marketing material is a consenting adult's (SCREENSHOT_PLAN.md).
/// So the photo-bearing shots are *conditional*: CI seeds the simulator library with
/// `simctl addmedia` when a sample exists, and this test picks it up. When no photo was
/// seeded the test still passes and records the gap in MANIFEST.txt rather than pretending
/// the set is complete.
final class ScreenshotTests: XCTestCase {

    /// Written next to the PNGs so the CI log can state exactly what was and was not produced.
    private var manifest: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let text = manifest.joined(separator: "\n") + "\n"
        let url = Self.outputDirectory.appendingPathComponent("MANIFEST.txt")
        if let data = text.data(using: .utf8) {
            try? data.write(to: url)
        }
        print("SCREENSHOT-MANIFEST-BEGIN\n\(text)SCREENSHOT-MANIFEST-END")
    }

    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        // Pin the language so a runner locale change cannot silently produce a set in
        // another language than the listing.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // 1 — Intro. The honest-disclosure screen; also the only place the privacy claim
        // and the "no subscription" line appear together.
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20), "Intro screen never appeared")
        try shoot("01-intro")

        // 2 — Scope card. Says US passport only, before the user spends time on a photo.
        getStarted.tap()
        let sizeLine = app.staticTexts["2 x 2 in · 51 x 51 mm · square"]
        XCTAssertTrue(sizeLine.waitForExistence(timeout: 10), "Document-type screen never appeared")
        try shoot("02-scope")

        // 3 — Capture entry point.
        app.buttons["Continue"].tap()
        let library = app.buttons["Choose from library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10), "Capture screen never appeared")
        try shoot("03-capture")

        // 4+ — everything past here needs a face in the simulator's photo library.
        guard selectFirstLibraryPhoto(app, libraryButton: library) else {
            manifest.append("SKIPPED 04-review, 05-crop, 06-export — no photo could be "
                          + "selected from the simulator library. Seed one with "
                          + "`simctl addmedia` (see screenshots.yml) and rerun.")
            return
        }

        // 4 — Compliance review. The hero shot: this is the screen the whole app is for.
        guard app.navigationBars["Compliance check"].waitForExistence(timeout: 30) else {
            manifest.append("SKIPPED 04-review, 05-crop, 06-export — the review screen "
                          + "never appeared after selecting a photo.")
            return
        }

        // The bottom button carries the verdict: "Looks good — export" when every hard
        // rule passed, "Fix the items above first" (disabled) when one did not. Waiting
        // for either is what tells us the spinner resolved.
        let verdict = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Looks good' OR label BEGINSWITH 'Fix the items'")
        ).firstMatch
        let resolved = verdict.waitForExistence(timeout: 30)
        try shoot("04-review")

        guard resolved else {
            manifest.append("SKIPPED 05-crop, 06-export — the analysis never resolved "
                          + "within 30s, so the review screen still showed its spinner.")
            return
        }
        // A sample photo that legitimately fails a hard rule leaves this disabled. That is
        // the product working correctly, not a harness bug — say so instead of hanging.
        guard verdict.isEnabled else {
            manifest.append("SKIPPED 05-crop, 06-export — the seeded photo failed a hard "
                          + "rule, so the app correctly refused to sell an export. Seed a "
                          + "compliant photo to reach the crop and export screens.")
            return
        }
        verdict.tap()

        // 5 — Assisted crop.
        guard app.navigationBars["Adjust"].waitForExistence(timeout: 15) else {
            manifest.append("SKIPPED 05-crop, 06-export — the crop screen never appeared.")
            return
        }
        try shoot("05-crop")
        app.buttons["Continue"].tap()

        // 6 — Export / paywall.
        if app.navigationBars["Export"].waitForExistence(timeout: 25) {
            // Wait past "Preparing your photo…" so the shot shows the real result.
            _ = app.staticTexts["Ready to export"].waitForExistence(timeout: 25)
            try shoot("06-export")
        } else {
            manifest.append("SKIPPED 06-export — the export screen never appeared.")
        }
    }

    // MARK: - Capture

    /// Captures the full screen at native device resolution and writes a PNG the CI job
    /// can pull out of the runner's container.
    private func shoot(_ name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = Self.outputDirectory.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url)

        let image = screenshot.image
        let pixels = "\(Int(image.size.width * image.scale))x\(Int(image.size.height * image.scale))"
        manifest.append("WROTE \(name).png \(pixels)")
    }

    private static let outputDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Photo library

    /// Drives the system photo picker. Best-effort by design: PHPicker is a separate
    /// process and its layout is Apple's, not ours, so a failure here must degrade the
    /// set rather than fail the run and lose the three screenshots already captured.
    private func selectFirstLibraryPhoto(_ app: XCUIApplication,
                                         libraryButton: XCUIElement) -> Bool {
        libraryButton.tap()

        // The picker's grid cells are images inside a collection view. Existing is not
        // enough: the sheet is still animating up when the cell first appears, and a tap
        // on a non-hittable element is silently dropped.
        let cell = app.images.matching(NSPredicate(format: "label CONTAINS[c] 'Photo'"))
            .firstMatch
        if cell.waitForExistence(timeout: 25), waitUntilHittable(cell, timeout: 10) {
            cell.tap()
            return true
        }

        // Fallback: some iOS versions expose the grid as cells rather than images.
        let anyCell = app.collectionViews.cells.firstMatch
        if anyCell.waitForExistence(timeout: 10), waitUntilHittable(anyCell, timeout: 10) {
            anyCell.tap()
            return true
        }

        // Leave the picker so the manifest write in tearDown is not blocked by a sheet.
        let cancel = app.buttons["Cancel"]
        if cancel.exists { cancel.tap() }
        return false
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"),
                                   evaluatedWith: element)
        return XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed
    }
}
