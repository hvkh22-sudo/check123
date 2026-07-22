import SwiftUI
import CoreImage
import UIKit

/// Screen 6 — export / paywall. Free watermarked preview; one-time purchase to export clean.
/// Real StoreKit purchase is wired later; for now "unlock" is a placeholder that reveals the export.
struct ExportView: View {
    let image: CIImage?
    /// True when `image` is the cropped passport export. False means the crop failed and
    /// `image` is the untouched photo — we must never sell that as "correct size".
    var isCropped: Bool = true
    /// Short diagnostic shown when the crop failed, so a failure pinpoints its own cause.
    var failureReason: String? = nil
    var onDone: () -> Void
    var onRetake: () -> Void = {}

    @StateObject private var store = Store()
    @State private var isPurchasing = false
    @State private var renderedImage: UIImage?

    private var unlocked: Bool { store.purchased }

    var body: some View {
        VStack(spacing: 18) {
            preview
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if isCropped {
                Text("Ready to export")
                    .font(.title3.bold())
                Text("Cropped to the correct square size for the online renewal upload.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let ui = renderedImage {
                    // Show the real output size — reassures the user the file meets the
                    // 600–1200px passport requirement, and is our own proof it's correct.
                    Label("\(Int(ui.size.width)) × \(Int(ui.size.height)) px",
                          systemImage: "checkmark.seal.fill")
                        .font(.caption.monospaced())
                        .foregroundStyle(.green)
                }
            } else {
                Text("Couldn't prepare the photo")
                    .font(.title3.bold())
                Text("We couldn't crop this photo to passport size. Please retake it.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                if let failureReason {
                    Text(failureReason)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .textSelection(.enabled)
                }
                Button("Retake photo", action: onRetake)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }

            Spacer()

            if !isCropped {
                EmptyView()   // no purchase for a photo we couldn't prepare
            } else if unlocked {
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
        .task {
            renderedImage = Self.render(image)
            await store.load()
        }
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

    /// Rendered once into state. As a computed property this ran on every body pass —
    /// three full-resolution bitmaps per render, which can exhaust memory on large photos.
    private static func render(_ image: CIImage?) -> UIImage? {
        guard let image, !image.extent.isInfinite, !image.extent.isEmpty else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    NavigationStack { ExportView(image: nil, onDone: {}) }
}
