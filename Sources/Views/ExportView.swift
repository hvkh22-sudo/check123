import SwiftUI
import CoreImage
import UIKit

/// Screen 6 — export / paywall.
///
/// The preview is free and is **not** watermarked; what the one-time non-consumable purchase
/// unlocks is the Save / Share control itself, which is absent until then rather than disabled.
///
/// This is a real StoreKit 2 purchase. An earlier version of this comment called the unlock a
/// placeholder to be wired up later, which was true once and would now read as an invitation to
/// delete the paywall.
struct ExportView: View {
    /// The captured photo and the guide positions. The crop is performed HERE, in the view
    /// that shows it — earlier it was computed a screen back and threaded through @State,
    /// and an occasional mismatch let an uncropped photo reach this screen with no reason.
    let source: CIImage?
    var crownY: CGFloat = 0
    var chinY: CGFloat = 0
    /// The face's horizontal midpoint; the square is centred on it. See `ExportPipeline.squareCrop`.
    var centerX: CGFloat = 0.5
    /// Findings the review screen showed as warnings and the user chose to go past. They
    /// are repeated here, on the screen that takes the money, because "Ready to export"
    /// under a green seal is an approval, and the app has not given one.
    var flagged: [String] = []
    var onDone: () -> Void
    var onRetake: () -> Void = {}

    @StateObject private var store = Store()
    @State private var isPurchasing = false
    @State private var renderedImage: UIImage?
    @State private var isCropped = false
    @State private var failureReason: String?
    @State private var preparing = true

    private var unlocked: Bool { store.purchased }

    /// Extracted so it can also be offered before a photo exists — see the branch above.
    @ViewBuilder
    private var restoreButton: some View {
        Button("Restore purchase") {
            Task {
                isPurchasing = true
                await store.restore()
                isPurchasing = false
            }
        }
        .font(.footnote)
        .disabled(isPurchasing)
    }

    /// Omits the price entirely when the real product has not loaded, rather than quoting a
    /// currency the customer may not be paying in.
    private var purchaseButtonTitle: String {
        if isPurchasing { return "Contacting the App Store…" }
        guard let price = store.priceText else { return "Unlock & export" }
        return "Unlock & export — \(price)"
    }

    /// Crops the passport image off the main thread (the render is heavy GPU→CPU work),
    /// retrying a couple of times — createCGImage can fail transiently under memory pressure
    /// right after analysis. Only after real retries do we surface a failure.
    private func prepare() async {
        guard let source else {
            failureReason = "no photo to prepare"; isCropped = false; preparing = false; return
        }
        let cy = crownY, chy = chinY, cx = centerX
        let renderTask = Task.detached { () -> (image: UIImage?, reason: String?) in
            for attempt in 1...3 {
                guard !Task.isCancelled else { return (nil, "cancelled") }
                let r = ExportPipeline.make(from: source, crownY: cy, chinY: chy, centerX: cx)
                if let img = r.image { return (Self.render(img), nil) }
                if attempt == 3 { return (nil, r.reason) }
            }
            return (nil, "couldn't prepare the photo")
        }
        let outcome = await withTaskCancellationHandler(operation: {
            await renderTask.value
        }, onCancel: {
            renderTask.cancel()
        })
        guard !Task.isCancelled else { return }

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
            } else if isCropped, !flagged.isEmpty {
                // Cropped correctly, but the photo carries an open finding. The size line is
                // still true and still shown; the seal and the word "ready" are not.
                Label("It may be rejected", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                ForEach(flagged, id: \.self) { finding in
                    Text(finding)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let ui = renderedImage {
                    Text("\(Int(ui.size.width)) × \(Int(ui.size.height)) px · cropped to size")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button("Retake against a plain wall — checks are free", action: onRetake)
                    .font(.footnote)
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
                // No purchase until there is a prepared photo — but restore is not a purchase.
                // Apple requires a non-consumable's restore to be reachable, and it used to
                // live inside the branch below, so a returning customer who had reinstalled
                // had to shoot a photo that passed every check and cropped successfully before
                // any restore control existed at all.
                if !unlocked { restoreButton }
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
                // Done discards the photo — `onDone` clears the session. `ShareLink` gives
                // no completion callback, so the app cannot tell whether the user actually
                // saved anything first. The label therefore asks the user to assert it rather
                // than the app assuming it.
                Button("I've saved it — done") {
                    renderedImage = nil
                    onDone()
                }
            } else {
                Button {
                    Task {
                        isPurchasing = true
                        _ = await store.purchase()
                        isPurchasing = false
                    }
                } label: {
                    Text(purchaseButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing)

                restoreButton

                Text("One-time · no subscription")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LegalLinksView()

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
            // Loading the product used to be sequenced behind `prepare()`, which is a
            // multi-second render with retries. Until it finished, `store.purchased` was
            // still false, so an existing owner was shown the paywall for something they had
            // already bought. Entitlement is not downstream of image rendering.
            async let entitlement: Void = store.load()
            await prepare()
            await entitlement
        }
        .onDisappear {
            renderedImage = nil
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
        ExportPipeline.renderUIImage(image)
    }
}

#Preview {
    NavigationStack { ExportView(source: nil, onDone: {}) }
}
