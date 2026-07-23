import SwiftUI

/// Screen 7 — done / next steps. Honest self-check of the things we can't verify + official link.
struct DoneView: View {
    var onRestart: () -> Void

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
                Circle().fill(Brand.pass.opacity(0.12)).frame(width: 96, height: 96)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Brand.pass)
            }
            Text("Saved to your photos")
                .font(.title2.bold())
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

            Button("Make another", action: onRestart)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .navigationTitle("Done")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { DoneView(onRestart: {}) }
}
