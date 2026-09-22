import Foundation

// Data models for the compliance engine. Source: ios/COMPLIANCE_ENGINE_SPEC.md.
// Pure value types, fully unit-testable without a camera or Vision.

/// Status of a single compliance rule.
enum RuleStatus: String, Codable {
    case verifiedPass   // machine-verified OK
    case verifiedFail   // machine-verified problem
    case assisted       // user-guided measurement (e.g. head height)
    case confirm        // user must self-confirm (e.g. glasses off, taken in last 6 months)
}

/// One rule's outcome.
struct RuleResult: Identifiable, Codable, Equatable {
    let id: String        // e.g. "head.height"
    var status: RuleStatus
    var measured: Double?  // measured value when applicable (e.g. 61.5)
    var unit: String?      // e.g. "%"
    var message: String

    /// A problem the device measured and did not like, but is not certain enough to block on.
    ///
    /// This is not the same as a rule the app simply cannot check. "Confirm your glasses are
    /// off" asks the user something; "Background isn't plain — 75%" *tells* them something,
    /// and a screen that treats the two alike will cheerfully report that a photo with a sofa
    /// in it passed every check. A measurement is what separates them.
    var isAdvisoryConcern: Bool { status == .confirm && measured != nil }
}

/// Overall verdict derived from the rule set.
enum ReportOutcome: String, Codable {
    case pass
    case needsAttention
    case fail
}

/// How the review screen should present a report.
enum ReviewVerdict: Equatable {
    /// Something the device measured and is sure about. The export stays closed.
    case blocked(count: Int)
    /// Something the device measured and does not like, but cannot be sure enough to stop on.
    /// The export opens, and says so — it must never read as approval.
    case advisory(count: Int)
    /// Nothing measured came back wrong.
    case clean
}

/// The full on-device compliance report. Never leaves the device.
struct ComplianceReport: Codable, Equatable {
    var results: [RuleResult]
    var engineVersion: String

    /// Suggested crown/chin guide positions from the detected face, as top-down fractions
    /// (0 = top of photo, 1 = bottom). The Adjust screen starts the guides here so the user
    /// confirms rather than places them from scratch. Nil when no face was detected.
    var suggestedCrownY: Double?
    var suggestedChinY: Double?
    /// The face's horizontal midpoint, as a fraction of the width from the left. The export
    /// centres its square here rather than on the middle of the photo. Nil when no face was
    /// detected, in which case the export falls back to the middle.
    var suggestedCenterX: Double?

    /// fail if any verified failure; else needsAttention if any assisted/confirm; else pass.
    var overall: ReportOutcome {
        if results.contains(where: { $0.status == .verifiedFail }) { return .fail }
        if results.contains(where: { $0.status == .assisted || $0.status == .confirm }) { return .needsAttention }
        return .pass
    }

    /// What the review screen should tell the user, in the screen's own terms.
    ///
    /// There are three states and there always were, but the screen only ever had two: it
    /// asked whether anything was blocking, and if nothing was, it announced "Passed every
    /// automatic check" under a green seal with a "Looks good — export" button. That was
    /// true for as long as every measured problem also blocked. The moment the background
    /// finding became advice rather than a lock, the same screen started declaring a photo
    /// with a sofa and a picture frame behind the subject to be perfect, while listing the
    /// background problem three inches further down. A device did exactly that on
    /// 2026-08-23.
    ///
    /// Derived here rather than in the view so it can be tested, because the two states the
    /// view could express were the whole defect.
    var reviewVerdict: ReviewVerdict {
        let blocking = results.filter { $0.status == .verifiedFail }.count
        if blocking > 0 { return .blocked(count: blocking) }
        let concerns = results.filter(\.isAdvisoryConcern).count
        if concerns > 0 { return .advisory(count: concerns) }
        return .clean
    }
}
