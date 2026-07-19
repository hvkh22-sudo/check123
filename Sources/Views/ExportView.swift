import SwiftUI
import CoreImage
import UIKit

/// Screen 6 — export / paywall. Free watermarked preview; one-time purchase to export clean.
/// Real StoreKit purchase is wired later; for now "unlock" is a placeholder that reveals the export.
struct ExportView: View {
    let image: CIImage?
    var onDone: () -> Void

    @State private var unlocked = false

    var body: some View {
        VStack(spacing: 18) {
            preview
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Ready to export")
                .font(.title3.bold())
            Text("Correct size for the online renewal upload.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            if unlocked {
                if let ui = renderedImage {
                    ShareLink(item: Image(uiImage: ui),
                              preview: SharePreview("Passport photo", image: Image(uiImage: ui))) {
                        Label("Save / Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Done", action: onDone)
            } else {
                Button {
                    unlocked = true   // TODO: StoreKit 2 one-time purchase
                } label: {
                    Text("Unlock & export — $4.99")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                Text("One-time · no subscription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var preview: some View {
        if let ui = renderedImage {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .overlay {
                    if !unlocked {
                        Text("PREVIEW")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white.opacity(0.5))
                            .rotationEffect(.degrees(-20))
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.15))
                .overlay(Text("No photo").foregroundStyle(.secondary))
        }
    }

    private var renderedImage: UIImage? {
        guard let image, !image.extent.isInfinite else { return nil }
        let context = CIContext()
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    NavigationStack { ExportView(image: nil, onDone: {}) }
}
