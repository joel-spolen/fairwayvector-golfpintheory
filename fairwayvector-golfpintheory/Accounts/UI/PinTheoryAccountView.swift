import SwiftUI

struct PinTheoryAccountView: View {
    let onHome: () -> Void
    @EnvironmentObject private var session: PinTheoryAccountSession
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PureLineHomeButton(onHome: onHome)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        PureLinePageHeader(title: "Account", subtitle: "Manage your sign-in.")
                        Label("Signed in", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pureLineCard()
                        Button("Sign out", role: .destructive) { confirmingSignOut = true }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("account-sign-out")
                    }
                    .padding(24)
                }
            }
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(PureLineStyle.accent)
        .confirmationDialog("Sign out of Golf PinTheory?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { session.signOut() }
        } message: {
            Text("Your saved rounds and current round stay on this device for your account. Unsaved edits will be lost.")
        }
        .accessibilityIdentifier("account-screen")
    }
}