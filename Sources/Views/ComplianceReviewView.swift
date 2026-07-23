import SwiftUI

/// Screen 4 — the core differentiator: honest ✓ / ⚠ / ✗ checklist from a ComplianceReport.
/// See design/UX_SPEC.md §4.
struct ComplianceReviewView: View {
    let report: ComplianceReport
    var onContinue: () -> Void = {}

    private var failed: [RuleResult] { report.results.filter { $0.status == .verifiedFail } }
    private var verified: [RuleResult] { report.results.filter { $0.status == .verifiedPass } }
    private var attention: [RuleResult] {
        report.results.filter { $0.status == .assisted || $0.status == .confirm }
    }

    var body: some View {
        List {
            Section { verdictBanner }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

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
        .safeAreaInset(edge: .bottom) {
            // An honest checker cannot sell an export for a photo it just told you is
            // wrong. A hard ✗ stops here; retaking is free, the export is not.
            VStack(spacing: 6) {
                Button(action: onContinue) {
                    Text(failed.isEmpty ? "Looks good — export" : "Fix the items above first")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!failed.isEmpty)

                if !failed.isEmpty {
                    Text("Retake the photo — checks are always free.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    /// One-glance summary at the top: how many automatic checks passed, and what's blocking.
    private var verdictBanner: some View {
        let passed = verified.count
        let total = verified.count + failed.count
        let blocking = failed.count
        return VStack(spacing: 8) {
            Image(systemName: blocking == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(blocking == 0 ? .green : .orange)
            Text(blocking == 0 ? "Passed every automatic check"
                               : "\(blocking) \(blocking == 1 ? "item needs" : "items need") fixing")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(blocking == 0
                 ? "\(passed) of \(total) on-device checks passed. Confirm the manual items below, then set head size."
                 : "Fix the item\(blocking == 1 ? "" : "s") under “Fix these”, then retake — checks are free.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func ruleRow(_ r: RuleResult, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.message)
                if let m = r.measured, let u = r.unit, m.isFinite {
                    // %.0f, not Int(m): Int(NaN/Inf) is a hard runtime trap.
                    Text("\(String(format: "%.0f", m))\(u)").font(.caption).foregroundStyle(.secondary)
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
