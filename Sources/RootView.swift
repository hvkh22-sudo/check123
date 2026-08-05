import SwiftUI
import CoreImage
import UIKit

/// Full app flow: Intro → Document type → Capture → Compliance review → Export → Done.
/// Capture uses library import for now (camera + real Vision engine land on-device).
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var path = NavigationPath()
    @State private var docType: DocumentType = .usPassport
    @State private var capturedImage: CIImage?
    @State private var report: ComplianceReport?
    @State private var isAnalyzing = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisGeneration = UUID()
    @State private var previousPathCount = 0

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
                            startCheck(image)
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
                                    restartAtCapture()
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
                                   onDone: {
                                       discardSensitiveSession()
                                       path = NavigationPath()
                                       path.append(Route.done)
                                   },
                                   onRetake: { restartAtCapture() })
                    case .done:
                        DoneView(onRestart: {
                            discardSensitiveSession()
                            path = NavigationPath()
                        })
                    }
                }
        }
        .overlay {
            if scenePhase != .active {
                PrivacyCover()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification
        )) { _ in
            // Preserve an active foreground session, but release facial imagery if iOS is
            // already reclaiming memory while the app is hidden.
            if scenePhase != .active {
                discardSensitiveSession(resetNavigation: true)
            }
        }
        .onChange(of: path.count) { count in
            // Returning to Capture, Document Type, or Intro ends the prior photo session.
            let shouldDiscard = Self.shouldDiscardSession(
                previousPathCount: previousPathCount,
                currentPathCount: count,
                hasSensitiveData: capturedImage != nil || report != nil || isAnalyzing
            )
            previousPathCount = count
            if shouldDiscard {
                discardSensitiveSession()
            }
        }
    }

    private func startCheck(_ image: CIImage) {
        // Camera frames are bounded here; library imports are already validated and
        // downsampled by ImageImportProcessor before they reach this closure.
        let prepared = image.downscaled()
        discardSensitiveSession()
        capturedImage = prepared

        let generation = UUID()
        analysisGeneration = generation
        analysisTask = Task {
            await runCheck(prepared, generation: generation)
        }
    }

    private func runCheck(_ image: CIImage, generation: UUID) async {
        // Navigate first so the user sees progress instead of a frozen capture screen,
        // then fill in the result.
        report = nil
        isAnalyzing = true
        path.append(Route.review)

        // Always finish within a bounded time. Vision (especially person segmentation) can
        // occasionally stall on a frame; without a timeout that left "Checking your photo…"
        // on screen forever. Racing a timeout guarantees the spinner always resolves.
        let result = await Self.analyzeWithTimeout(engine, image, seconds: 6)
        guard !Task.isCancelled, generation == analysisGeneration else { return }
        report = result
        isAnalyzing = false
        analysisTask = nil
    }

    static func analyzeWithTimeout(_ engine: ComplianceEngine,
                                   _ image: CIImage,
                                   seconds: Double) async -> ComplianceReport {
        await withTaskGroup(of: ComplianceReport.self) { group in
            group.addTask { await engine.analyze(image) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return ComplianceReport(
                    results: [RuleResult(id: "engine.timeout", status: .verifiedFail,
                                         measured: nil, unit: nil,
                                         message: "Checking took too long — please retake in better light.")],
                    engineVersion: "timeout")
            }
            let first = await group.next() ?? ComplianceReport(results: [], engineVersion: "cancelled")
            // VisionComplianceEngine forwards cancellation to every active VNRequest, so
            // the task group releases the image instead of leaving orphaned work behind.
            group.cancelAll()
            return first
        }
    }

    static func shouldDiscardSession(
        previousPathCount: Int,
        currentPathCount: Int,
        hasSensitiveData: Bool
    ) -> Bool {
        hasSensitiveData && currentPathCount < previousPathCount && currentPathCount <= 2
    }

    private func restartAtCapture() {
        discardSensitiveSession()
        path = NavigationPath()
        path.append(Route.capture)
    }

    private func discardSensitiveSession(resetNavigation: Bool = false) {
        analysisTask?.cancel()
        analysisTask = nil
        analysisGeneration = UUID()
        capturedImage = nil
        report = nil
        isAnalyzing = false
        if resetNavigation {
            path = NavigationPath()
        }
    }
}

#Preview {
    RootView()
}
