import AVFoundation
import CoreImage
import SwiftUI
import Vision
import UniformTypeIdentifiers

/// Front-camera buffers in portrait arrive rotated; Vision needs to be told.
///
/// A file-scope constant rather than a static on `LiveFaceCoach`: a static inside a
/// `@MainActor` type inherits that isolation, and the sample-buffer delegate that needs it
/// is nonisolated (an error, not a warning, under the Swift 6 language mode).
private let liveBufferOrientation: CGImagePropertyOrientation = .leftMirrored

/// Rate limiter owned by the capture queue.
///
/// Like `LiveBackgroundSampler`, this is only ever touched from the single serial capture
/// queue, which is what makes the unsynchronised `lastRun` safe. Keeping the cadence here
/// rather than behind a hop to the main actor matters: a frame that is not due is dropped
/// before anything captures it, so it never holds a buffer from the capture pool.
///
/// Internal rather than private only so `FrameThrottleTests` can reach it. The cadence is what
/// stands between this screen and a Vision call on every single frame, and its failure mode is
/// invisible — the screen still works, it just janks on older phones — so it is worth pinning.
final class FrameThrottle: @unchecked Sendable {
    private let interval: TimeInterval
    private var lastRun = Date.distantPast

    init(interval: TimeInterval) { self.interval = interval }

    /// True at most once per `interval`, and only then does the clock advance.
    func due() -> Bool {
        guard Date().timeIntervalSince(lastRun) >= interval else { return false }
        lastRun = Date()
        return true
    }
}

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
    private nonisolated let faceThrottle = FrameThrottle(interval: 0.25)

    /// Background segmentation runs on the capture queue at its own slower cadence — see
    /// LiveBackgroundSampler for why it cannot share the face path. Declared `nonisolated`
    /// so the sample-buffer delegate can reach it without hopping to the main actor.
    private nonisolated let backgroundSampler = LiveBackgroundSampler()

    /// Inputs and outputs may only be added once — adding them a second time fails and would
    /// report the camera as broken. Suspending for the app switcher stops the session but
    /// leaves it configured, so resuming is only `startRunning()`.
    private var isConfigured = false

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

        if !isConfigured {
            guard configure() else { return }
            isConfigured = true
        }

        let session = self.session
        await withCheckedContinuation { continuation in
            queue.async {
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        status = .running
    }

    /// Suspends capture. Called both when the screen closes and whenever the scene stops
    /// being active — leaving the camera running behind the app switcher kept the capture
    /// indicator lit and kept analysing frames the user had walked away from.
    func stop() {
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
        // Otherwise a warning measured just before the screen closed is still on screen
        // for over a second the next time it opens, describing a wall that isn't there.
        faceHint = nil
        backgroundHint = nil
        isReady = false
        // A shot that was still developing when the user left is abandoned rather than
        // delivered to a screen that has gone away; without this the in-flight flag also
        // stayed set and the shutter was dead for the rest of the session.
        captureInFlight = false
        photoHandler = nil
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

    // Frame orientation lives at file scope — see `liveBufferOrientation` at the top of
    // this file, and the note there on why it cannot be a static on this type.

    /// Runs on the capture queue, synchronously inside the sample-buffer callback.
    ///
    /// `VNDetectFaceLandmarksRequest` is synchronous and expensive. On the main actor it
    /// blocked the very screen it was driving — the oval, the sweep animation and the hint
    /// capsule all render there — several times a second. Only the resulting strings hop to
    /// the main actor now.
    fileprivate nonisolated func analyze(_ pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: liveBufferOrientation,
                                            options: [:])
        try? handler.perform([request])
        let faces = request.results ?? []

        let hint = Self.guidance(for: faces)
        Task { @MainActor in
            self.faceHint = hint
            self.isReady = LiveGuidance.isReady(faceHint: hint)
        }
    }

    /// One instruction at a time, ordered by what blocks the shot most.
    /// Returns nil when the face itself passes every check we can make without calibration.
    ///
    /// Static because it is called from the capture queue: it reads only `PassportRules`
    /// constants and holds no state of its own. `nonisolated` for the reason given at the top
    /// of this file — a static inside a `@MainActor` type inherits that isolation, so without
    /// it this would be unreachable from the nonisolated sample-buffer path.
    private nonisolated static func guidance(for faces: [VNFaceObservation]) -> String? {
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
                                                                    orientation: liveBufferOrientation) {
            Task { @MainActor in self.backgroundHint = warning }
        }

        // The cadence is checked here, on the capture queue, rather than after a hop to the
        // main actor. A frame that is not due now costs one comparison and is released with
        // the callback, instead of allocating a task that retains a capture-pool buffer
        // until the main actor gets round to discarding it.
        guard faceThrottle.due() else { return }
        analyze(buffer)
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
