import XCTest
@testable import PassCheck

/// The capture screen delivers 30–60 frames a second and must run Vision on roughly four of
/// them. These pin that the limiter actually limits, because the failure is invisible: the
/// screen still works, it just runs face landmarks on every frame and janks on older phones.
final class FrameThrottleTests: XCTestCase {

    func testFirstFrameIsAlwaysDue() {
        let throttle = FrameThrottle(interval: 0.25)
        XCTAssertTrue(throttle.due(), "The first frame should never be held back")
    }

    func testSecondFrameWithinTheIntervalIsDropped() {
        let throttle = FrameThrottle(interval: 0.25)
        XCTAssertTrue(throttle.due())
        XCTAssertFalse(throttle.due(), "A frame arriving immediately after must be dropped")
    }

    func testABurstOfFramesYieldsExactlyOneAnalysis() {
        let throttle = FrameThrottle(interval: 0.25)
        // One second of camera output arriving faster than the interval.
        let allowed = (0..<60).filter { _ in throttle.due() }.count
        XCTAssertEqual(allowed, 1, "A burst inside one interval should admit a single frame")
    }

    func testFrameIsDueAgainOnceTheIntervalHasElapsed() {
        // Deliberately short, with a generous wait, so this cannot flake on a loaded runner.
        let throttle = FrameThrottle(interval: 0.05)
        XCTAssertTrue(throttle.due())
        XCTAssertFalse(throttle.due())

        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(throttle.due(), "The limiter must reopen after its interval")
    }

    func testARejectedFrameDoesNotPushTheNextOpeningOut() {
        // A rejection must leave the clock alone. If it reset it, a camera delivering frames
        // faster than the interval would starve the check forever — the same starvation bug
        // that the background sampler had on its unusable-frame path.
        //
        // The interval is a full second so the two checks below sit 0.2s clear of the
        // boundary on either side; a tighter window flakes on a loaded runner.
        let throttle = FrameThrottle(interval: 1.0)
        XCTAssertTrue(throttle.due())

        Thread.sleep(forTimeInterval: 0.8)          // 0.8s elapsed — still inside the interval
        XCTAssertFalse(throttle.due())

        Thread.sleep(forTimeInterval: 0.4)          // 1.2s elapsed — past it
        XCTAssertTrue(throttle.due(),
                      "A rejection at 0.8s must not have restarted the interval")
    }
}
