import Foundation

/// Decides which single instruction the capture screen shows, given what the face checks
/// and the background check currently say.
///
/// This is pure so the ordering can be tested without a camera. The rule is that the user
/// only ever reads one instruction at a time: fixing your head is pointless if the app is
/// simultaneously shouting about the wall behind you.
enum LiveGuidance {

    /// Face problems come first because they are the ones the user can fix in place and
    /// the ones that actually block the shot. Background comes next: it is worth saying
    /// *while* they are still standing there, not after the shutter.
    static func primaryHint(faceHint: String?, backgroundHint: String?) -> String? {
        faceHint ?? backgroundHint
    }

    /// The background warning is only worth repeating underneath when the main line is
    /// already taken by a face instruction — otherwise it would say the same thing twice.
    static func secondaryWarning(faceHint: String?, backgroundHint: String?) -> String? {
        guard faceHint != nil else { return nil }
        return backgroundHint
    }

    /// Which way to move the phone when the face sits too high or too low in the frame.
    ///
    /// `faceMidY` is in Vision's normalised space, whose origin is the **bottom**-left of the
    /// upright image — the convention `VisionComplianceEngine` already relies on when it
    /// places the crop guides with `1 - boundingBox.maxY`. A large value therefore means the
    /// face is near the *top* of the picture, which is what happens when the phone is held
    /// below face height, and the fix is to raise it.
    ///
    /// Until 2026-09-22 the live coach returned the opposite instruction. Someone holding
    /// the phone at chest height was told to lower it, which pushed the face further up the
    /// frame and repeated the same instruction — a loop that reads as "the app doesn't
    /// work". It survived because the instruction table handed to the owner for QA-002
    /// never listed it, so no device test ever exercised it.
    static func verticalHint(faceMidY: Double) -> String? {
        guard faceMidY.isFinite else { return nil }
        let offset = faceMidY - 0.5
        guard abs(offset) > PassportRules.verticalCenteringTolerance else { return nil }
        return offset > 0 ? "Raise the camera" : "Lower the camera"
    }

    /// What the capture screen tells the user to do about the wall, or nil when there is
    /// nothing to say.
    ///
    /// The live screen used to show the analyser's report sentence — "Background isn't plain
    /// — something is behind you, or a shadow is on the wall." That describes a problem; the
    /// person holding the phone needs to know what to do about it, in the few words a capsule
    /// at the top of a camera view can carry. Each reason gets an instruction.
    ///
    /// When a "not plain" finding is strong enough that the review screen will refuse the
    /// photo (at or above `PassportRules.bgOutlierFractionHard`), the live line says so
    /// *before* the shutter, because retaking is cheapest while the user is still standing
    /// there. The grading is `VisionComplianceEngine.backgroundStatus(for:)` itself, so the
    /// two screens cannot drift apart. Too dark and too coloured always block; their lines
    /// already tell the user what to change.
    ///
    /// "Could not measure" gets its own line rather than silence. Silence turned the ring and
    /// the shutter green and put "Looks good — take the photo" over a wall nobody had looked
    /// at — the same "unknown reads as fine" shape fixed elsewhere. It does not lock the
    /// shutter: segmentation is unavailable on some devices and in poor light.
    static func backgroundInstruction(for result: BackgroundAnalyzer.Result) -> String? {
        switch result.reason {
        case .plain:
            return nil
        case .couldNotMeasure:
            return "Couldn't check the wall — make sure it's plain and light"
        case .notPlain:
            if VisionComplianceEngine.backgroundStatus(for: result) == .verifiedFail {
                return "This background would be rejected — stand against a plain, empty wall"
            }
            return "Something is behind you — move to a plain, empty wall"
        case .tooDark:
            return "The wall is too dark — find a white wall or add light"
        case .tooColoured:
            return "The wall has color — find a white or off-white wall"
        case .unevenLighting:
            return "Uneven light on the wall — face a window or a lamp"
        }
    }

    /// A bad background deliberately does **not** lock the shutter.
    ///
    /// Person segmentation is unavailable on some devices and degrades in poor light, so
    /// gating capture on it would let a failed measurement trap the user on a screen with
    /// no way forward. The post-capture compliance report still states the background
    /// result honestly; live coaching only warns.
    static func isReady(faceHint: String?) -> Bool {
        faceHint == nil
    }
}
