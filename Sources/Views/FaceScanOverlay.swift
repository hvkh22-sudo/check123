import SwiftUI

/// The head guide: a green measuring grid inside the oval with a band that sweeps down it
/// while the checks are still failing, and a settled solid ring once they pass.
///
/// The motion is honest signalling, not decoration — it says "still measuring" the whole
/// time the shutter is locked, and stops the moment it unlocks, so the two states are
/// distinguishable at a glance without reading the instruction text.
struct FaceScanOverlay: View {
    var isReady: Bool
    var ovalSize = CGSize(width: 250, height: 330)

    /// Users who ask the system to reduce motion get the grid without the sweep; the
    /// ready/not-ready difference still reads through colour and line weight.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// -1 is just above the oval, 1 is just below it.
    @State private var sweepPhase: CGFloat = -1

    private var lineColor: Color {
        isReady ? .green : Color.green.opacity(0.7)
    }

    var body: some View {
        ZStack {
            grid
            if !isReady && !reduceMotion { sweepBand }
        }
        .frame(width: ovalSize.width, height: ovalSize.height)
        .clipShape(Ellipse())
        .overlay {
            Ellipse()
                .stroke(isReady ? Color.green : Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: isReady ? 4 : 3,
                                           dash: isReady ? [] : [10, 8]))
        }
        .frame(width: ovalSize.width, height: ovalSize.height)
        .animation(.easeInOut(duration: 0.2), value: isReady)
        .onAppear(perform: startSweep)
        .accessibilityHidden(true)   // the spoken instruction carries the same information
    }

    private var grid: some View {
        GeometryReader { geo in
            Path { path in
                let columns = 5
                let rows = 7
                for column in 1..<columns {
                    let x = geo.size.width * CGFloat(column) / CGFloat(columns)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                for row in 1..<rows {
                    let y = geo.size.height * CGFloat(row) / CGFloat(rows)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(lineColor.opacity(isReady ? 0.5 : 0.28), lineWidth: 1)
        }
    }

    private var sweepBand: some View {
        LinearGradient(
            colors: [.clear, Color.green.opacity(0.55), Color.green.opacity(0.75),
                     Color.green.opacity(0.55), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 64)
        .offset(y: sweepPhase * (ovalSize.height / 2 + 32))
        .blendMode(.plusLighter)
    }

    private func startSweep() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.9).repeatForever(autoreverses: false)) {
            sweepPhase = 1
        }
    }
}

/// An amber wash over everything *outside* the head oval, shown while the live background
/// check is unhappy. It points at the wall rather than the face, so the user can see which
/// half of the frame the warning text is about.
struct BackgroundWarningWash: View {
    var ovalSize = CGSize(width: 250, height: 330)

    var body: some View {
        Rectangle()
            .fill(Color.orange.opacity(0.16))
            .mask {
                Rectangle()
                    .overlay {
                        Ellipse()
                            .frame(width: ovalSize.width, height: ovalSize.height)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
