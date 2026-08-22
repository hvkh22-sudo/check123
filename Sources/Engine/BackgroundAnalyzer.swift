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

    static func analyze(
        _ image: CIImage,
        cancellation: VisionRequestCancellation? = nil
    ) -> Result {
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .fast   // .balanced was slow enough to look frozen
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8
        cancellation?.register(req)

        guard !Task.isCancelled else {
            return Result(ok: false, message: "Photo checking was cancelled.", luminance: nil)
        }

        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        guard (try? handler.perform([req])) != nil,
              let mask = req.results?.first?.pixelBuffer else {
            if Task.isCancelled {
                return Result(ok: false, message: "Photo checking was cancelled.", luminance: nil)
            }
            // Segmentation unavailable (older device / failure) — fall back to asking.
            return Result(ok: false, message: "Is the background a plain, light, shadow-free wall?",
                          luminance: nil)
        }

        guard let stats = sampleBackground(image: image, mask: mask) else {
            return Result(ok: false, message: "Is the background a plain, light, shadow-free wall?",
                          luminance: nil)
        }

        return verdict(for: stats)
    }

    /// Internal rather than private so the two decisions that actually reject a photo —
    /// how the samples are reduced to a statistic, and which message that statistic earns —
    /// can be tested without a camera. That is where the QA-002 false pass lived.
    struct Stats {
        let luminance: Double
        let saturation: Double
        /// Luminance spread across the whole background. Catches gradients and shadows.
        let stdDev: Double
        /// Share of samples sitting further than `bgOutlierDeviation` from the median.
        /// Catches objects, which `stdDev` averages away.
        let outlierFraction: Double
    }

    /// Reduces the sampled background luminances to the statistics the verdict is made on.
    ///
    /// The median, not the mean, anchors the outlier test: an object large enough to move
    /// the mean towards itself would otherwise start hiding behind its own influence.
    static func stats(luminances: [Double], meanSaturation: Double) -> Stats {
        // The median below indexes directly, so an empty set would trap rather than produce
        // a number. Reported as NaN, which `verdict` turns into a failure, never a pass.
        guard !luminances.isEmpty else {
            return Stats(luminance: .nan, saturation: .nan, stdDev: .nan, outlierFraction: .nan)
        }

        let n = Double(luminances.count)
        let mean = luminances.reduce(0, +) / n
        let variance = luminances.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n

        let sorted = luminances.sorted()
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2

        let outliers = luminances.reduce(into: 0) { count, l in
            if abs(l - median) > PassportRules.bgOutlierDeviation { count += 1 }
        }

        return Stats(luminance: mean,
                     saturation: meanSaturation,
                     stdDev: variance.squareRoot(),
                     outlierFraction: Double(outliers) / n)
    }

    /// Turns the statistics into a pass/fail and the one line the user reads.
    ///
    /// The failing dimensions are ranked by how far past their own threshold they are,
    /// rather than by a fixed order. Under the fixed order, "too dark" was checked first
    /// and therefore masked every other reason: a bright but cluttered wall was told to
    /// find more light, and the sentence about objects behind you could never be reached.
    static func verdict(for stats: Stats) -> Result {
        // A degenerate sample set produces NaN, and every comparison against NaN is false —
        // which would have filtered out all four failures and returned a silent pass. Given
        // that this whole function exists because of a false pass, it fails closed instead.
        guard stats.luminance.isFinite, stats.saturation.isFinite,
              stats.stdDev.isFinite, stats.outlierFraction.isFinite else {
            return Result(ok: false,
                          message: "Is the background a plain, light, shadow-free wall?",
                          luminance: nil)
        }

        // Each margin is expressed as a fraction of its own threshold, so the four are
        // comparable despite being measured in different units.
        let failures: [(margin: Double, message: String)] = [
            ((PassportRules.bgLuminanceMin - stats.luminance) / PassportRules.bgLuminanceMin,
             "Background looks too dark — use a plain, light wall."),
            ((stats.saturation - PassportRules.bgSaturationMax) / PassportRules.bgSaturationMax,
             "Background has too much color — a plain white/off-white wall works best."),
            ((stats.outlierFraction - PassportRules.bgOutlierFractionMax) / PassportRules.bgOutlierFractionMax,
             "Something behind you is breaking up the wall — clear it, or move to an empty one."),
            ((stats.stdDev - PassportRules.bgUniformityMax) / PassportRules.bgUniformityMax,
             "Background isn't even — move away from shadows and bright patches.")
        ].filter { $0.margin > 0 }

        guard let worst = failures.max(by: { $0.margin < $1.margin }) else {
            return Result(ok: true, message: "Background looks plain and light.",
                          luminance: stats.luminance)
        }
        return Result(ok: false, message: worst.message, luminance: stats.luminance)
    }

    /// Samples a grid of points, keeps those the mask marks as background, and returns
    /// mean luminance, mean saturation, and luminance spread (uniformity).
    private static func sampleBackground(image: CIImage, mask: CVPixelBuffer) -> Stats? {
        let extent = image.extent
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1,
              let cg = ExportPipeline.sharedContext.createCGImage(image, from: extent),
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
        return stats(luminances: lums, meanSaturation: satSum / Double(lums.count))
    }
}
