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
