import CoreImage
import Vision

/// Checks whether the photo's background is plain and light, on-device.
///
/// This replaces a self-report ("Is the background a plain wall?") with a real measurement:
/// Vision segments the person, and we sample the pixels *outside* the person mask. A
/// passport background must be plain and near-white, so it is scored on four things: how
/// bright it is, how white it is, how evenly it is lit, and how much of it does not look
/// like the wall at all.
enum BackgroundAnalyzer {

    /// Which dimension decided the verdict.
    ///
    /// The caller needs this because the four are not equally trustworthy. Brightness and
    /// colour are means over the whole background and behave predictably. Whether the wall is
    /// *plain* leans on a person mask, on a threshold that is still uncalibrated against real
    /// photographs, and it cannot tell an object from the subject's own shadow. Presenting
    /// those two with the same authority was what left a user in an ordinary room unable to
    /// go on: the app was right that a shadow was there, and being right is not the same as
    /// being certain enough to stop someone.
    enum Reason {
        case plain
        case tooDark
        case tooColoured
        case notPlain
        case unevenLighting
        case couldNotMeasure
    }

    struct Result {
        let ok: Bool
        let message: String
        /// Mean background luminance, 0–1, for display/tuning. Nil when it couldn't run.
        let luminance: Double?
        let reason: Reason
        /// Share of background samples that did not look like the wall, 0–1. Only set when
        /// the statistic could be computed. The caller grades a `.notPlain` finding by this:
        /// a small share is advice, a large one is a verified failure.
        var outlierFraction: Double? = nil
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
            return Result(ok: false, message: "Photo checking was cancelled.",
                          luminance: nil, reason: .couldNotMeasure)
        }

        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        guard (try? handler.perform([req])) != nil,
              let mask = req.results?.first?.pixelBuffer else {
            if Task.isCancelled {
                return Result(ok: false, message: "Photo checking was cancelled.",
                          luminance: nil, reason: .couldNotMeasure)
            }
            // Segmentation unavailable (older device / failure) — fall back to asking.
            return Result(ok: false, message: "Is the background a plain, light, shadow-free wall?",
                          luminance: nil, reason: .couldNotMeasure)
        }

        guard let stats = sampleBackground(image: image, mask: mask) else {
            return Result(ok: false, message: "Is the background a plain, light, shadow-free wall?",
                          luminance: nil, reason: .couldNotMeasure)
        }

