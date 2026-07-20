import SwiftUI
import CoreImage
import UIKit

/// Screen 6 — export / paywall. Free watermarked preview; one-time purchase to export clean.
/// Real StoreKit purchase is wired later; for now "unlock" is a placeholder that reveals the export.
struct ExportView: View {
    let image: CIImage?
    var onDone: () -> Void

    @StateObject private var store = Store()
    @State private var isPurchasing = false

    private var unlocked: Bool { store.purchased }

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
                    Task {
                        isPurchasing = true
                        _ = await store.purchase()
                        isPurchasing = false
                    }
                } label: {
                    Text(isPurchasing ? "Contacting the App Store…" : "Unlock & export — \(store.priceText)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing)

                Button("Restore purchase") {
                    Task {
                        isPurchasing = true
                        await store.restore()
                        isPurchasing = false
                    }
                }
                .font(.footnote)
                .disabled(isPurchasing)

                Text("One-time · no subscription")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = store.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding()
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
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
