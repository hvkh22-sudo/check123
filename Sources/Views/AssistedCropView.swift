import SwiftUI
import CoreImage
import UIKit

/// Screen 5 — assisted crop (the honest answer to R-A: Vision has no crown landmark, so the
/// user drags crown & chin guides and we measure head-height from THOSE lines). See UX_SPEC §5.
///
/// The guides report positions as fractions of the **photo**, not of the container. The photo
/// is drawn with `.scaledToFit()`, so it is letterboxed whenever its aspect ratio differs from
/// the container's — measuring against the container would make every reading wrong by an
/// amount that varies with the photo. `imageRect(in:)` is what keeps the two in agreement.
struct AssistedCropView: View {
    let image: CIImage?
    /// Reports crown and chin as fractions of image height, measured top-down.
    var onRecheck: (CGFloat, CGFloat) -> Void

    @State private var crownY: CGFloat = 0.18
    @State private var chinY: CGFloat = 0.78
    /// Nothing is measured until the user actually places a guide, so the screen must not
    /// open showing a compliant-looking number for a measurement that hasn't happened.
    @State private var hasAdjusted = false
    @State private var rendered: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            Text("Drag the lines to the top of your head and your chin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GeometryReader { geo in
                let frame = imageRect(in: geo.size)
                ZStack {
                    if let ui = rendered {
                        Image(uiImage: ui).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                            .overlay(Text("No photo").foregroundStyle(.secondary))
                    }
                    guide(color: .blue, label: "Crown", frac: $crownY, frame: frame)
                    guide(color: .green, label: "Chin", frac: $chinY, frame: frame)
                }
                .coordinateSpace(name: "crop")
            }
            .frame(maxHeight: 360)

            if hasAdjusted {
                HStack(spacing: 8) {
                    Text("Head height: \(Int(headHeightPct))%").font(.headline)
                    Image(systemName: inBand ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(inBand ? .green : .orange)
                }
                Text("Measured from your guides — target 50–69%")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Head height: not measured yet")
                    .font(.headline).foregroundStyle(.secondary)
                Text("Place both lines to measure")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onRecheck(min(crownY, chinY), max(crownY, chinY))
            } label: {
                Text("Re-check").font(.headline).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasAdjusted)
        }
        .padding()
        .navigationTitle("Adjust")
        .navigationBarTitleDisplayMode(.inline)
        .task { rendered = Self.render(image) }
    }

    private var headHeightPct: Double { Double(abs(chinY - crownY)) * 100 }
    private var inBand: Bool { PassportRules.headHeightInBand(headHeightPct) }

    /// Where the photo is actually drawn inside the container, under `.scaledToFit()`.
    private func imageRect(in size: CGSize) -> CGRect {
        guard let ui = rendered, ui.size.width > 0, ui.size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / ui.size.width, size.height / ui.size.height)
        let drawn = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
        return CGRect(x: (size.width - drawn.width) / 2,
                      y: (size.height - drawn.height) / 2,
                      width: drawn.width, height: drawn.height)
    }

    private func guide(color: Color, label: String, frac: Binding<CGFloat>, frame: CGRect) -> some View {
        ZStack {
            Rectangle().fill(color).frame(height: 2)
            HStack {
                Text(label).font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color).foregroundStyle(.white).clipShape(Capsule())
                Spacer()
                Circle().fill(color).frame(width: 24, height: 24)
                    .overlay(Image(systemName: "arrow.up.and.down").font(.caption2).foregroundStyle(.white))
            }
        }
        .frame(width: frame.width)
        .position(x: frame.midX, y: frame.minY + frac.wrappedValue * frame.height)
        .gesture(
            DragGesture(coordinateSpace: .named("crop"))
                .onChanged { value in
                    guard frame.height > 0 else { return }
                    let f = (value.location.y - frame.minY) / frame.height
                    frac.wrappedValue = min(max(f, 0), 1)
                    hasAdjusted = true
                }
        )
        // VoiceOver cannot perform a drag, so expose the same control as an adjustable value.
        .accessibilityElement()
        .accessibilityLabel("\(label) guide")
        .accessibilityValue("\(Int(frac.wrappedValue * 100)) percent from the top")
        .accessibilityAdjustableAction { direction in
            let step: CGFloat = 0.01
            switch direction {
            case .increment: frac.wrappedValue = min(frac.wrappedValue + step, 1)
            case .decrement: frac.wrappedValue = max(frac.wrappedValue - step, 0)
            @unknown default: return
            }
            hasAdjusted = true
        }
    }

    /// Rendered once — as a computed property this rebuilt a full-resolution bitmap on
    /// every drag frame, which is exactly when the screen needs to stay responsive.
    private static func render(_ image: CIImage?) -> UIImage? {
        guard let image, !image.extent.isInfinite, !image.extent.isEmpty else { return nil }
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let cg = ctx.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    NavigationStack { AssistedCropView(image: nil, onRecheck: { _, _ in }) }
}
