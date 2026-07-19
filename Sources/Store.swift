import Foundation
import StoreKit

/// StoreKit 2 purchase manager for the one-time export unlock (no subscription).
/// The product must be configured in App Store Connect (id below). Until then, `purchase()`
/// falls back to a test unlock so the flow is usable in TestFlight before the product exists.
@MainActor
final class Store: ObservableObject {
    static let exportProductID = "com.appstudio.passcheck.export"

    @Published var product: Product?
    @Published var purchased = false

    func load() async {
        product = try? await Product.products(for: [Self.exportProductID]).first
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.exportProductID {
                purchased = true
            }
        }
    }

    /// Attempts the purchase. Returns true on success. If no product is configured yet
    /// (App Store Connect setup pending), returns true so testing can proceed.
    func purchase() async -> Bool {
        guard let product else {
            purchased = true
            return true
        }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
                purchased = true
                return true
            }
            return false
        } catch {
            return false
        }
    }

    var priceText: String { product?.displayPrice ?? "$4.99" }
}
