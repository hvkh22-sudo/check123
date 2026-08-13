import SwiftUI

/// The one document type this version checks.
///
/// `US Visa / Green Card` and `Other country` used to sit here greyed out with a "soon"
/// badge. They were removed: a promise with no date reads as an unfinished app, and the
/// rules engine has no per-country table behind it to make them real (see D-018).
enum DocumentType: String, CaseIterable, Identifiable {
    case usPassport = "US Passport"

    var id: String { rawValue }
}

/// Screen 2 — states what the app is about to check, before the user spends time on a photo.
///
/// This is the in-app half of the expectation-setting the App Store description does: the
/// listing is available worldwide because US citizens abroad renew US passports, so someone
/// who needs a 35x45 mm photo has to find out here, not after paying.
struct DocumentTypeView: View {
    var onContinue: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            Text("What are you making?")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Brand.primary)
                    Text(DocumentType.usPassport.rawValue)
                        .font(.headline)
                }
                Text("2 x 2 in · 51 x 51 mm · square")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("This version checks US passport photos only. Other countries use different sizes and head-height rules, and aren't supported yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button("Continue", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
}

#Preview {
    DocumentTypeView()
}
