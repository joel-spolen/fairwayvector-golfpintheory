import SwiftUI

/// Content-only: usable in a Settings navigation destination or a login sheet.
/// The presenting container owns navigation and dismissal.
@MainActor
struct PinTheoryAccountPrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PureLinePageHeader(title: L("Account & privacy"), subtitle: L("The essentials, at a glance."))

                section(L("Your account"), text: L("Your email is used to sign you in and send important account emails. Signing out does not delete your account."))

                section(L("Your golf data"), text: L("Your golf data is saved on this device by default. If you enable cloud sync in Settings, Golf PinTheory syncs your player name and low Handicap Index, saved scorecards, handicap-only entries, custom clubs/courses/tees, and wedge setup across devices. Active rounds, preferences, downloaded course catalogs, and course geometry stay on this device."))

                section(L("Your location"), text: L("With your permission, your location helps show distances and conditions on the course. Some features share location information with their providers. You can change location access in your device’s Settings."))

                Text("You can request account deletion from Account settings. Deletion removes the account and its server-side sync data; local data on this device is also cleared after the server confirms deletion.")
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