import SwiftUI

/// Screen 2 — document type select. MVP ships US Passport only; others shown as "soon".
enum DocumentType: String, CaseIterable, Identifiable {
    case usPassport = "US Passport"
    case usVisa = "US Visa / Green Card"
    case other = "Other country"

    var id: String { rawValue }
    var available: Bool { self == .usPassport }   // MVP scope
}

struct DocumentTypeView: View {
    @Binding var selected: DocumentType
    var onContinue: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            Text("What are you making?")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(DocumentType.allCases) { type in
                    Button {
                        if type.available { selected = type }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected == type ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(selected == type ? Brand.primary
                                                 : (type.available ? Color.secondary : Color.secondary.opacity(0.5)))
                            Text(type.rawValue)
                                .foregroundStyle(type.available ? Color.primary : Color.secondary)
                            Spacer()
                            if !type.available {
                                Text("soon")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 15)
                    }
                    .disabled(!type.available)
                    if type != DocumentType.allCases.last {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer()

            Button("Continue", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
}

#Preview {
    DocumentTypeView(selected: .constant(.usPassport))
}
