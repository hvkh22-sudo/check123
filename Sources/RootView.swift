import SwiftUI
import CoreImage

/// Full app flow: Intro → Document type → Capture → Compliance review → Export → Done.
/// Capture uses library import for now (camera + real Vision engine land on-device).
struct RootView: View {
    @State private var path = NavigationPath()
    @State private var docType: DocumentType = .usPassport
    @State private var capturedImage: CIImage?
    @State private var report: ComplianceReport?
    @State private var isAnalyzing = false
    @State private var analysisToken = 0

    private let engine: ComplianceEngine = VisionComplianceEngine()

    enum Route: Hashable {
        case documentType, capture, review, adjust, done
        // The guide positions travel WITH the navigation value, not through separate @State,
        // so the crop can never run with stale (0,0) guides — the "head span too small (0px)"
        // failure. Rounded to keep the value stably Hashable.
        case export(crownY: Double, chinY: Double)
    }

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
                            // Downscale once at ingest: full-res photos make Vision analysis
                            // look frozen and strain memory downstream. 2400px keeps the
                            // 1200px export crisp.
                            let prepared = image.downscaled()
                            capturedImage = prepared
                            Task { await runCheck(prepared) }
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
                                         suggestedCrownY: report?.suggestedCrownY,
                                         suggestedChinY: report?.suggestedChinY,
                                         onRecheck: { crownY, chinY in
                            // Carry the guides in the navigation value itself.
                            path.append(Route.export(crownY: Double(crownY), chinY: Double(chinY)))
                        })
                    case .export(let cy, let chy):
                        ExportView(source: capturedImage,
                                   crownY: CGFloat(cy),
                                   chinY: CGFloat(chy),
                                   onDone: { path.append(Route.done) },
                                   onRetake: {
                                       capturedImage = nil
                                       report = nil
                                       path = NavigationPath()
                                       path.append(Route.capture)
                                   })
                    case .done:
                        DoneView(onRestart: {
                            // The privacy policy promises the photo is gone once you
                            // export or leave — actually drop it, don't just navigate.
                            capturedImage = nil
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

        // Tag this run. If the user backs out and retakes, a slow earlier analysis must not
        // land on the new attempt — that stale result was corrupting state and causing the
        // intermittent "Couldn't prepare" with no reason.
        analysisToken &+= 1
        let token = analysisToken

        // Run Vision off the main actor so the UI stays responsive.
        let engine = self.engine
        let result = await Task.detached { await engine.analyze(image) }.value

        guard token == analysisToken else { return }   // a newer capture superseded this one
        report = result
        isAnalyzing = false
    }
}

#Preview {
    RootView()
}
