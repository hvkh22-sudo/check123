import Foundation

/// US passport photo spec as data (RulesProvider).
/// Source of truth: apps/passport-photo/ios/RULES_US_PASSPORT.md (verified from travel.state.gov, 2026-07).
/// HARD RULE (D-007): NO AI / background editing — crop, resize, straighten, honest levels only.
/// Thresholds marked "tune" are initial guesses to calibrate on the labeled sample set (R-A spike, qa/SAMPLE_SET_SPEC.md).
enum PassportRules {
    // Format / dimensions
    static let pixelMin = 600
    static let pixelMax = 1200
    static let aspectRatio = 1.0            // square 1:1

    // Head geometry — chin→crown as % of frame height (25–35 mm of 51 mm ≈ 50–69%)
    static let headHeightMinPct = 50.0
    static let headHeightMaxPct = 69.0

    // Tilt tolerances, degrees (tune)
    static let rollToleranceDeg = 6.0
    static let yawToleranceDeg = 6.0
    static let pitchToleranceDeg = 8.0

    /// Max distance of the face's horizontal midpoint from centre, as a fraction (tune).
    static let centeringTolerance = 0.10

    // Eyes-open EAR threshold (tune)
    static let earThreshold = 0.20

    /// Minimum Vision faceCaptureQuality to count as sharp (tune). Loosened from 0.5 → 0.35
    /// → 0.28: ordinary in-focus indoor selfies score ~0.3–0.55, so a higher bar falsely
    /// rejected good photos as "blurry/dark"; genuine motion blur scores well below 0.28.
    static let sharpnessMin = 0.28

    // Background near-white, normalized (tune) — tolerant for off-white walls and indoor
    // light. Loosened after real photos on a light (not pure-white) wall read as false
    // failures; a genuinely dark or coloured background still fails.
    static let bgLuminanceMin = 0.68
    static let bgSaturationMax = 0.18
    /// Max luminance spread across the background before it reads as non-uniform (shadows,
    /// objects). Loosened for tiled/textured walls with visible grout lines.
    ///
    /// This measures a *gradient*, not an object. Standard deviation averages a localised
    /// object into the wall around it: against a wall at 0.85, a black coat has to cover
    /// 7.7% of the sampled background before this trips, a mid-grey bed rail 15.7%, and
    /// anything at 0.50 luminance or lighter never trips it at any size. QA-002 on
    /// 2026-08-23 hit exactly that — a hanging coat and a bed rail were both passed.
    /// The outlier pair below is what catches objects; this stays for gradients.
    static let bgUniformityMax = 0.20

    /// How much more varied than the wall's own typical variation a sample must be before
    /// it counts as "not the wall".
    ///
    /// The threshold is this multiple of the median deviation, so it adapts: on a wall lit
    /// unevenly every sample drifts and the band widens with them, while on a flat wall the
    /// band collapses to the floor below and anything on the wall stands out.
    static let bgOutlierScale = 3.0

    /// The narrowest that band is ever allowed to get.
    ///
    /// This is the single most consequential number in the background check, and it is
    /// **not yet calibrated against real photographs**. It decides both halves of the
    /// trade-off: raise it and a beige door or a light wooden rail becomes invisible again,
    /// which is the false pass QA-002 caught on 2026-08-23; lower it and an ordinary tiled
    /// wall with visible grout starts failing, which is what the uniformity threshold above
    /// was once loosened to prevent. At 0.07 the check rejects a visibly tiled wall. That is
    /// a deliberate choice of the safer error — a false failure costs a retake, a false pass
    /// costs a rejected passport application — and it must be revisited against the owner's
    /// own photographs before release.
    static let bgOutlierFloor = 0.07

    /// Share of background samples allowed to be outliers before the background reads as
    /// not plain. Small, because a passport background must be empty: at 2% of a 40x40 grid
    /// this still tolerates a light switch, while catching a coat mostly hidden behind the
    /// head.
    static let bgOutlierFractionMax = 0.02

    /// Share of background samples beyond which "not plain" stops being advice and blocks.
    ///
    /// Below this the finding is shown as a warning the user can override, because the
    /// measurement cannot tell a soft shadow from a light switch and a false lock would
    /// trap someone in an ordinary room. At this share it is no longer a shadow: on
    /// 2026-09-14 a device passed a photo with a hanging coat and a bed rail filling a
    /// large part of the frame, and the app then sold an export of it under a green seal.
    /// A passport office rejects that photo every time, and an honest checker has to say
    /// so before the purchase, not after. Six times the advisory budget, so that a wall
    /// with a switch and a shadow still gets through as advice. **Not yet calibrated** —
    /// revisit against the owner's own photographs; the review screen now shows the
    /// measured share so that calibration can be read off a screenshot.
    static let bgOutlierFractionHard = 0.12

    /// Fewest background samples the outlier statistic will accept.
    ///
    /// A share is meaningless on a handful of points: at 20 samples a 2% budget rounds to
    /// tolerating no outlier at all, so one grid point catching the feathered edge of the
    /// person mask would condemn the photo. Below this the analyser says it could not
    /// measure instead of guessing.
    static let bgMinBackgroundSamples = 60

    /// Whether a measured head-height percentage is inside the compliant green band.
    static func headHeightInBand(_ pct: Double) -> Bool {
        pct >= headHeightMinPct && pct <= headHeightMaxPct
    }

    // MARK: - Head height calibration (spike R-A)

    /// Converts Vision's face bounding-box height into estimated chin-to-crown height.
    ///
    /// Vision's box stops near the hairline, so it systematically UNDER-measures the
    /// chin-to-crown distance the passport spec requires. This factor is the correction,
    /// and it is **not calibrated yet**: 1.0 means "report Vision's box unchanged".
    /// Derive the real value from labelled device photos (see `qa/SAMPLE_SET_SPEC.md`),
    /// then change only this constant — nothing else depends on the number.
    static let crownExtensionFactor = 1.0

    /// False until `crownExtensionFactor` is derived from real photos. While false the
    /// head-height rule must stay `.assisted` and must not be presented as a measurement.
    static var isHeadHeightCalibrated: Bool { crownExtensionFactor != 1.0 }

    /// Estimated chin-to-crown height as a percentage of frame height.
    /// - Parameter faceBoxHeightFraction: Vision bounding-box height, 0...1 of frame height.
    static func estimatedHeadHeightPct(faceBoxHeightFraction: Double) -> Double {
        let pct = faceBoxHeightFraction * crownExtensionFactor * 100
        return min(max(pct, 0), 100)
    }
}
