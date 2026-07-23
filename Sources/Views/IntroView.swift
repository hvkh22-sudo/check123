import SwiftUI

/// Screen 1 — intro / honest disclosure. See design/UX_SPEC.md.
struct IntroView: View {
    var onStart: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill(Brand.primarySoft)
                    .frame(width: 108, height: 108)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Brand.primary)
            }
            .padding(.bottom, 22)

            Text("Check your passport photo\nbefore you send it")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // The first real tester photographed his passport booklet instead of his face,
            // and thought he needed to own a US passport. Say plainly what to point the
            // camera at, and that this checks a photo rather than a document.
            Text("Take a selfie against a plain, light wall — we check it against the official US passport photo rules. You don't need a passport to use this.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 8)

            VStack(spacing: 12) {
                featureRow("checklist", "Checks against the official US rules")
                featureRow("iphone", "Runs 100% on your phone — nothing is uploaded")
                featureRow("creditcard", "No subscription — pay once, only to export")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(.top, 24)

            Spacer(minLength: 20)

            Button("Get started", action: onStart)
                .buttonStyle(PrimaryButtonStyle())

            Text("We can't guarantee the government accepts it — that's always their call.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private func featureRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Brand.primary)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    IntroView()
}
