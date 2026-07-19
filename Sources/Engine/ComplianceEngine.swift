import Foundation
import CoreImage

/// Analyzes a photo and produces a ComplianceReport. On-device only (Vision/Core Image).
/// Full algorithm: ios/COMPLIANCE_ENGINE_SPEC.md. Protocol-based so tests/UI inject a stub.
protocol ComplianceEngine {
    func analyze(_ image: CIImage) async -> ComplianceReport
}

/// Placeholder engine (B2 scaffold) so the UI and tests can be built now.
/// Real Vision-backed rules (face, tilt, eyes, background, sharpness, head-height assist)
/// land incrementally per the spec once cloud CI is compiling. Ignores the image for now.
struct StubComplianceEngine: ComplianceEngine {
    let engineVersion = "0.1-stub"

    func analyze(_ image: CIImage) async -> ComplianceReport {
        ComplianceReport(
            results: [
                RuleResult(id: "fmt.square", status: .verifiedPass, measured: nil, unit: nil,
                           message: "Square crop and size look right."),
                RuleResult(id: "head.height", status: .assisted, measured: nil, unit: "%",
                           message: "Align the crown and chin guides to check head size."),
                RuleResult(id: "face.glasses", status: .confirm, measured: nil, unit: nil,
                           message: "Please confirm your glasses are off.")
            ],
            engineVersion: engineVersion
        )
    }
}
