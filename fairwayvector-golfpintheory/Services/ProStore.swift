import Foundation
import Observation
import StoreKit

/// Golf PinTheory Pro: an auto-renewing subscription; everything else in the app is free.
@MainActor @Observable
final class ProStore {
    static let shared = ProStore()
    static let productIDs = ["pintheory.pro.yearly", "pintheory.pro.monthly"]

    private(set) var isPro = false
    private var updates: Task<Void, Never>?
    private var verifiedPurchaseExpirations: [String: Date] = [:]

    private init() {
        #if DEBUG
        // UI tests run as Pro unless they ask for the free version.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing") {
            isPro = !arguments.contains("-ui-testing-free")
            return
        }
        #endif
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.handle(transaction)
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            active = true
        }
        let now = Date.now
        verifiedPurchaseExpirations = verifiedPurchaseExpirations.filter { $0.value > now }
        isPro = active || !verifiedPurchaseExpirations.isEmpty
    }

    func completePurchase(_ result: Result<Product.PurchaseResult, Error>) async {
        guard case .success(.success(let verification)) = result,
              case .verified(let transaction) = verification,
              Self.productIDs.contains(transaction.productID) else {
            await refresh()
            return
        }
        await handle(transaction)
    }

    private func handle(_ transaction: Transaction) async {
        guard Self.productIDs.contains(transaction.productID) else {
            await transaction.finish()
            return
        }
        if transaction.revocationDate == nil,
           let expiration = transaction.expirationDate, expiration > .now {
            verifiedPurchaseExpirations[transaction.productID] = expiration
            isPro = true
        } else if transaction.revocationDate == nil, transaction.expirationDate == nil {
            verifiedPurchaseExpirations[transaction.productID] = .distantFuture
            isPro = true
        } else {
            verifiedPurchaseExpirations.removeValue(forKey: transaction.productID)
            await refresh()
        }
        await transaction.finish()
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}
