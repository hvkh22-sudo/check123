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
}

/// Overall verdict derived from the rule set.
enum ReportOutcome: String, Codable {
    case pass
    case needsAttention
    case fail
}

/// The full on-device compliance report. Never leaves the device.
struct ComplianceReport: Codable, Equatable {
    var results: [RuleResult]
    var engineVersion: String

    /// fail if any verified failure; else needsAttention if any assisted/confirm; else pass.
    var overall: ReportOutcome {
        if results.contains(where: { $0.status == .verifiedFail }) { return .fail }
        if results.contains(where: { $0.status == .assisted || $0.status == .confirm }) { return .needsAttention }
        return .pass
    }
}
