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
