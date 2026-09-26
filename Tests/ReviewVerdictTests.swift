import XCTest
@testable import PassCheck

/// The review screen had two states where the report has three, and on 2026-08-23 a device
/// showed what that costs. A photo with a sofa and a framed picture behind the subject was
/// presented under a green seal reading "Passed every automatic check", with a button saying
/// "Looks good — export" — while three inches further down the same screen listed
/// "Background isn't plain — something is behind you". Both were rendered from the same
/// question: is anything blocking? Nothing was, so the screen announced success.
///
/// These pin the third state. The screen used to compute this inline, which is why nothing
/// could catch it.
final class ReviewVerdictTests: XCTestCase {

    private func report(_ results: [RuleResult]) -> ComplianceReport {
        ComplianceReport(results: results, engineVersion: "test",
                         suggestedCrownY: nil, suggestedChinY: nil)
    }

    private let headStraight = RuleResult(id: "head.tilt", status: .verifiedPass,
                                          measured: 0, unit: "°", message: "Head is straight.")
    private let faceCentred = RuleResult(id: "head.centered", status: .verifiedPass,
                                         measured: 3, unit: "%", message: "Face is centered.")
    /// A rule the app cannot check at all. It asks the user something.
    private let glasses = RuleResult(id: "face.glasses", status: .confirm, measured: nil,
                                     unit: nil, message: "Confirm your glasses are off.")
    /// Head size is deliberately assisted rather than measured, pending calibration.
    private let headSize = RuleResult(id: "head.height", status: .assisted, measured: nil,
                                      unit: nil,
                                      message: "Head size — we'll frame it correctly on the next step.")
    /// A problem the device measured and did not like. It tells the user something.
    private let clutteredBackground = RuleResult(
        id: "bg.plain", status: .confirm, measured: 75, unit: "%",
        message: "Background isn't plain — something is behind you, or a shadow is on the wall.")

    // MARK: - The regression

    /// The exact shape of the screen the owner photographed.
    func testAMeasuredProblemIsNeverReportedAsPassingEverything() {
        let verdict = report([headStraight, faceCentred, headSize, glasses,
                              clutteredBackground]).reviewVerdict

        XCTAssertEqual(verdict, .advisory(count: 1))
        XCTAssertNotEqual(verdict, .clean,
                          "This is the photo with a sofa in it that the screen called perfect.")
    }

    /// A measurement is what separates "we found something" from "we could not check this".
    func testAMeasuredFindingIsAConcernAndAManualAskIsNot() {
        XCTAssertTrue(clutteredBackground.isAdvisoryConcern)
        XCTAssertFalse(glasses.isAdvisoryConcern, "This asks the user; it does not report a finding.")
        XCTAssertFalse(headSize.isAdvisoryConcern)
        XCTAssertFalse(headStraight.isAdvisoryConcern, "A passing measurement is not a concern.")
    }

    /// A rule the device could not measure asks rather than warns, so it must not turn the
    /// banner orange on its own — otherwise every older phone without segmentation would be
    /// permanently told something is wrong.
    func testAnUnmeasurableRuleDoesNotCountAsAConcern() {
        let unmeasurable = RuleResult(id: "img.sharp", status: .confirm, measured: nil,
                                      unit: nil,
                                      message: "Couldn't measure sharpness — check the photo is in focus.")
        XCTAssertFalse(unmeasurable.isAdvisoryConcern)
        XCTAssertEqual(report([headStraight, unmeasurable]).reviewVerdict, .clean)
    }

    /// An unmeasured machine check keeps the verdict clean (above) but is still listed as
    /// unchecked, so the screen cannot call the photo fully checked. A manual ask, a head size
    /// the user sets, a measured finding and a pass without a number are none of them.
    func testAnUnmeasuredMachineCheckIsListedAsUnchecked() {
        let unmeasuredSharpness = RuleResult(id: "img.sharp", status: .confirm, measured: nil, unit: nil,
                                             message: "Couldn't measure sharpness — check the photo is in focus.")
        let unmeasuredBackground = RuleResult(id: "bg.plain", status: .confirm, measured: nil, unit: nil,
                                              message: "Is the background a plain, light, shadow-free wall?")
        let eyesOpen = RuleResult(id: "face.eyesopen", status: .verifiedPass, measured: nil, unit: nil,
                                  message: "Both eyes open.")
        let r = report([headStraight, eyesOpen, glasses, headSize, clutteredBackground,
                        unmeasuredSharpness, unmeasuredBackground])
        XCTAssertEqual(r.uncheckedMachineRules.map(\.id), ["img.sharp", "bg.plain"])
    }

    func testAFullyMeasuredReportHasNothingUnchecked() {
        XCTAssertTrue(report([headStraight, faceCentred, glasses, headSize]).uncheckedMachineRules.isEmpty)
    }

    // MARK: - The other two states still behave

    func testAVerifiedFailureBlocks() {
        let tooDark = RuleResult(id: "bg.plain", status: .verifiedFail, measured: 40, unit: "%",
                                 message: "Background looks too dark — use a plain, light wall.")
        XCTAssertEqual(report([headStraight, tooDark]).reviewVerdict, .blocked(count: 1))
    }

    /// A blocking failure outranks an advisory one: there is no point offering "export anyway"
    /// next to an item the app will not let past.
    func testBlockingOutranksAdvisory() {
        let tooDark = RuleResult(id: "bg.dark", status: .verifiedFail, measured: 40, unit: "%",
                                 message: "Background looks too dark.")
        XCTAssertEqual(report([tooDark, clutteredBackground]).reviewVerdict, .blocked(count: 1))
    }

    func testNothingMeasuredWrongIsClean() {
        XCTAssertEqual(report([headStraight, faceCentred, glasses, headSize]).reviewVerdict, .clean)
    }

    /// The overall outcome and the screen's verdict must not drift apart: anything the screen
    /// calls advisory is still, in the report's own terms, something needing attention.
    func testAnAdvisoryReportIsStillNotAPass() {
        let r = report([headStraight, faceCentred, clutteredBackground])
        XCTAssertEqual(r.reviewVerdict, .advisory(count: 1))
        XCTAssertEqual(r.overall, .needsAttention)
        XCTAssertNotEqual(r.overall, .pass)
    }
}
