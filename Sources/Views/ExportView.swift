import SwiftUI
import CoreImage
import UIKit

/// Screen 6 — export / paywall. Free watermarked preview; one-time purchase to export clean.
/// Real StoreKit purchase is wired later; for now "unlock" is a placeholder that reveals the export.
struct ExportView: View {
    /// The captured photo and the guide positions. The crop is performed HERE, in the view
    /// that shows it — earlier it was computed a screen back and threaded through @State,
    /// and an occasional mismatch let an uncropped photo reach this screen with no reason.
    let source: CIImage?
    var crownY: CGFloat = 0
    var chinY: CGFloat = 0
    var onDone: () -> Void
    var onRetake: () -> Void = {}

    @StateObject private var store = Store()
    @State private var isPurchasing = false
    @State private var renderedImage: UIImage?
    @State private var isCropped = false
    @State private var failureReason: String?
    @State private var preparing = true

    private var unlocked: Bool { store.purchased }

    /// Crops the passport image off the main thread (the render is heavy GPU→CPU work),
    /// retrying a couple of times — createCGImage can fail transiently under memory pressure
    /// right after analysis. Only after real retries do we surface a failure.
    private func prepare() async {
        guard let source else {
            failureReason = "no photo to prepare"; isCropped = false; preparing = false; return
        }
        let cy = crownY, chy = chinY
        let outcome: (image: UIImage?, reason: String?) = await Task.detached {
            for attempt in 1...3 {
                let r = ExportPipeline.make(from: source, crownY: cy, chinY: chy)
                if let img = r.image { return (Self.render(img), nil) }
                if attempt == 3 { return (nil, r.reason) }
            }
            return (nil, "couldn't prepare the photo")
        }.value

        renderedImage = outcome.image
        isCropped = outcome.image != nil
        failureReason = isCropped ? nil : outcome.reason
        preparing = false
    }

    var body: some View {
        VStack(spacing: 18) {
            preview
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if preparing {
                ProgressView()
                Text("Preparing your photo…")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if isCropped {
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

            if preparing || !isCropped {
                EmptyView()   // no purchase until we have a prepared photo
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
            await prepare()
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
    NavigationStack { ExportView(source: nil, onDone: {}) }
}
