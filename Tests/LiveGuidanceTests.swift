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
}
