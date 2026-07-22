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

    /// Minimum Vision faceCaptureQuality to count as sharp (tune). 0.5 was too strict —
    /// ordinary in-focus phone selfies score ~0.4–0.55, so real photos were falsely
    /// rejected as "blurry"; a genuinely blurry frame scores well below this.
    static let sharpnessMin = 0.35

    // Background near-white, normalized (tune) — tolerant for off-white
    static let bgLuminanceMin = 0.88
    static let bgSaturationMax = 0.12

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
