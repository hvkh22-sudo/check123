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
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Saved")
                .font(.title.bold())
            Text("Before you submit, confirm the things we can't check:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(items.indices, id: \.self) { i in
                    Button {
                        checks[i].toggle()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: checks[i] ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checks[i] ? Color.accentColor : Color.secondary)
                            Text(items[i]).foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
            }
            .padding()

            Spacer()

            Link("Open official renewal guidance",
                 destination: URL(string: "https://travel.state.gov/content/travel/en/passports/how-apply/photos.html")!)

            Button("Make another", action: onRestart)
                .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Done")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { DoneView(onRestart: {}) }
}
