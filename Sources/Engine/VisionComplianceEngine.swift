import Foundation
import Vision
import CoreImage

/// On-device compliance engine using Apple Vision. See ios/COMPLIANCE_ENGINE_SPEC.md.
/// Implements the face/geometry checks. Head-height stays "assisted" (Vision has no crown
/// landmark → the crop guides measure it); background/glasses/edit stay user-confirm for now.
/// Thresholds are initial guesses to CALIBRATE on a real device against a labeled sample set.
struct VisionComplianceEngine: ComplianceEngine {

    /// Grades a background finding by how much the measurement can be trusted.
    ///
    /// A hard failure blocks the export — `ComplianceReviewView` disables its button while any
    /// rule is a verified failure, deliberately, because an honest checker cannot sell an
    /// export for a photo it has just called non-compliant. Brightness and colour earn that:
    /// they are means over the whole background and they behave predictably.
    ///
    /// "Not plain" does not, and a real device showed why. It leans on a person mask, on a
    /// threshold not yet calibrated against real photographs, and it cannot tell an object
    /// from the subject's own shadow. On 2026-08-23 it correctly spotted a shadow on the
    /// owner's wall — and left him unable to continue in his own home, in an app whose live
    /// camera screen already treats the very same measurement as advice rather than a lock.
    /// It is advice here too now: the report still states the finding plainly, and the person
    /// holding the phone decides whether to retake.
    static func backgroundStatus(for reason: BackgroundAnalyzer.Reason) -> RuleStatus {
        switch reason {
        case .plain:
            return .verifiedPass
        case .tooDark, .tooColoured:
            return .verifiedFail
        case .notPlain, .unevenLighting, .couldNotMeasure:
            return .confirm
        }
    }

    /// The same grading, with one more tier: a "not plain" finding whose measured share of
    /// foreign samples is large is a verified failure, not advice.
    ///
    /// The advisory grade above exists because the statistic cannot tell a shadow from an
    /// object, and a soft shadow must not trap a user. It was never meant to wave through a
    /// coat and a bed rail — which is what a device did on 2026-09-14: the report said
    /// "isn't plain", the screen said "passed", and the export sold. Above
    /// `PassportRules.bgOutlierFractionHard` there is no shadow story left to tell.
    static func backgroundStatus(for result: BackgroundAnalyzer.Result) -> RuleStatus {
        if result.reason == .notPlain,
           let share = result.outlierFraction, share.isFinite,
           share >= PassportRules.bgOutlierFractionHard {
            return .verifiedFail
        }
        return backgroundStatus(for: result.reason)
    }

    /// What number to print under the background line, and its unit.
    ///
    /// The row used to show mean brightness for every reason, so a wall flagged for having
    /// a coat on it read "74%" — a number that described the wall's brightness and nothing
    /// about the coat. For a "not plain" finding the share of foreign samples is the fact
    /// that decided the verdict, and it is also the number calibration needs.
    static func backgroundMeasure(for result: BackgroundAnalyzer.Result) -> (value: Double?, unit: String?) {
        if result.reason == .notPlain, let share = result.outlierFraction, share.isFinite {
            return (share * 100, "% of background")
        }
        guard let lum = result.luminance else { return (nil, nil) }
        return (lum * 100, "%")
    }

    /// Decides the head-tilt rule from the angles Vision reported.
    ///
    /// Pure and internal so the "not measured" path is testable without a camera. That path
    /// is where a false pass hid, and a false pass on tilt is one of the few defects that
    /// reaches the passport office rather than the user.
    static func tiltRule(rollDeg: Double?, yawDeg: Double?) -> RuleResult {
        // isFinite here as well as in the caller: this function is internal and total,
        // and a NaN reaching Int(...) in the failing branch below is a hard trap.
        guard let roll = rollDeg, let yaw = yawDeg, roll.isFinite, yaw.isFinite else {
            return RuleResult(id: "head.tilt", status: .confirm, measured: nil, unit: nil,
                              message: "Couldn't measure your head angle — check you're facing the camera straight.")
        }
        let maxTilt = max(abs(roll), abs(yaw))
        let ok = maxTilt <= PassportRules.rollToleranceDeg
        return RuleResult(
            id: "head.tilt",
            status: ok ? .verifiedPass : .verifiedFail,
            measured: maxTilt, unit: "°",
            // Safe from the trap the old clamp guarded against: a non-finite angle cannot
            // reach here, because `degreesOrNil` reports it as nil and it is handled above.
            message: ok ? "Head is straight." : "Face the camera straight — you're tilted \(Int(maxTilt))°.")
    }
    let engineVersion = "0.2-vision"

