import SwiftUI

/// Content-only: usable in a Settings navigation destination or a login sheet.
/// The presenting container owns navigation and dismissal.
@MainActor
struct PinTheoryAccountPrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PureLinePageHeader(title: "Account & privacy", subtitle: "The essentials, at a glance.")

                section("Your account", text: "Your email is used to sign you in and send important account emails. Signing out does not delete your account.")

                section("Your golf data", text: "Your rounds and club setup are currently saved on this device only. They are not backed up online or available on your other devices.")

                section("Your location", text: "With your permission, your location helps show distances and conditions on the course. Some features share location information with their providers. You can change location access in your device’s Settings.")

                Text("Account deletion is not available in this version yet.")
                    .font(.footnote)
                    .foregroundStyle(PureLineStyle.muted)
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(PureLineStyle.canvas)
        .foregroundStyle(PureLineStyle.ink)
        .tint(PureLineStyle.accent)
        .preferredColorScheme(.light)
        .navigationTitle("Account & privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(text).font(.body).foregroundStyle(PureLineStyle.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}