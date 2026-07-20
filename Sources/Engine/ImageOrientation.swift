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
