import Foundation
import StoreKit

/// StoreKit 2 purchase manager for the one-time export unlock (no subscription).
///
/// The product must be configured in App Store Connect (id below). Before it exists,
/// debug and TestFlight builds fall back to a free unlock so the flow stays testable.
/// That fallback is **never** available in an App Store build — see `allowsTestUnlock`.
@MainActor
final class Store: ObservableObject {
    static let exportProductID = "com.appstudio.passcheck.export"

    @Published var product: Product?
    @Published var purchased = false
    @Published var errorMessage: String?

    /// True only for builds that cannot reach real customers.
    ///
    /// App Store builds ship a receipt named `receipt`; TestFlight builds ship
    /// `sandboxReceipt`. A released build therefore always returns false, so a missing
    /// or unloadable product can never hand out a free export.
    private static var allowsTestUnlock: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    func load() async {
        do {
            product = try await Product.products(for: [Self.exportProductID]).first
        } catch {
            product = nil
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.exportProductID,
               transaction.revocationDate == nil {   // a refunded purchase loses access
                entitled = true
            }
        }
        // Never downgrade a test unlock — it has no transaction to find.
        if entitled || !unlockedForTesting { purchased = entitled }
    }

    /// Set only by the non-release fallback, so `refreshEntitlements()` doesn't revoke it.
    private var unlockedForTesting = false

    /// Attempts the purchase. Returns true when the export may be unlocked.
    func purchase() async -> Bool {
        errorMessage = nil

        guard let product else {
            if Self.allowsTestUnlock {
                unlockedForTesting = true
                purchased = true
                return true
            }
            errorMessage = "The store is unavailable right now. Please check your connection and try again."
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "That purchase could not be verified. You have not been charged."
                    return false
                }
                await transaction.finish()
                purchased = true
                return true
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Your purchase is awaiting approval. The export unlocks once it completes."
                return false
            @unknown default:
                errorMessage = "That purchase did not complete. You have not been charged."
                return false
            }
        } catch {
            errorMessage = "That purchase did not complete. You have not been charged."
            return false
        }
    }

    /// Restores a previous purchase on a new device or after reinstalling.
    func restore() async {
        errorMessage = nil
        try? await AppStore.sync()
        await refreshEntitlements()
        if !purchased {
            errorMessage = "No previous purchase was found for this Apple ID."
        }
    }

    var priceText: String { product?.displayPrice ?? "$4.99" }
}
