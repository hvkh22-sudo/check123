import CoreImage
import CoreGraphics

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
        let extent = image.extent
        guard extent.isFinite, extent.width > 0, extent.height > 0 else { return nil }

        let top = min(crownY, chinY)
        let bottom = max(crownY, chinY)
        let headHeight = (bottom - top) * extent.height
        guard headHeight > 1 else { return nil }

        // The square that puts the head at the target fraction — never larger than the photo.
        let side = min(headHeight / targetHeadFraction, min(extent.width, extent.height))

        // Guides are top-down; Core Image's origin is bottom-left.
        let crownFromTop = top * extent.height
        let cropTopFromTop = crownFromTop - side * marginAboveCrown

        var originX = extent.midX - side / 2
        var originY = extent.maxY - cropTopFromTop - side

        // Keep the crop inside the photo even when the head sits near an edge.
        originX = min(max(originX, extent.minX), extent.maxX - side)
        originY = min(max(originY, extent.minY), extent.maxY - side)

        let cropRect = CGRect(x: originX, y: originY, width: side, height: side)
        let cropped = image.cropped(to: cropRect)
        guard !cropped.extent.isEmpty else { return nil }

        let scale = outputSize / side
        return cropped
            .transformed(by: CGAffineTransform(translationX: -cropped.extent.minX,
                                               y: -cropped.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
