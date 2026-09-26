import SwiftUI
import CoreImage
import Foundation
import UIKit

/// Lets exactly one of two racing tasks resume a continuation.
///
/// Resuming a checked continuation twice is a crash rather than a warning, so the race in
/// `analyzeWithTimeout` needs a hard guarantee and not a hopeful one.
///
/// Internal rather than private so a test can pin that guarantee directly. The failure it
/// prevents is a crash in the field, which is not something to leave to inspection.
final class SingleResume: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Full app flow: Intro → Document type → Capture → Compliance review → Export → Done.
/// Capture uses library import for now (camera + real Vision engine land on-device).
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var path = NavigationPath()
    @State private var capturedImage: CIImage?
    @State private var report: ComplianceReport?
    @State private var isAnalyzing = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisGeneration = UUID()
    @State private var previousPathCount = 0

    private let engine: ComplianceEngine = VisionComplianceEngine()

    enum Route: Hashable {
        case documentType, capture, review, adjust
        /// Findings the user exported past travel to the last screen too — by value, because
        /// the session (and the report with them) is discarded before this screen appears.
        case done(flagged: [String])
        // The guide positions travel WITH the navigation value, not through separate @State,
        // so the crop can never run with stale (0,0) guides — the "head span too small (0px)"
        // failure. Rounded to keep the value stably Hashable.
        case export(crownY: Double, chinY: Double, centerX: Double)
    }

    var body: some View {
        NavigationStack(path: $path) {
            IntroView(onStart: { path.append(Route.documentType) })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .documentType:
                        DocumentTypeView(onContinue: { path.append(Route.capture) })
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
                                                 onContinue: { path.append(Route.adjust) },
                                                 onRetake: { restartAtCapture() })
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
                            path.append(Route.export(crownY: Double(crownY), chinY: Double(chinY),
                                                     centerX: report?.suggestedCenterX ?? 0.5))
                        },
                                         onRetake: { restartAtCapture() })
                    case .export(let cy, let chy, let cx):
                        ExportView(source: capturedImage,
                                   crownY: CGFloat(cy),
                                   chinY: CGFloat(chy),
                                   centerX: CGFloat(cx),
                                   // The review screen's warning travels with the photo. Without
                                   // this the export screen said "Ready to export" under a green
                                   // seal for a photo the previous screen had just flagged.
                                   flagged: flaggedFindings,
                                   onDone: {
                                       // Read before the discard below clears the report.
                                       let flagged = flaggedFindings
                                       discardSensitiveSession()
                                       path = NavigationPath()
                                       path.append(Route.done(flagged: flagged))
                                   },
                                   onRetake: { restartAtCapture() })
                    case .done(let flagged):
                        DoneView(flagged: flagged, onRestart: {
                            // A flagged export's button says "Take a new photo" — so it goes
                            // to the camera, not back to the intro.
                            if flagged.isEmpty {
                                discardSensitiveSession()
                                path = NavigationPath()
                            } else {
                                restartAtCapture()
                            }
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

    /// What the review screen flagged and the user chose to go past. Only the rule's message
    /// travels — no measurement, no image — so nothing sensitive outlives the session.
    private var flaggedFindings: [String] {
        report?.results.filter(\.isAdvisoryConcern).map(\.message) ?? []
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
        guard !Task.isCancelled, generation == analysisGeneration else {
            // Bailing out silently left `isAnalyzing` true and `report` nil, which is the
            // spinner state — so a cancelled run owned the screen forever. Only the current
            // generation may clear the flag: a superseded run must not switch off a spinner
            // that a newer analysis is legitimately showing.
            if generation == analysisGeneration { isAnalyzing = false }
            return
        }
        report = result
        isAnalyzing = false
        analysisTask = nil
    }

    /// Returns whichever finishes first: the analysis, or the timeout.
    ///
    /// This used to race the two inside a `withTaskGroup`, which cannot bound anything: a
    /// task group implicitly awaits every child before its `await` returns, and `cancelAll()`
    /// only *requests* cancellation. Vision's `perform` is synchronous and never observes
    /// that request, so a stalled person-segmentation kept the group alive, the timeout child
    /// never got to win, and "Checking your photo…" stayed on screen with no way out. A
    /// device hit exactly that on 2026-08-23, and the owner reported it had happened before.
    ///
    /// Resuming a continuation from whichever task finishes first genuinely bounds the wait.
    /// The losing task is left to run itself out — an orphaned Vision request holding one
    /// image for a few seconds is a far smaller problem than a screen the user cannot leave.
    static func analyzeWithTimeout(_ engine: ComplianceEngine,
                                   _ image: CIImage,
                                   seconds: Double) async -> ComplianceReport {
        let gate = SingleResume()
        return await withCheckedContinuation { continuation in
            Task.detached {
                let report = await engine.analyze(image)
                if gate.claim() { continuation.resume(returning: report) }
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if gate.claim() {
                    continuation.resume(returning: ComplianceReport(
                        results: [RuleResult(id: "engine.timeout", status: .verifiedFail,
                                             measured: nil, unit: nil,
                                             message: "Checking took too long — please retake in better light.")],
                        engineVersion: "timeout"))
                }
            }
        }
    }

    static func shouldDiscardSession(
        previousPathCount: Int,
        currentPathCount: Int,
        hasSensitiveData: Bool
    ) -> Bool {
        hasSensitiveData && currentPathCount < previousPathCount && currentPathCount <= 2
    }

    /// The stack a retake lands on: document type underneath capture, exactly as on a first
    /// pass.
    ///
    /// It used to be `[capture]` alone, which shifted every later screen one place down.
    /// Adjust sat at depth 3 instead of 4, so going back from it to the review screen matched
    /// the "returned to capture" rule in `shouldDiscardSession`, the new check was wiped, and
    /// the review screen read "That photo couldn't be checked." — after every retake.
    static func retakeStack() -> [Route] { [.documentType, .capture] }

    private func restartAtCapture() {
        discardSensitiveSession()
        path = NavigationPath(Self.retakeStack())
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
