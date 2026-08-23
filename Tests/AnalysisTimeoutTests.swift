import XCTest
import CoreImage
@testable import PassCheck

/// On 2026-08-23 a device sat on "Checking your photo…" forever, and the owner reported it
/// had happened before. The screen had a six-second timeout, and the timeout could not fire.
///
/// The race was run inside a `withTaskGroup`, which implicitly awaits every child before its
/// `await` returns; `cancelAll()` only *requests* cancellation, and Vision's `perform` is
/// synchronous and never observes the request. So a stalled analysis held the group open, the
/// timeout child never got to win, and the spinner owned the screen with no way out.
///
/// These pin the bound itself rather than the plumbing that provides it.
final class AnalysisTimeoutTests: XCTestCase {

    /// Outlasts every race in this file, and ignores cancellation — the shape of a stalled
    /// Vision request.
    ///
    /// Bounded rather than genuinely infinite: the losing task is deliberately left to run
    /// itself out, and a test must not leave a task spinning for the rest of the process.
    private struct StalledEngine: ComplianceEngine {
        func analyze(_ image: CIImage) async -> ComplianceReport {
            for _ in 0..<200 {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return ComplianceReport(results: [], engineVersion: "stalled",
                                    suggestedCrownY: nil, suggestedChinY: nil)
        }
    }

    private struct InstantEngine: ComplianceEngine {
        let report: ComplianceReport
        func analyze(_ image: CIImage) async -> ComplianceReport { report }
    }

    private var image: CIImage {
        CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
    }

    /// The bound must hold even when the analysis never finishes and never yields.
    func testAStalledAnalysisStillResolvesTheScreen() async {
        let started = Date()
        let report = await RootView.analyzeWithTimeout(StalledEngine(), image, seconds: 0.4)

        XCTAssertEqual(report.engineVersion, "timeout",
                       "A stalled analysis must lose the race, not hold the screen.")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5,
                          "The wait has to be bounded by the timeout, not by the analysis.")
    }

    /// And the timeout must not steal a result that arrived in time.
    func testAPromptAnalysisWins() async {
        let expected = ComplianceReport(
            results: [RuleResult(id: "test.rule", status: .verifiedPass, measured: nil,
                                 unit: nil, message: "fine")],
            engineVersion: "instant", suggestedCrownY: nil, suggestedChinY: nil)

        let report = await RootView.analyzeWithTimeout(InstantEngine(report: expected), image,
                                                       seconds: 5)
        XCTAssertEqual(report.engineVersion, "instant")
    }

    /// A timeout is a failure the user can act on, not a silent pass. If this ever became a
    /// pass, a photo nobody managed to check would sail through the report.
    func testATimedOutReportReadsAsAFailure() async {
        let report = await RootView.analyzeWithTimeout(StalledEngine(), image, seconds: 0.3)
        XCTAssertEqual(report.overall, .fail)
    }

    /// Both racers try to resume the same continuation; resuming twice is a crash rather than
    /// a warning, so the gate that prevents it is worth pinning on its own.
    func testOnlyOneClaimSucceeds() {
        let gate = SingleResume()
        XCTAssertTrue(gate.claim())
        XCTAssertFalse(gate.claim())
        XCTAssertFalse(gate.claim())
    }
}
