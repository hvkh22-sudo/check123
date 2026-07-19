import SwiftUI
import CoreImage

/// App navigation flow: Intro → Document type → (capture) → Compliance review.
/// Capture is stubbed for now (real AVFoundation camera + Vision land after CI is green);
/// the flow runs the stub engine so the review screen is exercisable end-to-end.
struct RootView: View {
    @State private var path = NavigationPath()
    @State private var docType: DocumentType = .usPassport
    @State private var report: ComplianceReport?

    private let engine: ComplianceEngine = StubComplianceEngine()

    enum Route: Hashable { case documentType, review }

    var body: some View {
        NavigationStack(path: $path) {
            IntroView(onStart: { path.append(Route.documentType) })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .documentType:
                        DocumentTypeView(selected: $docType, onContinue: {
                            Task { await runCheck() }
                        })
                    case .review:
                        if let report {
                            ComplianceReviewView(report: report)
                        }
                    }
                }
        }
    }

    private func runCheck() async {
        // Placeholder input; real capture provides the CIImage. Stub ignores it for now.
        report = await engine.analyze(CIImage.empty())
        path.append(Route.review)
    }
}

#Preview {
    RootView()
}
