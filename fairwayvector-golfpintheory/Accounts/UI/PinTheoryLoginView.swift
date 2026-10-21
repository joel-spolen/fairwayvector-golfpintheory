import SwiftUI
import AuthenticationServices

/// Root owns restoration, callback routing and account-data opening. Google
/// callbacks return directly to the service through the actual-window broker.
@MainActor
struct PinTheoryLoginView: View {
    @ObservedObject private var auth: PinTheoryAuthService
    @StateObject private var browser: PinTheoryWebAuthenticationBroker
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var mode: Mode = .signIn
    @State private var confirmationEmail: String?
    @State private var lastSendAttempt: Date?
    @State private var notice: String?
    @State private var localError: String?
    @State private var operation: Task<Void, Never>?
    @State private var generation: UInt64 = 0
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, password, confirmation }
    private enum Mode { case signIn, createAccount, forgotPassword }
    private enum Action { case google, signIn, createAccount, resetPassword, resendConfirmation }

    init(auth: PinTheoryAuthService, notice: String? = nil) {
        self.init(auth: auth, browser: PinTheoryWebAuthenticationBroker(), notice: notice)
    }

    /// Root may retain the broker to cancel browser presentation during logout.
    /// After recovery, root can pass a transient password-updated notice here.
    init(auth: PinTheoryAuthService, browser: PinTheoryWebAuthenticationBroker, notice: String? = nil) {
        self.auth = auth
        _browser = StateObject(wrappedValue: browser)
        _notice = State(initialValue: notice)
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validEmail: Bool {
        let value = trimmedEmail
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard !value.contains(where: { $0.isWhitespace }), parts.count == 2,
              !parts[0].isEmpty else { return false }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domain.count >= 2 && domain.allSatisfy { !$0.isEmpty }
    }
    private var unavailable: Bool { auth.isBusy || operation != nil || auth.state != .signedOut }
    private var validSubmission: Bool {
        guard validEmail else { return false }
        switch mode {
        case .signIn: return !password.isEmpty
        case .createAccount: return password.count >= 8 && password == confirmation
        case .forgotPassword: return true
        }
    }
    private var submitTitle: String {
        switch mode {
        case .signIn: return "Sign in"
        case .createAccount: return "Create account"
        case .forgotPassword: return "Send password reset email"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Image("icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                        .accessibilityHidden(true)
                    Text("Golf PinTheory").font(.largeTitle.weight(.semibold)).tracking(-0.6)
                        .accessibilityAddTraits(.isHeader)
                    Text("Sign in to continue").font(.headline).padding(.top, 8)
                }

                Button { start(.google) } label: {
                    HStack(spacing: 12) {
                        Image("GoogleSignInLogo")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Text("Sign in with Google")
                            .font(.system(size: 14, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(red: 0.45, green: 0.47, blue: 0.46), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .opacity(unavailable || !browser.hasPresentationAnchor ? 0.5 : 1)
                .disabled(unavailable || !browser.hasPresentationAnchor)
                .accessibilityIdentifier("account-google-sign-in")

                // Presentation placeholder only: no Apple authorization or token exchange.
                SignInWithAppleButton(.signIn, onRequest: { _ in }, onCompletion: { _ in })
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .disabled(true)
                    .accessibilityLabel("Sign in with Apple, not available yet")
                    .accessibilityIdentifier("account-apple-sign-in-placeholder")

                HStack(spacing: 12) {
                    Rectangle().fill(PureLineStyle.line).frame(height: 1)
                    Text("or use email").font(.subheadline).foregroundStyle(PureLineStyle.muted)
                        .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                    Rectangle().fill(PureLineStyle.line).frame(height: 1)
                }
                emailForm

                if auth.isBusy || operation != nil {
                    ProgressView("Completing account request…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("account-sign-in-progress")
                }
                if operation != nil {
                    Button("Cancel request") { cancelOperation() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("account-cancel-sign-in")
                }
                if let notice {
                    Text(notice).font(.subheadline).foregroundStyle(PureLineStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account-email-inbox-notice")
                }
                if let localError {
                    Text(localError).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account-sign-in-error")
                }
                if let diagnostic = auth.lastNetworkDiagnostic, !auth.isBusy {
                    DisclosureGroup("Connection details") {
                        Text(diagnostic)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("account-network-diagnostic")
                }

                Link("Privacy policy", destination: URL(string: "https://golfpintheory.com/privacy-policy/")!)
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    .accessibilityIdentifier("account-privacy")
                Text("Golf PinTheory by FairwayVector").font(.caption).foregroundStyle(PureLineStyle.muted)
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
        .background { PinTheoryAuthenticationWindowReader(broker: browser).frame(width: 0, height: 0) }
        .onAppear { showServiceError() }
        .onDisappear {
            if auth.state == .passwordRecovery { detachOperation() }
            else { cancelOperation() }
        }
        .onChange(of: auth.state) { _, state in
            // Recovery is published BEFORE its SDK callback exchange finishes.
            if state == .passwordRecovery { detachOperation() }
            else if state != .signedOut { cancelOperation() }
        }
    }

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 4) {
                modeButton("Sign in", mode: .signIn)
                modeButton("Create account", mode: .createAccount)
            }
            .padding(4)
            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))

            if mode == .forgotPassword {
                Text("Reset your password").font(.headline)
                Text("Enter your email address. If password reset is available for it, you’ll receive an email. Open its link on this device and return to Golf PinTheory.")
                    .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Email address").font(.subheadline.weight(.medium))
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(mode == .forgotPassword ? .go : .next)
                .focused($focusedField, equals: .email)
                .padding(14)
                .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PureLineStyle.line) }
                .disabled(unavailable)
                .accessibilityLabel("Email address")
                .accessibilityIdentifier("account-email")
                .onSubmit {
                    if mode == .forgotPassword { submit() }
                    else { focusedField = .password }
                }

            if mode != .forgotPassword {
                Text("Password").font(.subheadline.weight(.medium))
                SecureField("Password", text: $password)
                    .textContentType(mode == .createAccount ? .newPassword : .password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(mode == .createAccount ? .next : .go)
                    .focused($focusedField, equals: .password)
                    .padding(14)
                    .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PureLineStyle.line) }
                    .disabled(unavailable)
                    .accessibilityIdentifier("account-password")
                    .onSubmit {
                        if mode == .createAccount { focusedField = .confirmation }
                        else { submit() }
                    }
            }
            if mode == .createAccount {
                Text("Confirm password").font(.subheadline.weight(.medium))
                SecureField("Confirm password", text: $confirmation)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .confirmation)
                    .padding(14)
                    .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PureLineStyle.line) }
                    .disabled(unavailable)
                    .accessibilityIdentifier("account-confirm-password")
                    .onSubmit { submit() }
                Text("Use at least 8 characters. The account service may require a stronger password.")
                    .font(.footnote).foregroundStyle(PureLineStyle.muted)
                if !confirmation.isEmpty && password != confirmation {
                    Text("Passwords do not match.").font(.footnote)
                }
            }

            Button { submit() } label: {
                Text(submitTitle).padding(.horizontal, 16).padding(.vertical, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(PureLinePrimaryButtonStyle())
            .disabled(unavailable || !validSubmission)
            .accessibilityIdentifier("account-password-submit")

            if mode == .signIn {
                Button("Forgot password?") { changeMode(.forgotPassword) }
                    .frame(minHeight: 44).disabled(unavailable)
                    .accessibilityIdentifier("account-forgot-password")
            } else if mode == .forgotPassword {
                Button("Back to sign in") { changeMode(.signIn) }
                    .frame(minHeight: 44).disabled(unavailable)
            }
            if let confirmationEmail {
                Text("Confirmation email: \(confirmationEmail)")
                    .font(.caption).foregroundStyle(PureLineStyle.muted)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = remainingCooldown(at: context.date)
                    Button(seconds > 0 ? "Resend confirmation in \(seconds)s" : "Resend confirmation email") {
                        start(.resendConfirmation)
                    }
                    .frame(minHeight: 44)
                    .disabled(unavailable || seconds > 0)
                    .accessibilityIdentifier("account-resend-confirmation")
                }
            }
        }
    }

    private func modeButton(_ title: String, mode target: Mode) -> some View {
        Button { changeMode(target) } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .background(mode == target ? PureLineStyle.canvas : PureLineStyle.surface,
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == target ? [.isSelected] : [])
        .disabled(unavailable)
    }

    private func changeMode(_ target: Mode) {
        guard !unavailable, mode != target else { return }
        clearPasswords()
        mode = target
        localError = nil
        notice = nil
        confirmationEmail = nil
        focusedField = .email
    }

    private func clearPasswords() {
        password = ""
        confirmation = ""
    }

    private func showServiceError() {
        guard auth.state == .signedOut, let error = auth.lastError, error != .cancelled else { return }
        localError = error.localizedDescription
    }

    private func submit() {
        switch mode {
        case .signIn: start(.signIn)
        case .createAccount: start(.createAccount)
        case .forgotPassword: start(.resetPassword)
        }
    }

    private func remainingCooldown(at date: Date) -> Int {
        guard let lastSendAttempt else { return 0 }
        return max(0, Int(ceil(60 - date.timeIntervalSince(lastSendAttempt))))
    }

    private func start(_ action: Action) {
        guard !unavailable else { return }
        let address = trimmedEmail
        let submittedPassword = password // Never trim any password.
        let resendEmail = confirmationEmail ?? address
        switch action {
        case .google:
            guard browser.hasPresentationAnchor else { return }
        case .signIn:
            guard mode == .signIn, validSubmission else { return }
        case .createAccount:
            guard mode == .createAccount, validSubmission else { return }
            lastSendAttempt = Date()
        case .resetPassword:
            guard mode == .forgotPassword, validEmail else { return }
        case .resendConfirmation:
            guard confirmationEmail != nil, remainingCooldown(at: Date()) == 0 else { return }
            // Failed resend attempts and alternate addresses also consume cooldown.
            lastSendAttempt = Date()
        }
        focusedField = nil
        localError = nil
        notice = nil
        generation &+= 1
        let ticket = generation
        operation = Task { @MainActor in
            defer { if generation == ticket { operation = nil } }
            do {
                try Task.checkCancellation()
                switch action {
                case .google:
                    try await auth.signInWithGoogle { [browser] url in
                        try await browser.authenticate(url)
                    }
                case .signIn:
                    try await auth.signInWithPassword(email: address, password: submittedPassword)
                case .createAccount:
                    let needsConfirmation = try await auth.signUpWithPassword(email: address, password: submittedPassword)
                    guard generation == ticket, !Task.isCancelled else { return }
                    if needsConfirmation {
                        lastSendAttempt = Date()
                        mode = .signIn
                        confirmationEmail = address
                        notice = "Check your inbox and spam folder for a confirmation email if account creation is available for this address. Open its link on this device and return to Golf PinTheory, then sign in if asked."
                    }
                case .resetPassword:
                    try await auth.sendPasswordReset(email: address)
                    guard generation == ticket, !Task.isCancelled else { return }
                    mode = .signIn
                    confirmationEmail = nil
                    notice = "If password reset is available for this address, an email has been sent. Check your inbox and spam folder. Open the reset link on this device and return to Golf PinTheory to choose a new password."
                case .resendConfirmation:
                    try await auth.resendSignupConfirmation(email: resendEmail)
                    guard generation == ticket, !Task.isCancelled else { return }
                    notice = "If confirmation is available for this address, a confirmation email has been sent. Open its link on this device and return to Golf PinTheory."
                }
                guard generation == ticket, !Task.isCancelled else { return }
                clearPasswords()
            } catch {
                guard generation == ticket, !Task.isCancelled,
                      error as? PinTheoryAuthError != .cancelled,
                      !(error is CancellationError) else { return }
                clearPasswords()
                // Never expose raw provider errors or account-existence details.
                localError = (error as? PinTheoryAuthError)?.localizedDescription
                    ?? "The account request could not be completed. Please try again."
            }
        }
    }

    private func cancelOperation() {
        generation &+= 1
        operation?.cancel()
        operation = nil
        browser.cancel()
        clearPasswords()
        focusedField = nil
        // No implicit signOut: root owns account lifecycle and safe state.
    }

    private func detachOperation() {
        generation &+= 1
        operation = nil
        clearPasswords()
        focusedField = nil
        // Do NOT cancel while the service exchanges a recovery callback.
    }
}