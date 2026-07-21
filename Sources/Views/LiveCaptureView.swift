import AVFoundation
import CoreImage
import SwiftUI

/// Live camera with real-time coaching. The oval turns green and the shutter unlocks only
/// when the frame passes every check we can make without calibration, so people are guided
/// to a good photo instead of judged after taking a bad one.
struct LiveCaptureView: View {
    var onPhoto: (CIImage) -> Void
    var onFallback: () -> Void

    @StateObject private var coach = LiveFaceCoach()
    @Environment(\.dismiss) private var dismiss

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
                        detail: "Turn it on in Settings › PassCheck, or choose a photo from your library instead.")
            case .failed(let reason):
                message("The camera didn't start", detail: reason)
            }
        }
        .task { await coach.start() }
        .onDisappear { coach.stop() }
    }

    private var cameraLayer: some View {
        ZStack {
            CameraPreview(session: coach.session)
                .ignoresSafeArea()

            // The oval is where the head belongs. Green means every live check passes.
            Ellipse()
                .stroke(coach.isReady ? Color.green : Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 3, dash: coach.isReady ? [] : [10, 8]))
                .frame(width: 250, height: 330)
                .animation(.easeInOut(duration: 0.2), value: coach.isReady)

            VStack {
                Text(coach.hint ?? "Looks good — take the photo")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 24)
                    .animation(.easeInOut(duration: 0.15), value: coach.hint)

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
