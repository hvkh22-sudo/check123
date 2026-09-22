import SwiftUI

/// Screen 7 — done / next steps. Honest self-check of the things we can't verify + official link.
struct DoneView: View {
    /// Findings the review screen flagged and the user exported past anyway.
    ///
    /// This screen used to open with a green tick and "Your photo is ready" for every export —
    /// including one the review screen had just called "Not ready yet" and the export screen
    /// "It may be rejected". The last thing the user saw before leaving the app contradicted
    /// the two screens before it.
    var flagged: [String] = []
    var onRestart: () -> Void

    private var tint: Color { flagged.isEmpty ? Brand.pass : Brand.attention }
    /// A plain `String`, so `Button` takes its `StringProtocol` initialiser unambiguously.
    private var restartTitle: String { flagged.isEmpty ? "Make another" : "Take a new photo — free" }

    @State private var checks = [false, false, false, false]
    private let items = [
        "Glasses were off",
        "Taken in the last 6 months",
        "No filter / beauty / HDR",
        "Neutral expression"
    ]

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            ZStack {
                // Smaller when flagged: that screen carries an extra card and still has to
                // fit an iPhone SE without scrolling.
                let size: CGFloat = flagged.isEmpty ? 96 : 72
                Circle().fill(tint.opacity(0.12)).frame(width: size, height: size)
                Image(systemName: flagged.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: flagged.isEmpty ? 52 : 38))
                    .foregroundStyle(tint)
            }
            // The app has no photo-library code at all — `ShareLink` is the only delivery
            // path in the project and it reports no outcome — so it cannot know whether
            // anything was saved. It used to say so anyway, under a green tick, even when the
            // share sheet had never been opened. It states what it actually knows now.
            Text(flagged.isEmpty ? "Your photo is ready" : "Exported — but it may be rejected")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if !flagged.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(flagged, id: \.self) { finding in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Brand.attention)
                            Text(finding).font(.subheadline)
                        }
                    }
                    // True by construction: this screen is only reached from the unlocked
                    // branch of ExportView, and the purchase is a non-consumable.
                    Text("Export is already unlocked, so a new photo against a plain, light wall costs nothing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .card()
            }
            Text("Before you submit, confirm the things we can't check:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(items.indices, id: \.self) { i in
                    Button {
                        checks[i].toggle()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: checks[i] ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(checks[i] ? Brand.pass : Color.secondary)
                            Text(items[i]).foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
            }
            .card()

            Spacer()

            Link("Open official renewal guidance",
                 destination: URL(string: "https://travel.state.gov/content/travel/en/passports/how-apply/photos.html")!)
                .font(.subheadline)

            Button(restartTitle, action: onRestart)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .navigationTitle("Done")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Clean") {
    NavigationStack { DoneView(onRestart: {}) }
}

#Preview("Exported past a flag") {
    NavigationStack {
        DoneView(flagged: ["Background isn't plain — something is behind you, or a shadow is on the wall."],
                 onRestart: {})
    }
}
