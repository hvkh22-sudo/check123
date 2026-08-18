import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// Live camera with real-time coaching. The oval turns green and the shutter unlocks only
/// when the frame passes every face check we can make without calibration, so people are
/// guided to a good photo instead of judged after taking a bad one.
///
/// The background is measured live too, but it warns rather than locking the shutter —
/// see `LiveGuidance.isReady` for why.
struct LiveCaptureView: View {
    var onPhoto: (CIImage) -> Void
    var onFallback: () -> Void

    @StateObject private var coach = LiveFaceCoach()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch coach.status {
            case .running:
                cameraLayer
            case .starting:
                ProgressView().tint(.white)
            case .denied:
                message("Camera access is off",
                        detail: "Turn it on in Settings › BorderPixel, or choose a photo from your library instead.")
            case .failed(let reason):
                message("The camera didn't start", detail: reason)
            }
        }
        .overlay {
            if scenePhase != .active {
                PrivacyCover()
            }
        }
        .task { await coach.start() }
        .onDisappear { coach.stop() }
        // The cover hides the preview, but hiding it is not the same as switching the camera
        // off: without this the session kept running behind the app switcher, the capture
        // indicator stayed lit, and Vision kept analysing a face the user had walked away
        // from. `.onDisappear` does not fire for the app switcher, Control Centre or a call
        // banner, so the scene phase has to drive it.
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await coach.start() }
            } else {
                coach.stop()
            }
        }
        .onChange(of: spokenGuidance) { announce($0) }
    }

    /// The one line shown in the capsule at the top of the screen.
    private var mainInstruction: String {
        coach.hint ?? "Looks good — take the photo"
    }

    /// What VoiceOver says: the instruction plus, when it is showing separately as a chip,
    /// the background warning — so a VoiceOver user hears the same two things a sighted
    /// user sees, in one utterance rather than two competing ones.
    private var spokenGuidance: String {
        guard let warning = coach.secondaryWarning else { return mainInstruction }
        return "\(mainInstruction). \(warning)"
    }

    /// VoiceOver only reads what changed if it is told to. Announcements are skipped when
    /// VoiceOver is off so nothing is queued for a user who will never hear it.
    private func announce(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private var cameraLayer: some View {
        ZStack {
            CameraPreview(session: coach.session)
                .ignoresSafeArea()

            // The wall is checked while the user is still standing there, not after the
            // shutter, so the warning has to be visible on this screen.
            if coach.backgroundHint != nil {
                BackgroundWarningWash()
            }

            // The oval is where the head belongs. Green means every live check passes.
            FaceScanOverlay(isReady: coach.isReady)

            VStack {
                Text(mainInstruction)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 24)
                    .animation(.easeInOut(duration: 0.15), value: coach.hint)
                    // The whole point of this screen is coaching, which is useless to a
                    // VoiceOver user who never hears the instruction change. SwiftUI has no
                    // live-region equivalent, so changes are announced explicitly.
                    .accessibilityAddTraits(.updatesFrequently)

                // Only appears when the main line is busy with a face instruction —
                // otherwise the background warning is already the main line.
                if let warning = coach.secondaryWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(.orange.opacity(0.85), in: Capsule())
                        .padding(.top, 8)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: warning)
                }

                Spacer()

                Button {
                    coach.capturePhoto { image in
                        onPhoto(image)
                        dismiss()
                    }
                } label: {
                    Circle()
                        .fill(coach.isReady ? Color.green : Color.white.opacity(0.4))
                        .frame(width: 74, height: 74)
                        .overlay(Circle().stroke(.white, lineWidth: 4).padding(4))
                }
                .disabled(!coach.isReady)
                .padding(.bottom, 12)
                .accessibilityLabel("Take photo")
                .accessibilityHint(coach.isReady
                                   ? "Every live check passes"
                                   : coach.hint ?? "Not ready yet")

                // Never a dead end: coaching can fail in bad light or on an odd device.
                Button("Choose from library instead") {
                    onFallback()
                    dismiss()
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 28)
            }
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle).foregroundStyle(.white.opacity(0.7))
            Text(title).font(.headline).foregroundStyle(.white)
            Text(detail)
                .font(.footnote).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Choose from library") {
                onFallback()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
        }
        .padding(32)
    }
}

/// Hosts the AVFoundation preview layer, which has no SwiftUI equivalent.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
