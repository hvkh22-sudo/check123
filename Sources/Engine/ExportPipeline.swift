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

    /// One shared Core Image context. Creating a fresh CIContext per call is expensive and,
    /// right after the heavy background segmentation, occasionally failed under memory
    /// pressure — which is what made the first crop attempt intermittently fail.
    static let sharedContext = CIContext(options: [.cacheIntermediates: false])

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
    /// Convenience wrapper returning just the image (used by tests).
    static func makePassportImage(from image: CIImage,
                                  crownY: CGFloat,
                                  chinY: CGFloat) -> CIImage? {
        make(from: image, crownY: crownY, chinY: chinY).image
    }

    /// Builds the export image and, on failure, a short reason string. The reason is shown
    /// on-device so a crop failure pinpoints its own cause instead of me guessing blind.
    static func make(from image: CIImage,
                     crownY: CGFloat,
                     chinY: CGFloat) -> (image: CIImage?, reason: String?) {
        let extent = image.extent
        if extent.isInfinite || extent.isNull {
            return (nil, "source extent invalid (\(extent.debugDescription))")
        }
        if extent.width < 1 || extent.height < 1 {
            return (nil, "source too small (\(Int(extent.width))×\(Int(extent.height)))")
        }

        // Render to a concrete bitmap FIRST — an oriented CIImage can report a lazily
        // evaluated extent that defeated cropping. A CGImage is finite, top-left origin.
        // One transient retry: createCGImage can fail once under memory pressure and
        // succeed immediately after.
        var base = sharedContext.createCGImage(image, from: extent)
        if base == nil { base = sharedContext.createCGImage(image, from: extent) }
        guard let base else {
            return (nil, "render failed at \(Int(extent.width))×\(Int(extent.height))")
        }

        let w = CGFloat(base.width)
        let h = CGFloat(base.height)

        // CGImage space is top-down (y grows downward), matching the guide fractions.
        let top = max(0, min(crownY, chinY))
        let bottom = min(1, max(crownY, chinY))
        let headPx = (bottom - top) * h

        // If the guides are unusable (degenerate/equal), never dead-end: fall back to a
        // centered square from the upper part of the frame, where a selfie's head sits.
        // The user still gets a valid 1200×1200 and can retake for tighter framing.
        if headPx <= h * 0.02 {
            let s = min(w, h)
            let ox = min(max((w - s) / 2, 0), w - s)
            let oy = min(max(h * 0.06, 0), h - s)
            let rect = CGRect(x: ox.rounded(), y: oy.rounded(), width: s.rounded(), height: s.rounded())
            if let c = base.cropping(to: rect) {
                let sc = outputSize / CGFloat(c.width)
                return (CIImage(cgImage: c).transformed(by: CGAffineTransform(scaleX: sc, y: sc)), nil)
            }
            return (nil, "fallback crop failed \(Int(w))×\(Int(h))")
        }

        let side = min(headPx / targetHeadFraction, min(w, h))
        var originX = (w - side) / 2
        var originY = top * h - side * marginAboveCrown
        originX = min(max(originX, 0), w - side)
        originY = min(max(originY, 0), h - side)

        let cropRect = CGRect(x: originX.rounded(), y: originY.rounded(),
                              width: side.rounded(), height: side.rounded())
        guard let cropped = base.cropping(to: cropRect) else {
            return (nil, "crop nil rect=\(cropRect) img=\(base.width)×\(base.height)")
        }

        let scale = outputSize / CGFloat(cropped.width)
        let out = CIImage(cgImage: cropped)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return (out, nil)
    }
}
