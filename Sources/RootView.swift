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
    @State private var isAnalyzing = false

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
                        // Never render nothing here. Before this had a bare `if let`, so a
                        // report that wasn't ready left a blank screen with no way out —
                        // the first thing the owner hit on a real device.
                        if let report {
                            ComplianceReviewView(report: report,
                                                 onContinue: { path.append(Route.adjust) })
                        } else if isAnalyzing {
                            VStack(spacing: 14) {
                                ProgressView()
                                Text("Checking your photo…")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            .navigationTitle("Compliance check")
                            .navigationBarTitleDisplayMode(.inline)
                        } else {
                            VStack(spacing: 14) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle).foregroundStyle(.orange)
                                Text("That photo couldn't be checked.")
                                    .font(.headline)
                                Text("Take a new photo of your face against a plain, light wall.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Try another photo") {
                                    path = NavigationPath()
                                    path.append(Route.capture)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding()
                            .navigationTitle("Compliance check")
                            .navigationBarTitleDisplayMode(.inline)
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
                                   isCropped: exportImage != nil,
                                   onDone: { path.append(Route.done) },
                                   onRetake: {
                                       capturedImage = nil
                                       exportImage = nil
                                       report = nil
                                       path = NavigationPath()
                                       path.append(Route.capture)
                                   })
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
        // Navigate first so the user sees progress instead of a frozen capture screen,
        // then fill in the result.
        report = nil
        isAnalyzing = true
        path.append(Route.review)
        report = await engine.analyze(image)
        isAnalyzing = false
    }
}

#Preview {
    RootView()
}
