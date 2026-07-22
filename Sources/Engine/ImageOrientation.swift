import CoreImage
import ImageIO
import UIKit

extension CIImage {
    /// Returns the image with its EXIF orientation baked into the pixels.
    ///
    /// Photos usually carry orientation as metadata rather than as rotated pixels. Vision
    /// was being handed a fixed `.up`, so an ordinary portrait photo — the common case —
    /// was analysed sideways: faces missed, roll and yaw meaningless. Everything downstream
    /// depends on this, so both capture paths upright the image before anything reads it.
    func uprighted() -> CIImage {
        let raw = properties[kCGImagePropertyOrientation as String] as? UInt32 ?? 1
        guard raw != 1, let orientation = CGImagePropertyOrientation(rawValue: raw) else {
            return self
        }
        return oriented(orientation)
    }

    /// Bakes in a `UIImage`'s orientation — the camera path, which has no EXIF dictionary.
    func uprighted(from uiOrientation: UIImage.Orientation) -> CIImage {
        oriented(CGImagePropertyOrientation(uiOrientation))
    }

    /// Scales the image down so its longest side is at most `maxDimension`. Full-resolution
    /// phone photos (12–48MP) make Vision analysis take many seconds — long enough to look
    /// frozen — and cost memory on the crop/export screens. The export target is 1200px, so
    /// anything above ~2400px is wasted work.
    func downscaled(maxDimension: CGFloat = 2400) -> CIImage {
        let e = extent
        guard !e.isInfinite, !e.isNull, e.width > 0, e.height > 0 else { return self }
        let longest = max(e.width, e.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        return transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}

extension CGImagePropertyOrientation {
    init(_ ui: UIImage.Orientation) {
        switch ui {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
