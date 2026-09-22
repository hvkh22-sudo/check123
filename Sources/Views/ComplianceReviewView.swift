import SwiftUI

/// Screen 4 — the core differentiator: honest ✓ / ⚠ / ✗ checklist from a ComplianceReport.
/// See design/UX_SPEC.md §4.
///
/// The screen has three verdicts and each one must *look* like what it is. A device on
/// 2026-09-14 showed the failure mode: the background was flagged, the flag was filed under
/// "You'll want to double-check" next to "confirm your glasses are off", and the prominent
/// button read "Looks good — export". The user's reading was that the app does not care
/// about the background. It did care; it just did not say so where it counted.
struct ComplianceReviewView: View {
    let report: ComplianceReport
    var onContinue: () -> Void = {}
    /// Back to the camera. Retaking is the answer to every non-clean verdict, so it is a
    /// real button here rather than a navigation-bar chevron the user has to find.
    var onRetake: () -> Void = {}

    private var failed: [RuleResult] { report.results.filter { $0.status == .verifiedFail } }
    private var verified: [RuleResult] { report.results.filter { $0.status == .verifiedPass } }
    /// Measured by the phone and not liked. Distinct from the manual asks below — a
    /// measurement that came back wrong is a finding, not a checkbox.
    private var flagged: [RuleResult] { report.results.filter(\.isAdvisoryConcern) }
    /// Checks the phone normally makes but could not make on this photo.
    private var unchecked: [RuleResult] { report.uncheckedMachineRules }
    /// Things the phone cannot measure and asks the user to confirm.
    private var manual: [RuleResult] {
        report.results.filter { ($0.status == .assisted || $0.status == .confirm) && !$0.isAdvisoryConcern }
    }

    var body: some View {
        List {
            Section { verdictBanner }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            if !failed.isEmpty {
                Section("Fix these — retake") {
                    ForEach(failed) { ruleRow($0, icon: "xmark.circle.fill", color: .red) }
                }
            }
            if !flagged.isEmpty {
                Section {
                    ForEach(flagged) { ruleRow($0, icon: "exclamationmark.triangle.fill", color: .orange) }
                } header: {
                    Text("Your phone flagged this")
                } footer: {
                    Text("Passport offices reject photos with anything behind you — objects, furniture, shadows. A plain, light wall fixes it.")
                }
            }
            if !verified.isEmpty {
                Section("Verified on your phone") {
                    ForEach(verified) { ruleRow($0, icon: "checkmark.circle.fill", color: .green) }
                }
            }
            if !manual.isEmpty {
                Section("Confirm yourself") {
                    ForEach(manual) { ruleRow($0, icon: "questionmark.circle.fill", color: .secondary) }
                }
            }
        }
        .navigationTitle("Compliance check")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions }
    }

    // MARK: - Actions

    /// An honest checker cannot sell an export for a photo it just told you is wrong.
    ///
    /// Blocked: the only way forward is a new photo, so that is the one prominent button.
    /// Flagged: retaking is still the prominent button, because that is the advice; going
    /// on is a small plain link that says what it is. Clean: export, prominently.
    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            switch report.reviewVerdict {
            case .blocked:
                prominent("Retake photo", action: onRetake)
                Text("Checks are always free.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .advisory:
                prominent("Retake against a plain wall", action: onRetake)
                Button("Export anyway — it may be rejected", action: onContinue)
                    .font(.footnote)
            case .clean:
                // "Looks good" is a claim. When a check never ran it is not one the app can
                // make, so the button just says where it goes.
                prominent(unchecked.isEmpty ? "Looks good — export" : "Continue to export",
                          action: onContinue)
            }
        }
        .padding()
        .background(.bar)
    }

    private func prominent(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Banner

    private var verdictBanner: some View {
        let passed = verified.count
        let total = verified.count + failed.count
        return VStack(spacing: 8) {
            Image(systemName: bannerSymbol)
                .font(.system(size: 40))
                .foregroundStyle(bannerTint)
            Text(bannerHeadline)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(bannerDetail(passed: passed, total: total))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal)
    }

    private var bannerSymbol: String {
        switch report.reviewVerdict {
        case .blocked: return "xmark.octagon.fill"
        case .advisory: return "exclamationmark.triangle.fill"
        case .clean: return unchecked.isEmpty ? "checkmark.seal.fill" : "checkmark.circle.fill"
        }
    }

    private var bannerTint: Color {
        switch report.reviewVerdict {
        case .blocked: return .red
        case .advisory: return .orange
        case .clean: return .green
        }
    }

    private var bannerHeadline: String {
        switch report.reviewVerdict {
        case .blocked: return "Not ready — retake"
        case .advisory: return "Not ready yet"
        case .clean: return unchecked.isEmpty ? "Passed every automatic check" : "No problems found"
        }
    }

    private func bannerDetail(passed: Int, total: Int) -> String {
        switch report.reviewVerdict {
        case .blocked(let count):
            return "This photo would be rejected. Fix the \(count == 1 ? "item" : "\(count) items") under “Fix these”, then take a new one."
        case .advisory(let count):
            return "Your phone flagged \(count == 1 ? "something" : "\(count) things") it can't be certain about — but a passport office would be. Retake against a plain, light wall."
        case .clean:
            if !unchecked.isEmpty {
                let n = unchecked.count
                return "\(passed) of \(total + n) on-device checks passed; \(n == 1 ? "one" : "\(n)") couldn't run on this photo. Confirm \(n == 1 ? "it" : "them") yourself below, then set head size."
            }
            return "\(passed) of \(total) on-device checks passed. Confirm the manual items below, then set head size."
        }
    }

    // MARK: - Rows

    private func ruleRow(_ r: RuleResult, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.message)
                if let m = r.measured, let u = r.unit, m.isFinite {
                    // %.0f, not Int(m): Int(NaN/Inf) is a hard runtime trap.
                    Text("\(String(format: "%.0f", m))\(u)").font(.caption).foregroundStyle(.secondary)
                }
                if BuildChannel.showsCalibration, let d = r.diagnostic {
                    Text(d).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        // status conveyed by glyph + text + section title, never colour alone (accessibility).
    }
}

#Preview("Flagged background") {
    NavigationStack {
        ComplianceReviewView(report: ComplianceReport(
            results: [
                RuleResult(id: "head.tilt", status: .verifiedPass, measured: 0, unit: "°",
                           message: "Head is straight."),
                RuleResult(id: "bg.plain", status: .confirm, measured: 9, unit: "% of background",
                           message: "Background isn't plain — something is behind you, or a shadow is on the wall."),
                RuleResult(id: "head.height", status: .assisted, measured: nil, unit: nil,
                           message: "Head size — we'll frame it correctly on the next step."),
                RuleResult(id: "face.glasses", status: .confirm, measured: nil, unit: nil,
                           message: "Confirm your glasses are off.")
            ],
            engineVersion: "0.1-stub"
        ))
    }
}

#Preview("Blocked") {
    NavigationStack {
        ComplianceReviewView(report: ComplianceReport(
            results: [
                RuleResult(id: "bg.plain", status: .verifiedFail, measured: 31, unit: "% of background",
                           message: "Background isn't plain — something is behind you, or a shadow is on the wall."),
                RuleResult(id: "head.tilt", status: .verifiedPass, measured: 0, unit: "°",
                           message: "Head is straight.")
            ],
            engineVersion: "0.1-stub"
        ))
    }
}
