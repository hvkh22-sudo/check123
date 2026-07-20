import SwiftUI

/// Screen 1 — intro / honest disclosure. See design/UX_SPEC.md.
struct IntroView: View {
    var onStart: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Check your passport photo\nbefore you send it")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                Label("Checks against the official US rules", systemImage: "checklist")
                Label("Runs 100% on your phone", systemImage: "iphone")
                Label("No subscription", systemImage: "xmark.circle")
            }
            .font(.body)

            Text("We can't guarantee the government accepts it — that's always their call.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button(action: onStart) {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)

            // Precise on purpose: the app never uploads, but ShareLink hands the image
            // to whatever the user picks. Claiming more than the code does is a review risk.
            Text("PassCheck never uploads your photo. Sharing is always your choice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    IntroView()
}
