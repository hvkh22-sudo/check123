import XCTest
@testable import PassCheck

/// The capture screen shows one instruction at a time. These pin the ordering, and pin the
/// deliberate decision that a background problem warns but never locks the shutter.
final class LiveGuidanceTests: XCTestCase {

    func testFaceProblemWinsOverBackgroundProblem() {
        let hint = LiveGuidance.primaryHint(faceHint: "Center your face",
                                            backgroundHint: "Background looks too dark")
        XCTAssertEqual(hint, "Center your face")
    }

    func testBackgroundProblemShownWhenFaceIsFine() {
        let hint = LiveGuidance.primaryHint(faceHint: nil,
                                            backgroundHint: "Background looks too dark")
        XCTAssertEqual(hint, "Background looks too dark")
    }

    func testNoHintWhenEverythingPasses() {
        XCTAssertNil(LiveGuidance.primaryHint(faceHint: nil, backgroundHint: nil))
    }

    func testSecondaryWarningOnlyAppearsBehindAFaceHint() {
        XCTAssertEqual(
            LiveGuidance.secondaryWarning(faceHint: "Straighten your head",
                                          backgroundHint: "Background has too much color"),
            "Background has too much color")
    }

    func testSecondaryWarningSuppressedWhenItIsAlreadyTheMainLine() {
        XCTAssertNil(LiveGuidance.secondaryWarning(faceHint: nil,
                                                   backgroundHint: "Background looks too dark"))
    }

    func testSecondaryWarningNilWhenBackgroundIsFine() {
        XCTAssertNil(LiveGuidance.secondaryWarning(faceHint: "Move closer", backgroundHint: nil))
    }

    /// Segmentation is unavailable on some devices, so gating the shutter on the background
    /// result would strand the user on a screen with no way forward.
    func testBackgroundProblemDoesNotLockTheShutter() {
        XCTAssertTrue(LiveGuidance.isReady(faceHint: nil))
    }

    func testFaceProblemLocksTheShutter() {
        XCTAssertFalse(LiveGuidance.isReady(faceHint: "Put your face in the oval"))
    }

    // MARK: - Vertical position

    /// Vision's origin is bottom-left, so a face near the top of the frame has a large
    /// midY — the phone is below the face and has to come up. The coach said the opposite
    /// until 2026-09-22.
    func testFaceHighInFrameAsksToRaiseTheCamera() {
        XCTAssertEqual(LiveGuidance.verticalHint(faceMidY: 0.80), "Raise the camera")
    }

    func testFaceLowInFrameAsksToLowerTheCamera() {
        XCTAssertEqual(LiveGuidance.verticalHint(faceMidY: 0.20), "Lower the camera")
    }

    /// Inside the band there is nothing to say. Offsets are kept clear of the exact
    /// boundary, because 0.5 + 0.15 - 0.5 is 0.15000000000000002 in floating point.
    func testFaceNearCentreNeedsNoVerticalHint() {
        XCTAssertNil(LiveGuidance.verticalHint(faceMidY: 0.5))
        let justInside = PassportRules.verticalCenteringTolerance - 0.01
        XCTAssertNil(LiveGuidance.verticalHint(faceMidY: 0.5 + justInside))
        XCTAssertNil(LiveGuidance.verticalHint(faceMidY: 0.5 - justInside))
    }

    /// A position Vision could not report gives no instruction rather than a wrong one.
    /// The live coach only coaches; the post-capture report is where "unknown" is judged.
    func testUnmeasuredVerticalPositionGivesNoInstruction() {
        XCTAssertNil(LiveGuidance.verticalHint(faceMidY: .nan))
        XCTAssertNil(LiveGuidance.verticalHint(faceMidY: .infinity))
    }

    // MARK: - Background instruction

    private func background(_ reason: BackgroundAnalyzer.Reason,
                            share: Double? = nil) -> BackgroundAnalyzer.Result {
        BackgroundAnalyzer.Result(ok: reason == .plain,
                                  message: "Background isn't plain — something is behind you, or a shadow is on the wall.",
                                  luminance: 0.8, reason: reason, outlierFraction: share)
    }

    /// The live line tells the user what to do, not what the analyser measured. The
    /// capture screen on 2026-09-14 showed the report sentence verbatim.
    func testLiveBackgroundLineIsAnInstructionNotTheReportSentence() {
        let r = background(.notPlain, share: 0.05)
        let line = LiveGuidance.backgroundInstruction(for: r)
        XCTAssertNotNil(line)
        XCTAssertNotEqual(line, r.message)
        XCTAssertTrue(line?.contains("plain, empty wall") ?? false, "Got: \(line ?? "nil")")
    }

    /// When the review screen will refuse the photo, the camera says so first.
    func testHardFindingWarnsOfRejectionBeforeTheShutter() {
        let hard = background(.notPlain, share: PassportRules.bgOutlierFractionHard)
        let soft = background(.notPlain, share: PassportRules.bgOutlierFractionHard - 0.01)
        XCTAssertTrue(LiveGuidance.backgroundInstruction(for: hard)?.contains("rejected") ?? false)
        XCTAssertFalse(LiveGuidance.backgroundInstruction(for: soft)?.contains("rejected") ?? true)
    }

    func testEachWallProblemGetsItsOwnInstruction() {
        let lines = [BackgroundAnalyzer.Reason.notPlain, .tooDark, .tooColoured, .unevenLighting]
            .compactMap { LiveGuidance.backgroundInstruction(for: background($0, share: 0.05)) }
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(Set(lines).count, 4, "Two different problems must not read the same.")
    }

    /// A plain wall puts nothing on the live screen.
    func testNothingToSayForAPlainWall() {
        XCTAssertNil(LiveGuidance.backgroundInstruction(for: background(.plain, share: 0)))
    }

    /// A wall the device could not measure is said to be unchecked, not left silent — silence
    /// is what turns the ring green. It never locks the shutter (`isReady` ignores it).
    func testAnUnmeasuredWallIsSaidToBeUnchecked() {
        let line = LiveGuidance.backgroundInstruction(for: background(.couldNotMeasure))
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.hasPrefix("Couldn't check the wall") ?? false, "Got: \(line ?? "nil")")
        XCTAssertTrue(LiveGuidance.isReady(faceHint: nil))
    }

    /// The tolerance is a named rule now, and it stays looser than the horizontal one.
    func testVerticalToleranceIsLooserThanHorizontal() {
        XCTAssertGreaterThan(PassportRules.verticalCenteringTolerance,
                             PassportRules.centeringTolerance)
    }
}
