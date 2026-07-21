import AVFoundation
import CoreImage
import SwiftUI
import Vision

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
    /// The single most important thing to fix right now, or nil when the frame looks good.
    @Published private(set) var hint: String?
    /// True when every live check passes — the shutter turns green.
    @Published private(set) var isReady = false

    let session = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "passcheck.camera")
    private var photoHandler: ((CIImage) -> Void)?

    /// Vision on every frame is wasteful and makes hints flicker; a few times a second
    /// is faster than anyone can react to anyway.
    private var lastAnalysis = Date.distantPast
    private let analysisInterval: TimeInterval = 0.25

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

    func capturePhoto(completion: @escaping (CIImage) -> Void) {
        photoHandler = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Guidance

    /// Front-camera buffers in portrait arrive rotated; Vision needs to be told.
    private let bufferOrientation: CGImagePropertyOrientation = .leftMirrored

    fileprivate func analyze(_ pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: bufferOrientation,
                                            options: [:])
        try? handler.perform([request])
        let faces = request.results ?? []

        let (hint, ready) = guidance(for: faces)
        Task { @MainActor in
            self.hint = hint
            self.isReady = ready
        }
    }

    /// One instruction at a time, ordered by what blocks the shot most.
    private func guidance(for faces: [VNFaceObservation]) -> (String?, Bool) {
        guard let face = faces.max(by: { $0.boundingBox.height < $1.boundingBox.height }) else {
            return ("Put your face in the oval", false)
        }
        if faces.count > 1 {
            return ("Only you should be in the frame", false)
        }

        let roll = abs((face.roll?.doubleValue ?? 0) * 180 / .pi)
        let yaw = abs((face.yaw?.doubleValue ?? 0) * 180 / .pi)
        if max(roll, yaw) > PassportRules.rollToleranceDeg {
            return (yaw > roll ? "Turn to face the camera" : "Straighten your head", false)
        }

        if abs(face.boundingBox.midX - 0.5) > PassportRules.centeringTolerance {
            return ("Center your face", false)
        }
        if abs(face.boundingBox.midY - 0.5) > 0.15 {
            return (face.boundingBox.midY > 0.5 ? "Lower the camera" : "Raise the camera", false)
        }

        // Head size guidance is withheld until the crown estimate is calibrated —
        // see PassportRules.isHeadHeightCalibrated and spike R-A.
        if PassportRules.isHeadHeightCalibrated {
            let pct = PassportRules.estimatedHeadHeightPct(
                faceBoxHeightFraction: Double(face.boundingBox.height))
            if pct < PassportRules.headHeightMinPct { return ("Move closer", false) }
            if pct > PassportRules.headHeightMaxPct { return ("Move back a little", false) }
        }

        return (nil, true)
    }
}

// MARK: - Frame delegate

extension LiveFaceCoach: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
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
        guard let data = photo.fileDataRepresentation(),
              let image = CIImage(data: data) else { return }
        Task { @MainActor in
            // uprighted() bakes in EXIF orientation, so everything downstream — Vision,
            // the crop, the export — sees the photo the way the user saw it.
            self.photoHandler?(image.uprighted())
            self.photoHandler = nil
        }
    }
}
