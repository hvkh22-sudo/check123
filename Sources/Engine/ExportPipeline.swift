import CoreImage
import CoreGraphics
import UIKit

/// Turns the captured photo plus the user's crown/chin guides into the square, correctly
/// sized image the passport spec requires.
///
/// This is the thing the user actually pays for. Without it the export is the untouched
/// camera photo, which is neither square nor within the 600–1200px bounds, and would be
/// rejected by the government uploader's own format check.
///
/// No pixel is altered beyond cropping and scaling — see D-007: no AI, no background
/// replacement, no retouching. The US State Department rejects AI-edited photos.
enum ExportPipeline {

    /// Output edge length in pixels. Inside `PassportRules.pixelMin...pixelMax`.
    static let outputSize: CGFloat = 1200

    /// Where in the compliant 50–69% band we aim. The middle gives the most tolerance
    /// to a slightly imprecise guide placement in either direction.
    static let targetHeadFraction: CGFloat = 0.60

    /// Headroom above the crown, as a fraction of the square. The remainder falls below
    /// the chin, which is what gives passport framing its shoulders-visible look.
    static let marginAboveCrown: CGFloat = 0.12

    /// Builds the export image.
    /// - Parameters:
    ///   - crownY: crown position as a fraction of image height, measured top-down.
    ///   - chinY: chin position as a fraction of image height, measured top-down.
    /// - Returns: a square `outputSize` × `outputSize` image, or nil if the guides or the
    ///   source image are unusable.
    static func makePassportImage(from image: CIImage,
                                  crownY: CGFloat,
                                  chinY: CGFloat) -> CIImage? {
        // Render to a concrete bitmap FIRST. Portrait photos carry EXIF orientation, and an
        // oriented CIImage can report a non-zero-origin or lazily-evaluated extent that made
        // `cropped(to:)` silently return an empty image — the export then fell back to the
        // uncropped photo. A rendered CGImage is always finite, top-left origin, dimensions
        // in pixels, so the crop math below cannot be defeated by orientation.
        let ctx = CIContext(options: [.cacheIntermediates: false])
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull, extent.width >= 1, extent.height >= 1,
              let base = ctx.createCGImage(image, from: extent) else { return nil }

        let w = CGFloat(base.width)
        let h = CGFloat(base.height)

        // CGImage space is top-down (y grows downward), which matches the guide fractions.
        let top = max(0, min(crownY, chinY))
        let bottom = min(1, max(crownY, chinY))
        let headPx = (bottom - top) * h
        guard headPx > 1 else { return nil }

        // Square that puts the head at the target fraction — never larger than the photo.
        let side = min(headPx / targetHeadFraction, min(w, h))

        var originX = (w - side) / 2                     // centre horizontally
        var originY = top * h - side * marginAboveCrown  // a little headroom above the crown
        originX = min(max(originX, 0), w - side)
        originY = min(max(originY, 0), h - side)

        let cropRect = CGRect(x: originX.rounded(), y: originY.rounded(),
                              width: side.rounded(), height: side.rounded())
        guard let cropped = base.cropping(to: cropRect) else { return nil }

        let scale = outputSize / CGFloat(cropped.width)
        return CIImage(cgImage: cropped)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
