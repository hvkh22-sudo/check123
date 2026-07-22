import CoreImage
import Vision

/// Checks whether the photo's background is plain and light, on-device.
///
/// This replaces a self-report ("Is the background a plain wall?") with a real measurement:
/// Vision segments the person, and we sample the pixels *outside* the person mask. A
/// passport background must be plain and near-white, so we score its brightness, how white
/// (low-saturation) it is, and how uniform it is across the frame.
enum BackgroundAnalyzer {

    struct Result {
        let ok: Bool
        let message: String
        /// Mean background luminance, 0–1, for display/tuning. Nil when it couldn't run.
        let luminance: Double?
    }

    static func analyze(_ image: CIImage) -> Result {
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .balanced
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        guard (try? handler.perform([req])) != nil,
              let mask = req.results?.first?.pixelBuffer else {
            // Segmentation unavailable (older device / failure) — fall back to asking.
            return Result(ok: false, message: "Is the background a plain, light, shadow-free wall?",
                          luminance: nil)
        }

        guard let stats = sampleBackground(image: image, mask: mask) else {
            return Result(ok: false, message: "Is the background a plain, light, shadow-free wall?",
                          luminance: nil)
        }

        let brightEnough = stats.luminance >= PassportRules.bgLuminanceMin
        let whiteEnough = stats.saturation <= PassportRules.bgSaturationMax
        let uniform = stats.stdDev <= PassportRules.bgUniformityMax

        if brightEnough && whiteEnough && uniform {
            return Result(ok: true, message: "Background looks plain and light.",
                          luminance: stats.luminance)
        }

        let reason: String
        if !brightEnough {
            reason = "Background looks too dark — use a plain, light wall."
        } else if !whiteEnough {
            reason = "Background has too much color — a plain white/off-white wall works best."
        } else {
            reason = "Background isn't uniform — remove shadows and objects behind you."
        }
        return Result(ok: false, message: reason, luminance: stats.luminance)
    }

    private struct Stats { let luminance: Double; let saturation: Double; let stdDev: Double }

    /// Samples a grid of points, keeps those the mask marks as background, and returns
    /// mean luminance, mean saturation, and luminance spread (uniformity).
    private static func sampleBackground(image: CIImage, mask: CVPixelBuffer) -> Stats? {
        let ctx = CIContext(options: [.cacheIntermediates: false])
        let extent = image.extent
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1,
              let cg = ctx.createCGImage(image, from: extent),
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let bpp = cg.bitsPerPixel / 8
        let bpr = cg.bytesPerRow
        let w = cg.width
        let h = cg.height
        guard bpp >= 3 else { return nil }

        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let mw = CVPixelBufferGetWidth(mask)
        let mh = CVPixelBufferGetHeight(mask)
        let mbpr = CVPixelBufferGetBytesPerRow(mask)
        guard let mbase = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let mptr = mbase.assumingMemoryBound(to: UInt8.self)

        var lums: [Double] = []
        var satSum = 0.0
        let steps = 40
        for iy in 0..<steps {
            for ix in 0..<steps {
                let fx = (Double(ix) + 0.5) / Double(steps)
                let fy = (Double(iy) + 0.5) / Double(steps)

                // Person mask: high value = person. Sample only background (low mask value).
                let my = min(mh - 1, Int(fy * Double(mh)))
                let mx = min(mw - 1, Int(fx * Double(mw)))
                if mptr[my * mbpr + mx] > 40 { continue }

                let px = min(w - 1, Int(fx * Double(w)))
                let py = min(h - 1, Int(fy * Double(h)))
                let off = py * bpr + px * bpp
                let r = Double(ptr[off]) / 255
                let g = Double(ptr[off + 1]) / 255
                let b = Double(ptr[off + 2]) / 255

                lums.append(0.299 * r + 0.587 * g + 0.114 * b)
                let maxc = max(r, g, b), minc = min(r, g, b)
                satSum += maxc <= 0 ? 0 : (maxc - minc) / maxc
            }
        }

        guard lums.count >= 20 else { return nil }   // too little background visible
        let mean = lums.reduce(0, +) / Double(lums.count)
        let variance = lums.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(lums.count)
        return Stats(luminance: mean, saturation: satSum / Double(lums.count),
                     stdDev: variance.squareRoot())
    }
}
