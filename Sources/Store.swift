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

    private var updatesListener: Task<Void, Never>?

    init() {
        // StoreKit 2 requires a long-lived listener for transactions that arrive outside a
        // purchase() call: Ask-to-Buy approvals, pending purchases that later complete, or a
        // purchase made on another device. Without it, a charged customer stays locked.
        updatesListener = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    deinit { updatesListener?.cancel() }

    /// True only for builds that cannot reach real customers.
    ///
    /// App Store builds ship a receipt named `receipt`; TestFlight builds ship
    /// `sandboxReceipt`. A released build therefore always returns false, so a missing
    /// or unloadable product can never hand out a free export.
    ///
    /// **App Review also runs against the sandbox**, and therefore also takes this path. If
    /// the in-app purchase is not approved alongside the build, the reviewer is handed a free
    /// unlock, sees a working app, and approves it — while every paying customer meets
    /// "The store is unavailable right now". The gate protects revenue from leaking; it does
    /// not protect the launch from a store that never came up. See QA-B7.
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
                    // `.success` means the payment completed. Only the local signature check
                    // failed — a skewed device clock is the usual benign cause. Telling the
                    // customer they were not charged is the one thing that is certainly wrong,
                    // and it also sends them away from Restore, which is their actual way out.
                    errorMessage = "We couldn't verify that purchase on this device. If you were charged, tap Restore purchase — you won't be charged twice."
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
                errorMessage = "That purchase didn't complete. If you were charged, tap Restore purchase."
                return false
            }
        } catch {
            // A network error thrown after the payment sheet finished is not evidence that
            // nothing was charged, so this no longer says so.
            errorMessage = "That purchase didn't complete. If you were charged, tap Restore purchase."
            return false
        }
    }

    /// Restores a previous purchase on a new device or after reinstalling.
    func restore() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            // `try?` here reported every failed sync — no network, or the user dismissing the
            // Apple ID prompt this raises — as "you never bought this", which is a support
            // ticket and a one-star review rather than a transient error.
            errorMessage = "Couldn't reach the App Store to restore. Check your connection and try again."
            return
        }
        await refreshEntitlements()
        if !purchased {
            errorMessage = "No previous purchase was found for this Apple ID."
        }
    }

    /// Nil until the real product loads. The previous hardcoded "$4.99" fallback was shown
    /// to every storefront, so a customer paying in euros, pounds or shekels was quoted a
    /// price that is not theirs — for a product that, in that same state, cannot be bought
    /// at all. The button now omits the price rather than inventing one.
    var priceText: String? { product?.displayPrice }
}
