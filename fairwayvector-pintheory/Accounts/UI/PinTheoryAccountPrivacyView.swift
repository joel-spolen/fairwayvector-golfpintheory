import SwiftUI

/// Content-only: usable in a Settings navigation destination or a login sheet.
/// The presenting container owns navigation and dismissal.
@MainActor
struct PinTheoryAccountPrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PureLinePageHeader(title: "Account & privacy", subtitle: "PinTheory · prerelease account integration")

                section("Sign-in uses the network", text: "Supabase Auth manages your account identity, email address and sign-in session. Email/password sign-in sends your credentials over HTTPS to Supabase; the app does not save your password. Account creation and password reset use the configured email delivery service to send confirmation or reset links. Google sign-in opens Google's authorization flow; Google and Supabase process the identity information needed to sign you in, which can include your email and Google profile details. These services have their own privacy policies.")

                section("Golf records are still local", text: "Your saved rounds, handicap information, club setup and other golf records are stored locally on this device. They are not connected to account sync yet. Signing in does not upload these records or make them available on another device. Do not rely on this test integration as a cloud backup.")

                section("Session storage", text: "Sign-in credentials are kept in this device's Keychain. Signing out clears the local sign-in session; it does not delete your Supabase account or revoke all sessions on other devices.")

                section("Course, weather & location services", text: "Account sign-in is separate from the golf features' network requests. When used and configured, course search can contact Golf API or OpenStreetMap's Overpass service, maps use Apple Maps, weather uses Open-Meteo, and terrain uses GPXZ. Requests can include search terms, course identifiers or coordinates. GPXZ terrain requests may include your golfer position. Device location is used with your permission; provider availability, caches and development modes affect which requests are made. Signing in does not itself grant location permission.")

                section("Advertising & analytics", text: "PinTheory does not add advertising or analytics SDKs. This is not a promise that authentication, email, map or other service providers collect no operational data: they may process network information and logs under their own policies.")

                VStack(alignment: .leading, spacing: 8) {
                    Label("Test integration — not a public release", systemImage: "exclamationmark.shield")
                        .font(.headline)
                    Text("In-app account deletion is not available yet. Account deletion, provider configuration and the full release privacy disclosures must be completed before public release. Use this prerelease integration only with a test account and do not enter sensitive information.")
                        .font(.body)
                }
                .fixedSize(horizontal: false, vertical: true)
                .pureLineCard()
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