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
                .padding(.top)

            VStack(spacing: 0) {
                ForEach(DocumentType.allCases) { type in
                    Button {
                        if type.available { selected = type }
                    } label: {
                        HStack {
                            Image(systemName: selected == type ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(type.available ? Color.accentColor : .secondary)
                            Text(type.rawValue)
                                .foregroundStyle(type.available ? .primary : .secondary)
                            Spacer()
                            if !type.available {
                                Text("soon").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .disabled(!type.available)
                    if type != DocumentType.allCases.last { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.12)))

            Spacer()

            Button(action: onContinue) {
                Text("Continue").font(.headline).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    DocumentTypeView(selected: .constant(.usPassport))
}