    func analyze(_ fullImage: CIImage) async -> ComplianceReport {
        let cancellation = VisionRequestCancellation()
        return await withTaskCancellationHandler(operation: {
            performAnalysis(fullImage, cancellation: cancellation)
        }, onCancel: {
            cancellation.cancelAll()
        })
    }

    private func performAnalysis(
        _ fullImage: CIImage,
        cancellation: VisionRequestCancellation
    ) -> ComplianceReport {
        // Analyse a small copy. Face/background fractions are resolution-independent, but
        // person segmentation is heavy — on a large photo it made the "Checking your photo"
        // screen look frozen. 768px keeps detection accurate while cutting analysis time.
        let image = fullImage.downscaled(maxDimension: 768)

        let landmarksReq = VNDetectFaceLandmarksRequest()
        let qualityReq = VNDetectFaceCaptureQualityRequest()
        cancellation.register(landmarksReq)
        cancellation.register(qualityReq)
        guard !Task.isCancelled else { return cancelledReport() }

        // `.up` is correct because both capture paths bake EXIF orientation into the
        // pixels before we get here (see CIImage.uprighted()).
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([landmarksReq, qualityReq])
        } catch {
            if Task.isCancelled { return cancelledReport() }
            return report([RuleResult(id: "engine.error", status: .verifiedFail, measured: nil, unit: nil,
                                      message: "Couldn't analyze the photo — please retake.")])
        }

        let faces = landmarksReq.results ?? []
        guard let face = faces.max(by: { $0.boundingBox.height < $1.boundingBox.height }) else {
            return report([RuleResult(id: "face.present", status: .verifiedFail, measured: nil, unit: nil,
                                      message: "No face detected — get the whole head in frame.")])
        }
        if faces.count > 1 {
            return report([RuleResult(id: "face.single", status: .verifiedFail, measured: nil, unit: nil,
                                      message: "More than one face detected — only you should be in frame.")])
        }

        var results: [RuleResult] = []

        // Tilt (roll/yaw in radians → degrees)
        results.append(Self.tiltRule(rollDeg: degreesOrNil(face.roll),
                                     yawDeg: degreesOrNil(face.yaw)))

        // Centering (bounding-box mid-x)
        let cx = face.boundingBox.midX
        let centered = abs(cx - 0.5) <= PassportRules.centeringTolerance
        results.append(RuleResult(
            id: "head.centered",
            status: centered ? .verifiedPass : .verifiedFail,
            measured: Double(abs(cx - 0.5)) * 100, unit: "%",
            message: centered ? "Face is centered." : "Center your face in the frame."))

        // Eyes open (openness proxy from eye landmark extents)
        if let le = eyeOpenness(face.landmarks?.leftEye), let re = eyeOpenness(face.landmarks?.rightEye) {
            let minOpen = min(le, re)
            results.append(RuleResult(
                id: "face.eyesopen",
                status: minOpen >= PassportRules.earThreshold ? .verifiedPass : .verifiedFail,
                measured: nil, unit: nil,
                message: minOpen >= PassportRules.earThreshold ? "Both eyes open." : "Keep both eyes open."))
        } else {
            results.append(RuleResult(id: "face.eyesopen", status: .confirm, measured: nil, unit: nil,
                                      message: "Couldn't measure eyes — make sure both are open."))
        }

        // Sharpness (face capture quality)
        if let q = qualityReq.results?.first?.faceCaptureQuality {
            let sharp = Double(q) >= PassportRules.sharpnessMin
            results.append(RuleResult(
                id: "img.sharp",
                status: sharp ? .verifiedPass : .verifiedFail,
                measured: Double(q) * 100, unit: "%",
                message: sharp ? "Photo is sharp." : "Looks blurry or low quality — retake."))
        } else {
            // Without an else the whole rule vanished from the report when Vision could not
            // score the face. `overall` is computed from the rules that are present, so a
            // blurry photo could reach `.pass` with the sharpness question never asked and
            // never shown to the user. An unmeasurable rule has to stay in the report.
            results.append(RuleResult(id: "img.sharp", status: .confirm, measured: nil, unit: nil,
                                      message: "Couldn't measure sharpness — check the photo is in focus."))
        }