        return verdict(for: stats)
    }

    /// One background pixel. Kept as colour rather than reduced to luminance on the spot,
    /// because a curtain that is the same brightness as the wall but a different colour is
    /// invisible to luminance alone — and the mean saturation that used to be the only
    /// colour signal has exactly the averaging flaw this file exists to remove.
    struct Sample {
        let r: Double
        let g: Double
        let b: Double

        var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }
        var saturation: Double {
            let mx = max(r, g, b), mn = min(r, g, b)
            return mx <= 0 ? 0 : (mx - mn) / mx
        }
    }

    /// Internal rather than private so the two decisions that actually reject a photo —
    /// how the samples are reduced to a statistic, and which message that statistic earns —
    /// can be tested without a camera. That is where the false pass of 2026-08-23 lived.
    struct Stats {
        let luminance: Double
        let saturation: Double
        /// Luminance spread across the whole background. Catches light falling off across
        /// the wall.
        let stdDev: Double
        /// Share of samples that do not look like the wall. Catches objects and cast
        /// shadows, which a spread measure averages away.
        let outlierFraction: Double
        /// The deviation a sample had to exceed to count. Reported for tuning; it adapts to
        /// how varied the wall itself is.
        let outlierThreshold: Double
    }

    /// The lower median: for an even count this is a value that actually occurs in the
    /// image, rather than the midpoint between the two central ones. That midpoint is
    /// exactly wrong for the case this statistic exists to catch — a background split half
    /// wall and half wardrobe puts the interpolated anchor in the empty space between them,
    /// leaving both halves equidistant from it and neither one an outlier.
    static func lowerMedian(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[(sorted.count - 1) / 2]
    }

    /// Reduces the sampled background pixels to the statistics the verdict is made on.
    ///
    /// The wall is estimated robustly — the median luminance and the median of each colour
    /// channel — and a sample's deviation is the largest of its departures from those. A
    /// sample counts as "not the wall" when it exceeds a threshold that **scales with how
    /// varied the wall already is**: a multiple of the median deviation, floored so that a
    /// perfectly flat wall still has a usable band. That scaling is what separates a wall
    /// lit unevenly, where every sample drifts a little, from a wall with something on it,
    /// where most samples agree and a few do not.
    static func stats(samples: [Sample]) -> Stats {
        guard !samples.isEmpty else {
            return Stats(luminance: .nan, saturation: .nan, stdDev: .nan,
                         outlierFraction: .nan, outlierThreshold: .nan)
        }

        let n = Double(samples.count)
        let lums = samples.map { $0.luminance }
        let mean = lums.reduce(0, +) / n
        let variance = lums.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n

        let medianL = lowerMedian(lums)
        let medianR = lowerMedian(samples.map { $0.r })
        let medianG = lowerMedian(samples.map { $0.g })
        let medianB = lowerMedian(samples.map { $0.b })

        let deviations = samples.map { s in
            max(abs(s.luminance - medianL),
                abs(s.r - medianR), abs(s.g - medianG), abs(s.b - medianB))
        }
        let threshold = max(PassportRules.bgOutlierScale * lowerMedian(deviations),
                            PassportRules.bgOutlierFloor)
        let outliers = deviations.reduce(into: 0) { count, d in
            if d > threshold { count += 1 }
        }

        return Stats(luminance: mean,
                     saturation: samples.reduce(0.0) { $0 + $1.saturation } / n,
                     stdDev: variance.squareRoot(),
                     outlierFraction: Double(outliers) / n,
                     outlierThreshold: threshold)
    }

    /// Turns the statistics into a pass/fail and the one line the user reads.
    ///
    /// The failing dimensions are ranked by how far past their own threshold they are,
    /// rather than by a fixed order. Under a fixed order, "too dark" was checked first and
    /// masked every other reason: a bright but cluttered wall was told to find more light,
    /// and the sentence about the wall not being plain could never be reached at all.
    static func verdict(for stats: Stats) -> Result {
        // A degenerate sample set produces NaN, and every comparison against NaN is false,
        // which would filter out all four failures and return a pass. It reports "could not
        // measure" instead. Note what the caller then does with that: VisionComplianceEngine
        // maps a nil luminance to a user-confirmed checkbox, not to a failure — the same
        // fallback used when segmentation is unavailable on an older device. So this is not
        // a hard fail, and this comment must not claim it is.
        guard stats.luminance.isFinite, stats.saturation.isFinite,
              stats.stdDev.isFinite, stats.outlierFraction.isFinite else {
            return Result(ok: false,
                          message: "Is the background a plain, light, shadow-free wall?",
                          luminance: nil, reason: .couldNotMeasure)
        }

        // Each margin is a fraction of its own threshold, so the four rank by relative
        // severity rather than by absolute units.
        let failures: [(margin: Double, message: String, reason: Reason)] = [
            ((PassportRules.bgLuminanceMin - stats.luminance) / PassportRules.bgLuminanceMin,
             "Background looks too dark — use a plain, light wall.", .tooDark),
            ((stats.saturation - PassportRules.bgSaturationMax) / PassportRules.bgSaturationMax,
             "Background has too much color — a plain white/off-white wall works best.", .tooColoured),
            ((stats.outlierFraction - PassportRules.bgOutlierFractionMax) / PassportRules.bgOutlierFractionMax,
             "Background isn't plain — something is behind you, or a shadow is on the wall.", .notPlain),
            ((stats.stdDev - PassportRules.bgUniformityMax) / PassportRules.bgUniformityMax,
             "Lighting on the wall is uneven — move to a flatter light.", .unevenLighting)
        ].filter { $0.margin > 0 }

        guard let worst = failures.max(by: { $0.margin < $1.margin }) else {
            return Result(ok: true, message: "Background looks plain and light.",
                          luminance: stats.luminance, reason: .plain,
                          outlierFraction: stats.outlierFraction)
        }
        return Result(ok: false, message: worst.message,
                      luminance: stats.luminance, reason: worst.reason,
                      outlierFraction: stats.outlierFraction)
    }

    /// Samples a grid of points and keeps those the mask marks as background.
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

        var samples: [Sample] = []
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

                samples.append(Sample(r: r, g: g, b: b))
            }
        }

        // A share-of-samples statistic is meaningless on a handful of points: at 20 samples
        // a 2% budget rounds to "no outlier at all is tolerated", so one grid point landing
        // on the feathered edge of the person mask would condemn the photo. Below this count
        // the analyser reports that it could not measure, rather than guessing.
        guard samples.count >= PassportRules.bgMinBackgroundSamples else { return nil }
        return stats(samples: samples)
    }
}
