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

        // Always finish within a bounded time. Vision (especially person segmentation) can
        // occasionally stall on a frame; without a timeout that left "Checking your photo…"
        // on screen forever. Racing a timeout guarantees the spinner always resolves.
        report = await Self.analyzeWithTimeout(engine, image, seconds: 8)
        isAnalyzing = false
    }

    private static func analyzeWithTimeout(_ engine: ComplianceEngine,
                                           _ image: CIImage,
                                           seconds: Double) async -> ComplianceReport {
        // withTaskGroup implicitly awaits ALL children before returning, and Vision's
        // synchronous perform() cannot be cancelled — so a stalled analysis would still
        // hang the screen. Instead resolve from whichever finishes first via a
        // resume-once box; the losing task keeps running but its result is discarded.
        let box = ResolveOnceBox()
        return await withCheckedContinuation { cont in
            box.attach(cont)
            Task.detached { box.resolve(await engine.analyze(image)) }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                box.resolve(ComplianceReport(
                    results: [RuleResult(id: "engine.timeout", status: .verifiedFail,
                                         measured: nil, unit: nil,
                                         message: "Checking took too long — please retake in better light.")],
                    engineVersion: "timeout"))
            }
        }
    }
}

/// Delivers exactly one result to a continuation, whichever racing task resolves first.
private final class ResolveOnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var cont: CheckedContinuation<ComplianceReport, Never>?

    func attach(_ c: CheckedContinuation<ComplianceReport, Never>) {
        lock.lock(); defer { lock.unlock() }
        cont = c
    }

    func resolve(_ report: ComplianceReport) {
        lock.lock(); defer { lock.unlock() }
        guard !done, let c = cont else { return }
        done = true
        cont = nil
        c.resume(returning: report)
    }
}

#Preview {
    RootView()
}
