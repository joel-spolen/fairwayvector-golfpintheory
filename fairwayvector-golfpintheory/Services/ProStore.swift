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
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
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
        isPro = active
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}
