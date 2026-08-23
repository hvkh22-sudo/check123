import XCTest
@testable import PassCheck

/// The false pass QA-002 caught on 2026-08-23 had a shape: something the app could not
/// measure resolved to "fine" instead of to "unknown". A sweep of the rest of the compliance
/// engine found the same shape in two more places, and these pin both of them.
///
/// The distinction matters because of how the report is scored. A `.confirm` rule drags the
/// whole report down to `needsAttention`, which the user must resolve; a rule that quietly
/// passes, or that never appears at all, lets the report reach `pass` with the question
/// never asked.
final class UnmeasurableRuleTests: XCTestCase {

    // MARK: - Head tilt

    /// Vision does not always report roll and yaw. That used to be clamped to 0°, and 0°
    /// passes the tilt rule — so an unmeasurable head angle became "Head is straight."
    func testMissingAnglesReadAsUnknownNotAsStraight() {
        let rule = VisionComplianceEngine.tiltRule(rollDeg: nil, yawDeg: nil)

        XCTAssertEqual(rule.status, .confirm, "An angle nobody measured is not a verified pass.")
        XCTAssertNotEqual(rule.status, .verifiedPass)
        XCTAssertNil(rule.measured, "There is no measurement to report.")
    }

    /// One angle is enough to lose. Reporting the other one alone would be a measurement of
    /// half the problem, presented as if it were the whole.
    func testOneMissingAngleIsEnoughToBeUnknown() {
        XCTAssertEqual(VisionComplianceEngine.tiltRule(rollDeg: 2, yawDeg: nil).status, .confirm)
        XCTAssertEqual(VisionComplianceEngine.tiltRule(rollDeg: nil, yawDeg: 2).status, .confirm)
    }

    /// Vision's own documentation warns that roll and yaw can come back NaN on extreme or
    /// degenerate detections — which are the very head positions this rule exists to catch.
    /// A NaN must not reach the failing branch, where `Int(...)` would trap.
    func testNonFiniteAnglesReadAsUnknownAndDoNotTrap() {
        XCTAssertEqual(VisionComplianceEngine.tiltRule(rollDeg: .nan, yawDeg: 3).status, .confirm)
        XCTAssertEqual(VisionComplianceEngine.tiltRule(rollDeg: 3, yawDeg: .infinity).status, .confirm)
    }

    func testMeasuredAnglesStillPassAndFailOnTheirMerits() {
        let straight = VisionComplianceEngine.tiltRule(rollDeg: 3, yawDeg: 4)
        XCTAssertEqual(straight.status, .verifiedPass)
        XCTAssertEqual(straight.measured ?? 0, 4, accuracy: 1e-9, "The larger angle is the one that matters.")

        let tilted = VisionComplianceEngine.tiltRule(rollDeg: -12, yawDeg: 2)
        XCTAssertEqual(tilted.status, .verifiedFail)
        XCTAssertEqual(tilted.measured ?? 0, 12, accuracy: 1e-9, "Reported as magnitude, not direction.")
    }

    // MARK: - The scoring invariant that gives the above its meaning

    /// A report holding an unmeasurable rule must never read as a clean pass. If this ever
    /// changes, every `.confirm` fallback in the engine silently becomes a false pass again.
    func testAReportWithAnUnknownRuleIsNeverAPass() {
        let report = ComplianceReport(
            results: [
                RuleResult(id: "head.centered", status: .verifiedPass, measured: 1, unit: "%",
                           message: "Face is centered."),
                VisionComplianceEngine.tiltRule(rollDeg: nil, yawDeg: nil)
            ],
            engineVersion: "test",
            suggestedCrownY: nil,
            suggestedChinY: nil)

        XCTAssertEqual(report.overall, .needsAttention)
        XCTAssertNotEqual(report.overall, .pass)
    }

    /// And the case that made the sharpness omission dangerous: a rule that is simply absent
    /// costs nothing at all, so the report passes with the question never asked. This pins
    /// why the engine now appends a `.confirm` instead of skipping the rule.
    func testAnAbsentRuleCostsNothingWhichIsWhyNoRuleMayBeSkipped() {
        let withoutSharpness = ComplianceReport(
            results: [RuleResult(id: "head.centered", status: .verifiedPass, measured: 1,
                                 unit: "%", message: "Face is centered.")],
            engineVersion: "test", suggestedCrownY: nil, suggestedChinY: nil)

        XCTAssertEqual(withoutSharpness.overall, .pass,
                       "An omitted rule is invisible to scoring — the reason it must not be omitted.")

        let withUnmeasuredSharpness = ComplianceReport(
            results: withoutSharpness.results + [
                RuleResult(id: "img.sharp", status: .confirm, measured: nil, unit: nil,
                           message: "Couldn't measure sharpness — check the photo is in focus.")
            ],
            engineVersion: "test", suggestedCrownY: nil, suggestedChinY: nil)

        XCTAssertEqual(withUnmeasuredSharpness.overall, .needsAttention)
    }
}
