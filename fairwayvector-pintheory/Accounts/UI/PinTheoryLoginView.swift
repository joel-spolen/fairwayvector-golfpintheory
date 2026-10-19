import SwiftUI

/// Login presentation only. The app root owns restore(), callback routing and
/// account-data opening. Do not route this browser's callback through onOpenURL
/// as well; the browser returns it directly to signInWithGoogle.
@MainActor
struct PinTheoryLoginView: View {
    @ObservedObject private var auth: PinTheoryAuthService
    @StateObject private var browser: PinTheoryWebAuthenticationBroker
    @State private var email = ""
    @State private var code = ""
    @State private var sentEmail: String?
    @State private var lastSendAttempt: Date?
    @State private var operation: Task<Void, Never>?
    @State private var generation: UInt64 = 0
    @State private var localError: String?
    @State private var showingPrivacy = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, code }
    private enum Action { case google, sendEmail, verifyCode }
    private let resendInterval: TimeInterval = 60

    init(auth: PinTheoryAuthService) {
        self.init(auth: auth, browser: PinTheoryWebAuthenticationBroker())
    }

    /// Supply a root-retained broker to expose browser cancellation during logout.
    init(auth: PinTheoryAuthService, browser: PinTheoryWebAuthenticationBroker) {
        self.auth = auth
        _browser = StateObject(wrappedValue: browser)
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validEmail: Bool {
        let value = trimmedEmail
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard !value.contains(where: { $0.isWhitespace }), parts.count == 2,
              !parts[0].isEmpty else { return false }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domain.count >= 2 && domain.allSatisfy { !$0.isEmpty }
    }
    private var validCode: Bool {
        (6...10).contains(trimmedCode.utf8.count)
            && trimmedCode.utf8.allSatisfy { (48...57).contains($0) }
    }
    private var unavailable: Bool { auth.isBusy || operation != nil || auth.state != .signedOut }
    private var errorMessage: String? {
        if let localError { return localError }
        guard !auth.isBusy, let error = auth.lastError, error != .cancelled else { return nil }
        return error.localizedDescription
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "location.north.circle")
                        .font(.largeTitle.weight(.light))
                        .foregroundStyle(PureLineStyle.accent)
                        .accessibilityHidden(true)
                    Text("PinTheory").font(.largeTitle.weight(.semibold)).tracking(-0.6)
                        .accessibilityAddTraits(.isHeader)
                    Text("Golf, made clearer.").font(.title3).foregroundStyle(PureLineStyle.muted)
                    Text("Sign in to continue").font(.headline).padding(.top, 8)
                }

                Button { start(.google) } label: {
                    Text("Continue with Google").padding(.horizontal, 16).padding(.vertical, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(PureLinePrimaryButtonStyle())
                .disabled(unavailable || !browser.hasPresentationAnchor)
                .accessibilityIdentifier("account-google-sign-in")

                HStack(spacing: 12) {
                    Rectangle().fill(PureLineStyle.line).frame(height: 1)
                    Text("or use email").font(.subheadline).foregroundStyle(PureLineStyle.muted)
                        .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                    Rectangle().fill(PureLineStyle.line).frame(height: 1)
                }

                emailForm

                if auth.isBusy || operation != nil {
                    ProgressView("Completing sign-in…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("account-sign-in-progress")
                }
                if operation != nil {
                    Button("Cancel sign-in") { cancelOperation() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("account-cancel-sign-in")
                }
                if let errorMessage {
                    Text(errorMessage).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account-sign-in-error")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Your golf records stay local for now", systemImage: "iphone")
                        .font(.subheadline.weight(.semibold))
                    Text("Account sync is not connected yet. Signing in does not back up or transfer your rounds, handicap or club setup.")
                        .font(.footnote).foregroundStyle(PureLineStyle.muted)
                    Text("Prerelease test integration. In-app account deletion is not available yet; this is not ready for public release.")
                        .font(.footnote).foregroundStyle(PureLineStyle.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .pureLineCard()

                Button("Account & privacy") { focusedField = nil; showingPrivacy = true }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    .accessibilityIdentifier("account-privacy")
                Text("PinTheory by FairwayVector").font(.caption).foregroundStyle(PureLineStyle.muted)
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
        .sheet(isPresented: $showingPrivacy) {
            NavigationStack {
                PinTheoryAccountPrivacyView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingPrivacy = false }
                        }
                    }
            }
            .tint(PureLineStyle.accent)
            .preferredColorScheme(.light)
        }
        .onDisappear { cancelOperation() }
        .onChange(of: auth.state) { _, state in
            if state != .signedOut { cancelOperation() }
        }
    }

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Email address").font(.subheadline.weight(.medium))
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focusedField, equals: .email)
                .padding(14)
                .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PureLineStyle.line) }
                .disabled(unavailable || sentEmail != nil)
                .accessibilityLabel("Email address")
                .accessibilityHint("Enter your email address to request a sign-in link or code")
                .accessibilityIdentifier("account-email")
                .onSubmit { start(.sendEmail) }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = remainingCooldown(at: context.date)
                Button { start(.sendEmail) } label: {
                    Text(seconds > 0 ? "Send again in \(seconds)s" : (sentEmail == nil ? "Email me a sign-in link" : "Resend sign-in email"))
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(PureLinePrimaryButtonStyle())
                .disabled(unavailable || !validEmail || seconds > 0)
                .accessibilityIdentifier("account-send-email")
            }

            if let sentEmail {
                Text("If email sign-in is available for this address, check your inbox and spam folder for a sign-in email. Use its link, or enter the code below if one is included.")
                    .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("account-email-inbox-notice")
                Text("Email code").font(.subheadline.weight(.medium))
                TextField("Code from your email", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .code)
                    .padding(14)
                    .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PureLineStyle.line) }
                    .disabled(unavailable)
                    .accessibilityLabel("Email sign-in code")
                    .accessibilityHint("Enter the 6 to 10 digit code from your sign-in email")
                    .accessibilityIdentifier("account-email-code")
                Button { start(.verifyCode) } label: {
                    Text("Verify code").padding(.horizontal, 16).padding(.vertical, 12)
                }
                .buttonStyle(PureLinePrimaryButtonStyle())
                .disabled(unavailable || !validCode)
                .accessibilityIdentifier("account-verify-code")
                Button("Use a different email") {
                    self.sentEmail = nil
                    code = ""
                    localError = nil
                    focusedField = .email
                }
                .frame(minHeight: 44)
                .disabled(unavailable)
                .accessibilityIdentifier("account-change-email")
                // Keep the submitted address associated with verification even
                // if a future UI allows editing the visible email field.
                Text("Sign-in email: \(sentEmail)").font(.caption).foregroundStyle(PureLineStyle.muted)
            }
        }
    }

    private func remainingCooldown(at date: Date) -> Int {
        guard let lastSendAttempt else { return 0 }
        return max(0, Int(ceil(resendInterval - date.timeIntervalSince(lastSendAttempt))))
    }

    private func start(_ action: Action) {
        guard !unavailable else { return }
        let address = trimmedEmail
        let token = trimmedCode
        switch action {
        case .google:
            guard browser.hasPresentationAnchor else { return }
        case .sendEmail:
            guard validEmail, remainingCooldown(at: Date()) == 0 else { return }
            // Throttle failures and alternate addresses too, not only successes.
            lastSendAttempt = Date()
        case .verifyCode:
            guard validCode, sentEmail != nil else { return }
        }
        focusedField = nil
        localError = nil
        generation &+= 1
        let ticket = generation
        let verificationEmail = sentEmail ?? address
        operation = Task { @MainActor in
            defer { if generation == ticket { operation = nil } }
            do {
                try Task.checkCancellation()
                switch action {
                case .google:
                    try await auth.signInWithGoogle { [browser] url in
                        try await browser.authenticate(url)
                    }
                case .sendEmail:
                    try await auth.sendEmailMagicLink(to: address)
                    guard generation == ticket, !Task.isCancelled else { return }
                    sentEmail = address
                    code = ""
                case .verifyCode:
                    try await auth.verifyEmailCode(email: verificationEmail, code: token)
                }
            } catch {
                guard generation == ticket, !Task.isCancelled,
                      error as? PinTheoryAuthError != .cancelled,
                      !(error is CancellationError) else { return }
                // Never expose raw provider errors or account-existence details.
                localError = (error as? PinTheoryAuthError)?.localizedDescription
                    ?? "Sign-in could not be completed. Please try again."
            }
        }
    }

    private func cancelOperation() {
        generation &+= 1
        operation?.cancel()
        operation = nil
        browser.cancel()
        // Never implicitly call auth.signOut(). Root owns account lifecycle.
    }
}