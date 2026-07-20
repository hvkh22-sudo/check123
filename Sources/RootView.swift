import SwiftUI
import CoreImage

/// Full app flow: Intro → Document type → Capture → Compliance review → Export → Done.
/// Capture uses library import for now (camera + real Vision engine land on-device).
struct RootView: View {
    @State private var path = NavigationPath()
    @State private var docType: DocumentType = .usPassport
    @State private var capturedImage: CIImage?
    @State private var exportImage: CIImage?
    @State private var report: ComplianceReport?

    private let engine: ComplianceEngine = VisionComplianceEngine()

    enum Route: Hashable { case documentType, capture, review, adjust, export, done }

    var body: some View {
        NavigationStack(path: $path) {
            IntroView(onStart: { path.append(Route.documentType) })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .documentType:
                        DocumentTypeView(selected: $docType,
                                         onContinue: { path.append(Route.capture) })
                    case .capture:
                        CaptureView(onPhoto: { image in
                            capturedImage = image
                            Task { await runCheck(image) }
                        })
                    case .review:
                        if let report {
                            ComplianceReviewView(report: report,
                                                 onContinue: { path.append(Route.adjust) })
                        }
                    case .adjust:
                        AssistedCropView(image: capturedImage,
                                         onRecheck: { crownY, chinY in
                            // The guides are the whole point — build the real export from
                            // them rather than handing back the untouched photo.
                            if let source = capturedImage {
                                exportImage = ExportPipeline.makePassportImage(
                                    from: source, crownY: crownY, chinY: chinY)
                            }
                            path.append(Route.export)
                        })
                    case .export:
                        ExportView(image: exportImage ?? capturedImage,
                                   onDone: { path.append(Route.done) })
                    case .done:
                        DoneView(onRestart: {
                            // The privacy policy promises the photo is gone once you
                            // export or leave — actually drop it, don't just navigate.
                            capturedImage = nil
                            exportImage = nil
                            report = nil
                            path = NavigationPath()
                        })
                    }
                }
        }
    }

    private func runCheck(_ image: CIImage) async {
        report = await engine.analyze(image)
        path.append(Route.review)
    }
}

#Preview {
    RootView()
}
