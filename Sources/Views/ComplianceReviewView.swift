import SwiftUI

/// Screen 4 — the core differentiator: honest ✓ / ⚠ / ✗ checklist from a ComplianceReport.
/// See design/UX_SPEC.md §4.
struct ComplianceReviewView: View {
    let report: ComplianceReport

    private var failed: [RuleResult] { report.results.filter { $0.status == .verifiedFail } }
    private var verified: [RuleResult] { report.results.filter { $0.status == .verifiedPass } }
    private var attention: [RuleResult] {
        report.results.filter { $0.status == .assisted || $0.status == .confirm }
    }

    var body: some View {
        List {
            if !failed.isEmpty {
                Section("Fix these") {
                    ForEach(failed) { ruleRow($0, icon: "xmark.circle.fill", color: .red) }
                }
            }
            if !verified.isEmpty {
                Section("Verified on your phone") {
                    ForEach(verified) { ruleRow($0, icon: "checkmark.circle.fill", color: .green) }
                }
            }
            if !attention.isEmpty {
                Section("You'll want to double-check") {
                    ForEach(attention) { ruleRow($0, icon: "exclamationmark.triangle.fill", color: .orange) }
                }
            }
        }
        .navigationTitle("Compliance check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ruleRow(_ r: RuleResult, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.message)
                if let m = r.measured, let u = r.unit {
                    Text("\(Int(m))\(u)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        // status conveyed by glyph + text + section title, never colour alone (accessibility).
    }
}

#Preview {
    NavigationStack {
        ComplianceReviewView(report: ComplianceReport(
            results: [
                RuleResult(id: "fmt.square", status: .verifiedPass, measured: nil, unit: nil,
                           message: "Correct square size & resolution"),
                RuleResult(id: "bg.white", status: .verifiedFail, measured: nil, unit: nil,
                           message: "Background is too dark — use a plain light wall"),
                RuleResult(id: "head.height", status: .assisted, measured: 61, unit: "%",
                           message: "Head size — aligned with your guides")
            ],
            engineVersion: "0.1-stub"
        ))
    }
}
