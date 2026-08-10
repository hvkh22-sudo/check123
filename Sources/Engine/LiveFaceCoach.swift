import AVFoundation
import CoreImage
import SwiftUI
import Vision
import UniformTypeIdentifiers

/// Real-time coaching from the camera feed: runs the same Vision checks as the still-photo
/// engine, several times a second, and publishes one short instruction at a time.
///
/// The point is to stop making people take a photo, read a verdict, and try again. The
/// checks here are deliberately the ones that need no calibration — head size stays out
/// until `PassportRules.crownExtensionFactor` is derived from real photos, because a
/// confident "move closer" based on an unvalidated estimate is worse than silence.
@MainActor
final class LiveFaceCoach: NSObject, ObservableObject {

    enum Status: Equatable {
        case starting
        case denied
        case failed(String)
        case running
    }

    @Published private(set) var status: Status = .starting
    /// What the face checks want fixed, or nil when the face itself looks right.
    @Published private(set) var faceHint: String?
    /// What the live background check wants fixed, or nil when the wall behind is fine
    /// (or hasn't been measured yet).
    @Published private(set) var backgroundHint: String?
    /// True when every live check passes — the shutter turns green.
    @Published private(set) var isReady = false

    /// The single most important thing to fix right now, or nil when the frame looks good.
    var hint: String? {
        LiveGuidance.primaryHint(faceHint: faceHint, backgroundHint: backgroundHint)
    }

    /// A background warning worth showing under the main line, or nil.
    var secondaryWarning: String? {
        LiveGuidance.secondaryWarning(faceHint: faceHint, backgroundHint: backgroundHint)
    }

    let session = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "passcheck.camera")
    private var photoHandler: ((CIImage) -> Void)?

    /// Vision on every frame is wasteful and makes hints flicker; a few times a second
    /// is faster than anyone can react to anyway.
    private var lastAnalysis = Date.distantPast
    private let analysisInterval: TimeInterval = 0.25

    /// Background segmentation runs on the capture queue at its own slower cadence — see
    /// LiveBackgroundSampler for why it cannot share the face path. Declared `nonisolated`
    /// so the sample-buffer delegate can reach it without hopping to the main actor.
    private nonisolated let backgroundSampler = LiveBackgroundSampler()

    // MARK: - Lifecycle

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }

        guard configure() else { return }
        let session = self.session
        await withCheckedContinuation { continuation in
            queue.async {
                session.startRunning()
                continuation.resume()
            }
        }
        status = .running
    }

    func stop() {
        let session = self.session
        queue.async { session.stopRunning() }
        // Otherwise a warning measured just before the screen closed is still on screen
        // for over a second the next time it opens, describing a wall that isn't there.
        faceHint = nil
        backgroundHint = nil
        isReady = false
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            status = .failed("This device's front camera isn't available.")
            return false
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else {
            status = .failed("Couldn't read the camera feed.")
            return false
        }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else {
            status = .failed("Couldn't set up the camera.")
            return false
        }
        session.addOutput(photoOutput)

        return true
    }

    // MARK: - Capture

    private var captureInFlight = false

    func capturePhoto(completion: @escaping (CIImage) -> Void) {
        guard !captureInFlight else { return }   // ignore double-taps on the shutter
        captureInFlight = true
        photoHandler = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Guidance

    /// Front-camera buffers in portrait arrive rotated; Vision needs to be told.
    /// Static so the nonisolated sample-buffer delegate can read it too.
    fileprivate static let bufferOrientation: CGImagePropertyOrientation = .leftMirrored

    fileprivate func analyze(_ pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: Self.bufferOrientation,
                                            options: [:])
        try? handler.perform([request])
        let faces = request.results ?? []

        let hint = guidance(for: faces)
        Task { @MainActor in
            self.faceHint = hint
            self.isReady = LiveGuidance.isReady(faceHint: hint)
        }
    }

    /// One instruction at a time, ordered by what blocks the shot most.
    /// Returns nil when the face itself passes every check we can make without calibration.
    private func guidance(for faces: [VNFaceObservation]) -> String? {
        guard let face = faces.max(by: { $0.boundingBox.height < $1.boundingBox.height }) else {
            return "Put your face in the oval"
        }
        if faces.count > 1 {
            return "Only you should be in the frame"
        }

        let roll = abs((face.roll?.doubleValue ?? 0) * 180 / .pi)
        let yaw = abs((face.yaw?.doubleValue ?? 0) * 180 / .pi)
        if max(roll, yaw) > PassportRules.rollToleranceDeg {
            return yaw > roll ? "Turn to face the camera" : "Straighten your head"
        }

        if abs(face.boundingBox.midX - 0.5) > PassportRules.centeringTolerance {
            return "Center your face"
        }
        if abs(face.boundingBox.midY - 0.5) > 0.15 {
            return face.boundingBox.midY > 0.5 ? "Lower the camera" : "Raise the camera"
        }

        // Head size guidance is withheld until the crown estimate is calibrated —
        // see PassportRules.isHeadHeightCalibrated and spike R-A.
        if PassportRules.isHeadHeightCalibrated {
            let pct = PassportRules.estimatedHeadHeightPct(
                faceBoxHeightFraction: Double(face.boundingBox.height))
            if pct < PassportRules.headHeightMinPct { return "Move closer" }
            if pct > PassportRules.headHeightMaxPct { return "Move back a little" }
        }

        return nil
    }
}

// MARK: - Frame delegate

extension LiveFaceCoach: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Background segmentation happens here, synchronously on the capture queue, because
        // the pixel buffer is recycled as soon as this callback returns. Frames dropped
        // during a pass are harmless: `alwaysDiscardsLateVideoFrames` is on and the preview
        // layer draws independently of this output.
        if case .measured(let warning) = backgroundSampler.consider(buffer,
                                                                    orientation: Self.bufferOrientation) {
            Task { @MainActor in self.backgroundHint = warning }
        }

        Task { @MainActor in
            guard Date().timeIntervalSince(self.lastAnalysis) >= self.analysisInterval else { return }
            self.lastAnalysis = Date()
            self.analyze(buffer)
        }
    }
}

// MARK: - Photo delegate

extension LiveFaceCoach: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        // On any failure (capture error, unreadable data) clear the in-flight state and
        // surface a hint, so the shutter never silently no-ops and leaves the user stuck.
        let image: CIImage? = (error == nil)
            ? photo.fileDataRepresentation().flatMap {
                try? ImageImportProcessor.prepare(data: $0, supportedContentTypes: [.image])
            }
            : nil
        Task { @MainActor in
            self.captureInFlight = false
            if let image {
                // ImageImportProcessor applies EXIF orientation while creating the bounded
                // thumbnail, so downstream Vision/crop/export sees the displayed geometry.
                self.photoHandler?(image)
                self.photoHandler = nil
            } else {
                self.photoHandler = nil
                self.faceHint = "That shot didn't save — try again"
            }
        }
    }
}
