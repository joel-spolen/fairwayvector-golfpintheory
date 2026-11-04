import StoreKit
import SwiftUI

/// Small "PRO" tag next to anything that needs Golf PinTheory Pro.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "PRO")
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(PureLineStyle.canvas)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PureLineStyle.accent, in: Capsule())
            .accessibilityLabel(Text(verbatim: "Pro"))
    }
}

struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss

    private let benefits: [(symbol: String, text: String)] = [
        ("scope", L("Club advice, wind and elevation for every shot")),
        ("square.grid.3x3.fill", L("Move the pin and read the green's slope, in 2D and 3D")),
        ("chart.bar.xaxis", L("Advanced statistics and handicap predictions")),
        ("chart.xyaxis.line", L("Trajectory and Wedge Matrix tools")),
        ("icloud", L("Sync across your devices")),
    ]

    var body: some View {
        SubscriptionStoreView(productIDs: ProStore.productIDs) {
            VStack(alignment: .leading, spacing: 18) {
                Text(verbatim: "Golf PinTheory Pro")
                    .font(.largeTitle.weight(.semibold)).tracking(-0.6)
                    .foregroundStyle(PureLineStyle.ink)
                ForEach(benefits, id: \.text) { benefit in
                    Label {
                        Text(benefit.text).foregroundStyle(PureLineStyle.ink)
                    } icon: {
                        Image(systemName: benefit.symbol).foregroundStyle(PureLineStyle.accent)
                    }
                    .font(.subheadline)
                }
                Text("Playing rounds, GPS distances, scorecards and handicap tracking stay free.")
                    .font(.footnote)
                    .foregroundStyle(PureLineStyle.muted)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(PureLineStyle.canvas, for: .subscriptionStoreFullHeight)
        }
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .subscriptionStorePolicyDestination(url: URL(string: "https://golfpintheory.com/terms-of-service/")!, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: URL(string: "https://golfpintheory.com/privacy-policy/")!, for: .privacyPolicy)
        .tint(PureLineStyle.accent)
        .onInAppPurchaseCompletion { _, result in
            await ProStore.shared.refresh()
            if case .success(.success) = result { dismiss() }
        }
        .preferredColorScheme(.light)
    }
}

/// Shown instead of a Pro screen for free users, with a way to unlock it.
struct ProLockedView: View {
    let title: String
    @State private var showingPaywall = false

    var body: some View {
        ContentUnavailableView {
            Label {
                HStack(spacing: 8) {
                    Text(title)
                    ProBadge()
                }
            } icon: {
                Image(systemName: "lock")
            }
        } description: {
            Text("This is part of Golf PinTheory Pro.")
        } actions: {
            Button(L("Unlock Pro")) { showingPaywall = true }
                .buttonStyle(PureLinePrimaryButtonStyle(fillsWidth: false, minimumHeight: 48, horizontalPadding: 28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PureLineStyle.canvas)
        .sheet(isPresented: $showingPaywall) { ProPaywallView() }
    }
}