        // Head height — assisted. Vision has no crown landmark, so this is an estimate
        // that reads low until PassportRules.crownExtensionFactor is calibrated (spike R-A).
        let headPct = PassportRules.estimatedHeadHeightPct(
            faceBoxHeightFraction: Double(face.boundingBox.height))
        results.append(RuleResult(
            id: "head.height", status: .assisted,
            measured: nil, unit: nil,
            message: "Head size — we'll frame it correctly on the next step."))

        // Background — now measured on-device (person segmentation), not self-reported.
        guard !Task.isCancelled else { return cancelledReport() }
        let bg = BackgroundAnalyzer.analyze(image, cancellation: cancellation)
        let bgMeasure = Self.backgroundMeasure(for: bg)
        results.append(RuleResult(
            id: "bg.plain",
            status: Self.backgroundStatus(for: bg),
            measured: bgMeasure.value, unit: bgMeasure.unit,
            message: bg.message))

        // Still honest user-confirm items (not machine-verifiable)
        results.append(RuleResult(id: "face.glasses", status: .confirm, measured: nil, unit: nil,
                                  message: "Confirm your glasses are off."))
        results.append(RuleResult(id: "meta.unedited", status: .confirm, measured: nil, unit: nil,
                                  message: "No filters, beauty, or AI edits (they get rejected)."))

        // Suggested guide positions so the Adjust screen starts placed, not blank. Vision's
        // box runs chin→hairline; the crown sits above it by ~35% of the box height.
        // Coordinates are bottom-left; convert to top-down fractions.
        let box = face.boundingBox
        let chinY = (1 - Double(box.minY)).clamped01()
        let crownY = (1 - Double(box.maxY) - 0.35 * Double(box.height)).clamped01()

        var out = report(results)
        out.suggestedChinY = chinY
        out.suggestedCrownY = crownY
        // Vision's x runs left to right like the export's CGImage space, so it needs no flip —
        // only y is bottom-up. Both are measured on the same upright image.
        out.suggestedCenterX = Double(box.midX).clamped01()
        return out
    }

    // MARK: - helpers

    private func report(_ r: [RuleResult]) -> ComplianceReport {
        ComplianceReport(results: r, engineVersion: engineVersion)
    }

    private func cancelledReport() -> ComplianceReport {
        report([RuleResult(id: "engine.cancelled", status: .verifiedFail,
                           measured: nil, unit: nil,
                           message: "Photo checking was cancelled.")])
    }

    // (clamp helper defined at file scope below)

    /// Vision can return a missing or present-but-NaN roll/yaw on extreme or degenerate
    /// detections. This reports that as nil rather than as an angle.
    ///
    /// It used to clamp to 0, which kept a NaN out of `Int(...)` — a real runtime trap — but
    /// paid for it by turning "not measured" into "0°", and 0° passes the tilt rule. The
    /// degenerate detections Vision warns about are exactly the extreme head positions the
    /// rule exists to catch, so the failure mode and the fallback were correlated: the
    /// harder the head was tilted, the likelier the app was to call it straight.
    private func degreesOrNil(_ radians: NSNumber?) -> Double? {
        guard let r = radians?.doubleValue, r.isFinite else { return nil }
        return r * 180.0 / Double.pi
    }

    /// Openness proxy: vertical extent / horizontal extent of the eye's landmark points.
    private func eyeOpenness(_ region: VNFaceLandmarkRegion2D?) -> Double? {
        guard let pts = region?.normalizedPoints, pts.count >= 4 else { return nil }
        let xs = pts.map { Double($0.x) }
        let ys = pts.map { Double($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(), maxX - minX > 0 else { return nil }
        return (maxY - minY) / (maxX - minX)
    }
}

private extension Double {
    /// Clamps to the 0...1 fraction range used for guide positions.
    func clamped01() -> Double { Swift.min(Swift.max(self, 0), 1) }
}
