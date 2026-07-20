import Foundation
import Vision
import CoreImage

/// On-device compliance engine using Apple Vision. See ios/COMPLIANCE_ENGINE_SPEC.md.
/// Implements the face/geometry checks. Head-height stays "assisted" (Vision has no crown
/// landmark → the crop guides measure it); background/glasses/edit stay user-confirm for now.
/// Thresholds are initial guesses to CALIBRATE on a real device against a labeled sample set.
struct VisionComplianceEngine: ComplianceEngine {
    let engineVersion = "0.2-vision"

    func analyze(_ image: CIImage) async -> ComplianceReport {
        let landmarksReq = VNDetectFaceLandmarksRequest()
        let qualityReq = VNDetectFaceCaptureQualityRequest()

        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([landmarksReq, qualityReq])
        } catch {
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
        let maxTilt = max(abs(degrees(face.roll)), abs(degrees(face.yaw)))
        results.append(RuleResult(
            id: "head.tilt",
            status: maxTilt <= 8 ? .verifiedPass : .verifiedFail,
            measured: maxTilt, unit: "°",
            message: maxTilt <= 8 ? "Head is straight." : "Face the camera straight — you're tilted \(Int(maxTilt))°."))

        // Centering (bounding-box mid-x)
        let cx = face.boundingBox.midX
        let centered = abs(cx - 0.5) <= 0.10
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
                status: minOpen >= 0.22 ? .verifiedPass : .verifiedFail,
                measured: nil, unit: nil,
                message: minOpen >= 0.22 ? "Both eyes open." : "Keep both eyes open."))
        } else {
            results.append(RuleResult(id: "face.eyesopen", status: .confirm, measured: nil, unit: nil,
                                      message: "Couldn't measure eyes — make sure both are open."))
        }

        // Sharpness (face capture quality)
        if let q = qualityReq.results?.first?.faceCaptureQuality {
            results.append(RuleResult(
                id: "img.sharp",
                status: q >= 0.5 ? .verifiedPass : .verifiedFail,
                measured: Double(q) * 100, unit: "%",
                message: q >= 0.5 ? "Photo is sharp." : "Looks blurry or low quality — retake."))
        }

        // Head height — assisted. Vision has no crown landmark, so this is an estimate
        // that reads low until PassportRules.crownExtensionFactor is calibrated (spike R-A).
        let headPct = PassportRules.estimatedHeadHeightPct(
            faceBoxHeightFraction: Double(face.boundingBox.height))
        results.append(RuleResult(
            id: "head.height", status: .assisted,
            measured: headPct, unit: "%",
            message: PassportRules.isHeadHeightCalibrated
                ? "Head size — align the crown and chin guides to confirm."
                : "Head size can't be measured automatically — align the crown and chin guides."))

        // Not machine-verifiable → honest user-confirm items
        results.append(RuleResult(id: "bg.plain", status: .confirm, measured: nil, unit: nil,
                                  message: "Is the background a plain, light, shadow-free wall?"))
        results.append(RuleResult(id: "face.glasses", status: .confirm, measured: nil, unit: nil,
                                  message: "Confirm your glasses are off."))
        results.append(RuleResult(id: "meta.unedited", status: .confirm, measured: nil, unit: nil,
                                  message: "No filters, beauty, or AI edits (they get rejected)."))

        return report(results)
    }

    // MARK: - helpers

    private func report(_ r: [RuleResult]) -> ComplianceReport {
        ComplianceReport(results: r, engineVersion: engineVersion)
    }

    private func degrees(_ radians: NSNumber?) -> Double {
        guard let r = radians?.doubleValue else { return 0 }
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
