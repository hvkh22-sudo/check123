import SwiftUI
import CoreImage
import UIKit

/// Screen 5 — assisted crop (the honest answer to R-A: Vision has no crown landmark, so the
/// user drags crown & chin guides and we measure head-height from THOSE lines). See UX_SPEC §5.
struct AssistedCropView: View {
    let image: CIImage?
    var onRecheck: (Double) -> Void

    @State private var crownY: CGFloat = 0.18
    @State private var chinY: CGFloat = 0.78

    var body: some View {
        VStack(spacing: 16) {
            Text("Drag the lines to the top of your head and your chin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GeometryReader { geo in
                ZStack {
                    if let ui = rendered {
                        Image(uiImage: ui).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                            .overlay(Text("No photo").foregroundStyle(.secondary))
                    }
                    guide(color: .blue, label: "Crown", frac: $crownY, size: geo.size)
                    guide(color: .green, label: "Chin", frac: $chinY, size: geo.size)
                }
                .coordinateSpace(name: "crop")
            }
            .frame(maxHeight: 360)

            HStack(spacing: 8) {
                Text("Head height: \(Int(headHeightPct))%").font(.headline)
                Image(systemName: inBand ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(inBand ? .green : .orange)
            }
            Text("Measured from your guides — target 50–69%")
                .font(.caption).foregroundStyle(.secondary)

            Spacer()

            Button {
                onRecheck(headHeightPct)
            } label: {
                Text("Re-check").font(.headline).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Adjust")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headHeightPct: Double { Double(abs(chinY - crownY)) * 100 }
    private var inBand: Bool { headHeightPct >= 50 && headHeightPct <= 69 }

    private func guide(color: Color, label: String, frac: Binding<CGFloat>, size: CGSize) -> some View {
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
        .frame(width: size.width)
        .position(x: size.width / 2, y: frac.wrappedValue * size.height)
        .gesture(
            DragGesture(coordinateSpace: .named("crop"))
                .onChanged { value in
                    frac.wrappedValue = min(max(value.location.y / size.height, 0), 1)
                }
        )
    }

    private var rendered: UIImage? {
        guard let image, !image.extent.isInfinite else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    NavigationStack { AssistedCropView(image: nil, onRecheck: { _ in }) }
}
