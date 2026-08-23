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

    /// Renders a CIImage to a UIImage via the shared context, with one transient retry.
    /// Both the crop preview and the adjust preview go through this, so a memory-pressure
    /// createCGImage stall is retried in one place rather than blanking a screen.
    static func renderUIImage(_ image: CIImage?) -> UIImage? {
        guard let image, !image.extent.isInfinite, !image.extent.isEmpty else { return nil }
        if let cg = sharedContext.createCGImage(image, from: image.extent) { return UIImage(cgImage: cg) }
        if let cg = sharedContext.createCGImage(image, from: image.extent) { return UIImage(cgImage: cg) }
        return nil
    }

    /// Output edge length in pixels. Inside `PassportRules.pixelMin...pixelMax`.
    static let outputSize: CGFloat = 1200

    /// Where in the compliant 50–69% band we aim. Sits in the upper-middle so the head
    /// reads as prominent (closer to what people expect from a passport photo) while
    /// keeping margin below 69% for imprecise guide placement.
    static let targetHeadFraction: CGFloat = 0.64

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

    /// What a crop rectangle actually delivers, as opposed to what it was asked for.
    ///
    /// This type exists because the two were silently allowed to differ. The square's side is
    /// clamped to the source's short edge when the ideal square does not fit, and the code
    /// then cropped and resized without ever asking what head fraction had resulted — so an
    /// ordinary head-and-shoulders photo could ship at ~80% head height under a green
    /// "Ready to export" seal. `PassportRules.headHeightInBand` was never called on the
    /// geometry that reached the customer.
    struct Delivered {
        /// Head height as a percentage of the exported square.
        let headHeightPct: Double
        /// Whether the crop actually contains the crown and the chin. Clamping the square's
        /// origin can push the bottom edge above the chin on a very tight source.
        let containsCrown: Bool
        let containsChin: Bool

        var isCompliant: Bool {
            containsCrown && containsChin && PassportRules.headHeightInBand(headHeightPct)
        }
    }

    /// The head fraction a crop would deliver, computed without performing the crop, so a
    /// screen can promise only what the export can keep.
    ///
    /// `delivered(cropRect:crownPx:chinPx:)` stays authoritative — it measures the rectangle
    /// after clamping and rounding. This differs from it by at most a rounding pixel, which
    /// does not matter for a hint shown while someone drags a line.
    static func predictedHeadHeightPct(sourceWidth: CGFloat, sourceHeight: CGFloat,
                                       crownY: CGFloat, chinY: CGFloat) -> Double {
        guard sourceWidth > 0, sourceHeight > 0 else { return 0 }
        let top = max(0, min(crownY, chinY))
        let bottom = min(1, max(crownY, chinY))
        let headPx = (bottom - top) * sourceHeight
        guard headPx > 0 else { return 0 }
        let side = min(headPx / targetHeadFraction, min(sourceWidth, sourceHeight))
        return Double(headPx / side) * 100
    }

    /// Measures a finished crop rectangle against the head it was supposed to frame.
    ///
    /// Pure and internal so the delivered geometry is testable without a camera: every earlier
    /// test in this file asserted the output's declared size and never its framing, which is
    /// why the clamp shipped unnoticed.
    static func delivered(cropRect: CGRect,
                          crownPx: CGFloat,
                          chinPx: CGFloat) -> Delivered {
        let side = cropRect.height
        guard side > 0 else {
            return Delivered(headHeightPct: 0, containsCrown: false, containsChin: false)
        }
        return Delivered(headHeightPct: Double((chinPx - crownPx) / side) * 100,
                         containsCrown: cropRect.minY <= crownPx,
                         containsChin: cropRect.maxY >= chinPx)
    }

    /// Explains a non-compliant crop in terms the user can act on.
    static func rejection(for delivered: Delivered) -> String {
        if !delivered.containsCrown || !delivered.containsChin {
            return "the square can't fit your whole head — move further from the camera and retake"
        }
        let pct = Int(delivered.headHeightPct.rounded())
        let low = Int(PassportRules.headHeightMinPct), high = Int(PassportRules.headHeightMaxPct)
        if delivered.headHeightPct > PassportRules.headHeightMaxPct {
            return "your head would fill \(pct)% of the photo, above the \(low)–\(high)% allowed — move further from the camera and retake"
        }
        return "your head would fill only \(pct)% of the photo, below the \(low)–\(high)% allowed — move closer and retake"
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

        // Unusable guides used to fall back to a centred square from the upper part of the
        // frame and return it with no failure reason — that is, as a success. It bore no
        // relation to where the head was, and the export screen stamped it "Ready to export"
        // at 1200 × 1200 with a green seal. "Never dead-end" is not a kindness when the way
        // out is selling someone an arbitrary square as their passport photo.
        if headPx <= h * 0.02 {
            return (nil, "the crown and chin lines are on top of each other — place them on your head and try again")
        }

        let side = min(headPx / targetHeadFraction, min(w, h))
        var originX = (w - side) / 2
        var originY = top * h - side * marginAboveCrown
        originX = min(max(originX, 0), w - side)
        originY = min(max(originY, 0), h - side)

        let cropRect = CGRect(x: originX.rounded(), y: originY.rounded(),
                              width: side.rounded(), height: side.rounded())

        // `side` above is clamped to the source's short edge, so the head fraction that
        // results is not necessarily the one that was asked for. Measure the rectangle that
        // will actually be used, and refuse rather than deliver a photo that will be rejected
        // for head size. A retake costs a minute; a rejected passport application does not.
        let result = delivered(cropRect: cropRect, crownPx: top * h, chinPx: bottom * h)
        guard result.isCompliant else {
            return (nil, rejection(for: result))
        }

        // The scale below has no floor at 1:1, so a crop smaller than the output size is
        // upscaled and then labelled "1200 × 1200" on screen. When the real crop is under
        // `pixelMin` that turns "this photo does not have enough detail to comply" into a
        // number that looks compliant — the same trade the head-fraction clamp was making.
        guard cropRect.height >= CGFloat(PassportRules.pixelMin) else {
            return (nil, "there isn't enough detail at this framing — move closer to the camera and retake")
        }

        guard let cropped = base.cropping(to: cropRect) else {
            return (nil, "crop nil rect=\(cropRect) img=\(base.width)×\(base.height)")
        }

        // `cropping(to:)` intersects rather than failing, so a rectangle that overhangs by a
        // rounding pixel yields a non-square image — and the scale below is derived from the
        // width alone and applied to both axes, which would ship 1200 × 1199 under the same
        // green seal.
        guard cropped.width == cropped.height else {
            return (nil, "crop came back \(cropped.width)×\(cropped.height), not square")
        }

        let scale = outputSize / CGFloat(cropped.width)
        let out = CIImage(cgImage: cropped)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return (out, nil)
    }
}
