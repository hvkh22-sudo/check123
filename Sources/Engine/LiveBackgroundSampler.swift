import CoreImage
import CoreVideo
import Foundation
import ImageIO

/// Runs the background check on the live camera feed.
///
/// Person segmentation is an order of magnitude heavier than face landmarks, so it cannot
/// share the face coach's 4-per-second cadence or its main-thread hop. This runs on the
/// camera's own queue, on a downscaled copy of the frame, at a cadence slow enough that the
/// preview stays smooth — and it skips entirely while a previous pass is still running.
///
/// It returns its verdict rather than calling back, so the caller owns the hop to the main
/// actor. The sampler is only ever touched from the capture queue that calls `consider`,
/// which is why the unsynchronised state below is safe.
final class LiveBackgroundSampler: @unchecked Sendable {

    enum Outcome {
        /// Not due yet, or the frame was unusable. Leave the last warning alone.
        case skipped
        /// A fresh measurement: the warning to show, or nil when the background is fine.
        case measured(String?)
    }

    /// Long enough that segmentation never queues up behind itself, short enough that a
    /// user who steps in front of a different wall is told within about a second.
    ///
    /// No re-entrancy guard is needed alongside it: `consider` runs synchronously and is
    /// only ever called from the one serial capture queue, so a second pass cannot begin
    /// while the first is still running.
    private let interval: TimeInterval
    /// Segmentation quality stops improving well before full camera resolution, and the
    /// cost scales with pixels, so the frame is shrunk to this longest edge first.
    private let targetLongestEdge: CGFloat

    private var lastRun = Date.distantPast

    init(interval: TimeInterval = 1.2, targetLongestEdge: CGFloat = 320) {
        self.interval = interval
        self.targetLongestEdge = targetLongestEdge
    }

    /// Analyses the frame if enough time has passed. Must be called from the capture queue,
    /// synchronously inside the sample-buffer callback: the pixel buffer is recycled the
    /// moment that callback returns, so the work cannot be deferred to another queue.
    func consider(_ pixelBuffer: CVPixelBuffer,
                  orientation: CGImagePropertyOrientation) -> Outcome {
        guard Date().timeIntervalSince(lastRun) >= interval else { return .skipped }

        // Orient first, then analyse as `.up`. BackgroundAnalyzer samples the mask and the
        // image in the same coordinate space, so handing it a rotated image with a mask
        // generated at a different orientation would misalign the two and end up sampling
        // the person instead of the wall.
        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let extent = oriented.extent
        // `CGRect.isFinite` is package-internal in this SDK; `isInfinite` is the public
        // counterpart, and it is what BackgroundAnalyzer already guards with.
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { return .skipped }
        let longest = max(extent.width, extent.height)
        let scale = min(1, targetLongestEdge / longest)
        let frame = scale < 1
            ? oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : oriented

        let result = BackgroundAnalyzer.analyze(frame)
        // Advanced only once a measurement actually happened. Setting it on the unusable-frame
        // path too meant a run of degenerate frames silently pushed the next real measurement
        // out by a further interval each time.
        lastRun = Date()
        return .measured(result.ok ? nil : result.message)
    }
}
