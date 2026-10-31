import SwiftUI

struct PinTheoryAccountView: View {
    private enum AccountEditor: String, Identifiable {
        case name
        case password
        var id: String { rawValue }
    }

    let onHome: () -> Void
    @EnvironmentObject private var session: PinTheoryAccountSession
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var activeEditor: AccountEditor?
    @State private var details: PinTheoryAccountDetails?
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var confirmsAccountDeletion = false
    @State private var isWorking = false
    @State private var isDeletingAccount = false
    @State private var notice: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PureLineHomeButton(onHome: onHome)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        PureLinePageHeader(title: L("Account"), subtitle: "")

                        if let details {
                            accountSummary(details)
                            nameManagement
                            if details.supportsEmailManagement {
                                passwordManagement
                            }
                            deleteAccountSection
                        } else if isWorking {
                            ProgressView("Loading account details…")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .pureLineCard()
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Account details are unavailable")
                                    .font(.headline)
                                Text(errorMessage ?? L("Connect to the internet and try again."))
                                    .font(.subheadline)
                                    .foregroundStyle(PureLineStyle.muted)
                                Button("Try again") { Task { await loadDetails() } }
                                    .buttonStyle(PureLinePrimaryButtonStyle(minimumHeight: 44))
                                    .disabled(isWorking)
                            }
                            .pureLineCard()
                        }

                        if let notice {
                            Label(notice, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(PureLineStyle.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .pureLineCard()
                        }
                        if let errorMessage, details != nil {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(PureLineStyle.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .pureLineCard()
                        }

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
        .overlay {
            if isDeletingAccount {
                deletionProgressOverlay
            }
        }
        .tint(PureLineStyle.accent)
        .task { await loadDetails() }
        .confirmationDialog("Sign out of Golf PinTheory?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { session.signOut() }
        } message: {
            Text("Your saved rounds and current round stay on this device for your account. Unsaved edits will be lost.")
        }
        .confirmationDialog("Permanently delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete my account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes your account and removes its saved golf data from this device. This cannot be undone.")
        }
        .sheet(item: $activeEditor) { editor in
            NavigationStack { editorForm(editor) }
                .tint(PureLineStyle.accent)
                .preferredColorScheme(.light)
        }
        .accessibilityIdentifier("account-screen")
    }

    private func accountSummary(_ details: PinTheoryAccountDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Account details", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            if let email = details.email, !email.isEmpty {
                detailRow(L("Email"), value: email)
                Text("Email addresses can’t be changed in the app. Contact support if you need help.")
                    .font(.footnote)
                    .foregroundStyle(PureLineStyle.muted)
            }
            if let pendingEmail = details.pendingEmail, !pendingEmail.isEmpty {
                Label("Email change awaiting confirmation: \(pendingEmail). Contact support before confirming it.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(PureLineStyle.muted)
            }
            detailRow(L("Sign-in method"), value: details.providers.map(providerName).joined(separator: ", "))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
    }

    private var nameManagement: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(L("Name"), subtitle: L("Optional"))
            HStack {
                Text(details?.displayName.isEmpty == false ? details!.displayName : L("Not set"))
                    .foregroundStyle(details?.displayName.isEmpty == false ? PureLineStyle.ink : PureLineStyle.muted)
                Spacer()
                Button("Edit") { activeEditor = .name }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isWorking)
                    .accessibilityIdentifier("account-edit-name")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
    }

    private var passwordManagement: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(L("Password"), subtitle: "")
            HStack {
                Text("••••••••")
                    .foregroundStyle(PureLineStyle.muted)
                Spacer()
                Button("Change") {
                    currentPassword = ""
                    newPassword = ""
                    confirmNewPassword = ""
                    activeEditor = .password
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isWorking)
                .accessibilityIdentifier("account-change-password")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
    }

    @ViewBuilder
    private func editorForm(_ editor: AccountEditor) -> some View {
        Form {
            if editor == .name {
                Section("Name") {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("account-first-name")
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("account-last-name")
                }
            } else {
                Section("Change password") {
                    SecureField("Current password", text: $currentPassword)
                        .textContentType(.password)
                        .accessibilityIdentifier("account-current-password")
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("account-new-password")
                    SecureField("Confirm new password", text: $confirmNewPassword)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("account-confirm-new-password")
                }
            }
        }
        .navigationTitle(editor == .name ? L("Edit name") : L("Change password"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { closeEditor() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        if editor == .name { await saveDisplayName() }
                        else { await changePassword() }
                    }
                }
                .disabled(isWorking || !canSave(editor))
                .accessibilityIdentifier(editor == .name ? "account-save-display-name" : "account-update-password")
            }
        }
    }

    private func canSave(_ editor: AccountEditor) -> Bool {
        if editor == .name {
            return firstName != (details?.firstName ?? "") || lastName != (details?.lastName ?? "")
        }
        return !currentPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmNewPassword
    }

    private func closeEditor() {
        activeEditor = nil
        currentPassword = ""
        newPassword = ""
        confirmNewPassword = ""
    }

    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(L("Delete account"), subtitle: L("Permanently remove your account and its data."))
            Text("This cannot be undone. Your online account and saved golf records on this device will be removed.")
                .font(.subheadline)
                .foregroundStyle(PureLineStyle.muted)
            if session.auth?.canRequestAccountDeletion == true {
                Toggle("I want to delete my account", isOn: $confirmsAccountDeletion)
                    .tint(.red)
                    .accessibilityIdentifier("account-confirm-delete-toggle")
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete account", systemImage: "trash")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
                }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .tint(.red)
                    .opacity(confirmsAccountDeletion ? 1 : 0.45)
                    .disabled(isWorking || !confirmsAccountDeletion)
                    .accessibilityIdentifier("account-delete")
            } else {
                Text("Account deletion is not available yet. Contact support if you need your account removed.")
                    .font(.footnote).foregroundStyle(PureLineStyle.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
    }

    private var deletionProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(PureLineStyle.accent)
                Text("Deleting your account…")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Please keep Golf PinTheory open. This may take a moment.")
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(PureLineStyle.line.opacity(0.7), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("account-deletion-progress")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .transition(.opacity)
        .zIndex(10)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(PureLineStyle.muted)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.subheadline)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(PureLineStyle.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func providerName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "email": L("Email")
        case "google": "Google"
        case "apple": "Apple"
        default: provider.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @MainActor
    private func loadDetails() async {
        guard details == nil, !isWorking else { return }
        if let cached = session.accountDetails {
            details = cached
            firstName = cached.firstName
            lastName = cached.lastName
        }
        guard let auth = session.auth else {
            if details == nil { errorMessage = L("Account service is unavailable.") }
            return
        }
        guard case .authenticated = auth.state else {
            if details == nil { errorMessage = L("Connect to the internet to load account details.") }
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            details = try await session.loadAccountDetails()
            firstName = details?.firstName ?? ""
            lastName = details?.lastName ?? ""
            errorMessage = nil
        } catch {
            if details == nil { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func perform(_ successMessage: String, action: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        notice = nil
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await action()
            notice = successMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func changePassword() async {
        await perform(L("Your password has been updated. Sign in on your other devices with the new password.")) {
            guard let auth = session.auth else { throw PinTheoryAuthError.authenticationRequired }
            try await auth.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            currentPassword = ""
            newPassword = ""
            confirmNewPassword = ""
            activeEditor = nil
        }
    }

    @MainActor
    private func saveDisplayName() async {
        await perform(L("Your display name has been saved.")) {
            let updated = try await session.updateAccountDisplayName(firstName: firstName, lastName: lastName)
            details = updated
            firstName = updated.firstName
            lastName = updated.lastName
            activeEditor = nil
        }
    }

    @MainActor
    private func deleteAccount() async {
        guard !isDeletingAccount else { return }
        guard confirmsAccountDeletion else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        await perform(L("Your account was deleted.")) {
            try await session.deleteAccount()
        }
    }
}