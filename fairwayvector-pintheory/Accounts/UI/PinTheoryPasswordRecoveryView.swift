import SwiftUI

/// Restricted, identity-free credential update. Root owns this route and the
/// signed-out destination; this view never opens account data or handles tokens.
@MainActor
struct PinTheoryPasswordRecoveryView: View {
    @ObservedObject private var auth: PinTheoryAuthService
    @State private var password = ""
    @State private var confirmation = ""
    @State private var localError: String?
    @State private var operation: Task<Void, Never>?
    @State private var generation: UInt64 = 0
    @State private var confirmingCancel = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case password, confirmation }

    init(auth: PinTheoryAuthService) { self.auth = auth }

    private var unavailable: Bool {
        auth.isBusy || operation != nil || auth.state != .passwordRecovery
    }
    private var validPassword: Bool { password.count >= 8 && password == confirmation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "lock.rotation")
                    .font(.largeTitle.weight(.light)).foregroundStyle(PureLineStyle.accent)
                    .accessibilityHidden(true)
                Text("Choose a new password").font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Save your new password, then sign in again with your email address and new password. This screen does not open your account or golf records.")
                    .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    Text("New password").font(.subheadline.weight(.medium))
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .password)
                        .padding(14)
                        .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PureLineStyle.line) }
                        .disabled(unavailable)
                        .accessibilityIdentifier("account-recovery-password")
                        .onSubmit { focusedField = .confirmation }
                    Text("Confirm new password").font(.subheadline.weight(.medium))
                    SecureField("Confirm new password", text: $confirmation)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focusedField, equals: .confirmation)
                        .padding(14)
                        .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PureLineStyle.line) }
                        .disabled(unavailable)
                        .accessibilityIdentifier("account-recovery-confirm-password")
                        .onSubmit { savePassword() }
                    Text("Use at least 8 characters. The account service may require a stronger password.")
                        .font(.footnote).foregroundStyle(PureLineStyle.muted)
                    if !confirmation.isEmpty && password != confirmation {
                        Text("Passwords do not match.").font(.footnote)
                    }
                }

                Button { savePassword() } label: {
                    Text("Save password").padding(.horizontal, 16).padding(.vertical, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(PureLinePrimaryButtonStyle())
                .disabled(unavailable || !validPassword)
                .accessibilityIdentifier("account-recovery-save")

                if auth.isBusy || operation != nil {
                    ProgressView("Completing password recovery…")
                }
                if let localError {
                    Text(localError).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account-recovery-error")
                }
                Button("Cancel password reset", role: .destructive) {
                    focusedField = nil
                    confirmingCancel = true
                }
                .frame(minHeight: 44)
                .disabled(unavailable)
                .accessibilityIdentifier("account-recovery-cancel")

                Text("Golf records remain on this device. Account sync is not connected yet; changing your password does not back up or transfer your records.")
                    .font(.footnote).foregroundStyle(PureLineStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .pureLineCard()
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PureLineStyle.canvas.ignoresSafeArea())
        .foregroundStyle(PureLineStyle.ink)
        .tint(PureLineStyle.accent)
        .preferredColorScheme(.light)
        .confirmationDialog("Cancel password reset?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel password reset", role: .destructive) { cancelRecovery() }
            Button("Keep resetting", role: .cancel) { }
        } message: {
            Text("This clears local sign-in credentials, not your golf records. You’ll return to sign in and can request another reset email. It does not sign out other devices.")
        }
        .onAppear { showServiceError() }
        .onChange(of: auth.lastError) { _, _ in
            if operation == nil { showServiceError() }
        }
        .onDisappear {
            generation &+= 1
            operation?.cancel()
            operation = nil
            clearPasswords()
        }
    }

    private func clearPasswords() {
        password = ""
        confirmation = ""
        focusedField = nil
    }

    private func showServiceError() {
        guard auth.state == .passwordRecovery,
              let error = auth.lastError, error != .cancelled else { return }
        localError = error.localizedDescription
    }

    private func savePassword() {
        guard !unavailable, validPassword else { return }
        let submittedPassword = password // Never trim a password.
        focusedField = nil
        localError = nil
        generation &+= 1
        let ticket = generation
        operation = Task { @MainActor in
            defer { if generation == ticket { operation = nil } }
            do {
                try Task.checkCancellation()
                try await auth.completePasswordReset(password: submittedPassword)
                guard generation == ticket, !Task.isCancelled else { return }
                clearPasswords()
                // Service publishes signedOut; root shows the login success note.
            } catch {
                guard generation == ticket, !Task.isCancelled,
                      error as? PinTheoryAuthError != .cancelled,
                      !(error is CancellationError) else { return }
                clearPasswords()
                localError = (error as? PinTheoryAuthError)?.localizedDescription
                    ?? "Your password could not be updated. Please try again."
            }
        }
    }

    private func cancelRecovery() {
        guard !unavailable else { return }
        generation &+= 1
        operation?.cancel()
        operation = nil
        clearPasswords()
        localError = nil
        do {
            try auth.signOut()
            // Root observes signedOut and detaches all account-bound content.
        } catch {
            localError = (error as? PinTheoryAuthError)?.localizedDescription
                ?? "Local sign-in credentials could not be cleared. Please try again."
        }
    }
}