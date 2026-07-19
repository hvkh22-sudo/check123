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

    // Eyes-open EAR threshold (tune)
    static let earThreshold = 0.20

    // Background near-white, normalized (tune) — tolerant for off-white
    static let bgLuminanceMin = 0.88
    static let bgSaturationMax = 0.12

    /// Whether a measured head-height percentage is inside the compliant green band.
    static func headHeightInBand(_ pct: Double) -> Bool {
        pct >= headHeightMinPct && pct <= headHeightMaxPct
    }
}
