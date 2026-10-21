import Auth
import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import Network
import OSLog

nonisolated struct PinTheoryAuthIdentity: Equatable, Sendable {
    let userID: UUID
}

nonisolated enum PinTheoryAuthState: Equatable, Sendable {
    case signedOut
    case restoring
    /// Restricted credential update only: never an account/cache identity.
    case passwordRecovery
    case authenticated(PinTheoryAuthIdentity)
    /// Local account-cache access ONLY. This does not authorize any cloud request.
    case offlineCachedIdentity(PinTheoryAuthIdentity)
}

/// Own exactly one instance per project/storage; the app session owns lifecycle.
/// Auto-refresh is intentionally disabled: restore/token access refresh on demand.
@MainActor
final class PinTheoryAuthService: ObservableObject {
    @Published private(set) var state: PinTheoryAuthState = .signedOut
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: PinTheoryAuthError?
    @Published private(set) var lastNetworkDiagnostic: String?
    private let networkMonitor = NWPathMonitor()

    private let configuration: PinTheoryAuthConfiguration
    private let storage: any AuthLocalStorage
    private let fetch: AuthClient.FetchHandler
    private var client: AuthClient?
    private var lease: PinTheoryAuthStorageLease?
    private var generation: UInt64 = 0
    private var appleNonce: String?

    init(configuration: PinTheoryAuthConfiguration, storage: (any AuthLocalStorage)? = nil,
         fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) }) {
        self.configuration = configuration
        self.storage = storage ?? PinTheoryKeychainAuthStorage(configuration: configuration)
        self.fetch = fetch
        networkMonitor.start(queue: DispatchQueue(label: "com.fairwayvector.auth.network-observation"))
        installClient()
    }

    deinit { networkMonitor.cancel() }

    private func installClient() {
        lease?.revoke()
        let lease = PinTheoryAuthStorageLease(storage: storage)
        self.lease = lease
        let transport = fetch
        let monitor = networkMonitor
        client = AuthClient(configuration: .init(
            url: configuration.projectURL.appendingPathComponent("auth/v1"),
            headers: ["apikey": configuration.publishableKey], flowType: .pkce,
            redirectToURL: PinTheoryAuthConfiguration.callbackURL,
            storageKey: PinTheoryAuthStorageLease.sessionKey, localStorage: lease,
            logger: nil, fetch: { [weak self, lease] request in
                do { return try await transport(request) }
                catch {
                    if let networkError = error as? URLError, networkError.code != .cancelled {
                        let summary = PinTheoryNetworkDiagnostics.describe(networkError, path: monitor.currentPath)
                        await self?.recordNetworkDiagnostic(summary, lease: lease)
                    }
                    throw error
                }
            }, autoRefreshToken: false,
            emitLocalSessionAsInitialSession: true))
    }

    private func recordNetworkDiagnostic(_ summary: String, lease: PinTheoryAuthStorageLease) {
        guard self.lease === lease else { return }
        lastNetworkDiagnostic = summary
        #if DEBUG
        Logger(subsystem: "com.fairwayvector.pintheory", category: "AccountNetwork")
            .error("Account network diagnostic: \(summary, privacy: .public)")
        #endif
    }

    private func begin() throws -> (UInt64, AuthClient) {
        guard !isBusy else { throw PinTheoryAuthError.operationInProgress }
        guard let client else { throw PinTheoryAuthError.secureStorageUnavailable }
        generation &+= 1
        isBusy = true
        lastError = nil
        lastNetworkDiagnostic = nil
        return (generation, client)
    }

    private func check(_ ticket: UInt64) throws {
        guard ticket == generation, !Task.isCancelled else { throw PinTheoryAuthError.cancelled }
    }

    private func finish(_ ticket: UInt64) {
        if ticket == generation { isBusy = false; appleNonce = nil }
    }

    private func confirmedIdentity() throws -> PinTheoryAuthIdentity? {
        do {
            guard let bytes = try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) else { return nil }
            guard let id = UUID(uuidString: String(decoding: bytes, as: UTF8.self)) else {
                throw PinTheoryAuthError.secureStorageUnavailable
            }
            return PinTheoryAuthIdentity(userID: id)
        } catch { throw PinTheoryAuthError.secureStorageUnavailable }
    }

    /// SDK currentSession can hide retrieval/decoding errors behind nil.
    /// Only a successful throwing read with no bytes means no stored session.
    private func storedSession() throws -> Session? {
        do {
            guard let bytes = try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) else { return nil }
            let session = try JSONDecoder().decode(Session.self, from: bytes)
            guard !session.accessToken.isEmpty, !session.refreshToken.isEmpty, session.expiresAt.isFinite else {
                throw PinTheoryAuthError.secureStorageUnavailable
            }
            return session
        } catch { throw PinTheoryAuthError.secureStorageUnavailable }
    }

    private func requirePKCEVerifier() throws {
        do {
            guard let bytes = try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey), !bytes.isEmpty else {
                throw PinTheoryAuthError.secureStorageUnavailable
            }
        } catch { throw PinTheoryAuthError.secureStorageUnavailable }
    }

    private func hasMarker(_ key: String) throws -> Bool {
        do {
            guard let bytes = try storage.retrieve(key: key) else { return false }
            guard bytes == Data("1".utf8) else { throw PinTheoryAuthError.secureStorageUnavailable }
            return true
        } catch { throw PinTheoryAuthError.secureStorageUnavailable }
    }

    private func requireOrdinarySignIn() throws {
        guard !isBusy else { throw PinTheoryAuthError.operationInProgress }
        guard state == .signedOut, try !hasMarker(PinTheoryAuthStorageLease.recoveryKey) else {
            throw PinTheoryAuthError.authenticationRequired
        }
        // A deliberately started new login supersedes a pending reset request,
        // never an activated recovery. The reset destination remains restricted.
        do {
            if try hasMarker(PinTheoryAuthStorageLease.pendingRecoveryKey) {
                try storage.remove(key: PinTheoryAuthStorageLease.pendingRecoveryKey)
            }
        } catch { throw PinTheoryAuthError.secureStorageUnavailable }
    }

    private func activateRecovery() throws {
        do {
            // Write BEFORE exchange or any deletion: a crash cannot restore Home.
            try storage.store(key: PinTheoryAuthStorageLease.recoveryKey, value: Data("1".utf8))
            state = .passwordRecovery
            try storage.remove(key: PinTheoryAuthStorageLease.confirmationKey)
        } catch { throw PinTheoryAuthError.secureStorageUnavailable }
    }

    private func validateRecovery(_ session: Session, client: AuthClient, ticket: UInt64) async throws {
        try check(ticket)
        guard try hasMarker(PinTheoryAuthStorageLease.recoveryKey) else {
            throw PinTheoryAuthError.authenticationRequired
        }
        let user = try await client.user(jwt: session.accessToken)
        try check(ticket)
        guard user.id == session.user.id, !session.isExpired,
              let current = client.currentSession, current.user.id == user.id,
              current.accessToken == session.accessToken else {
            throw PinTheoryAuthError.authenticationRequired
        }
        do {
            try storage.store(key: PinTheoryAuthStorageLease.sessionKey, value: JSONEncoder().encode(session))
            try storage.remove(key: PinTheoryAuthStorageLease.confirmationKey)
        } catch { throw PinTheoryAuthError.secureStorageUnavailable }
        state = .passwordRecovery
    }

    /// Explicit, nondestructive recovery of a storage-locked service. Validate
    /// through throwing reads BEFORE an SDK client can hide a read failure.
    func retrySecureStorage() async throws {
        guard !isBusy else { throw PinTheoryAuthError.operationInProgress }
        guard client == nil else { return }
        generation &+= 1
        let ticket = generation
        do {
            _ = try storedSession()
            _ = try confirmedIdentity()
            _ = try hasMarker(PinTheoryAuthStorageLease.recoveryKey)
            _ = try hasMarker(PinTheoryAuthStorageLease.pendingRecoveryKey)
            do { _ = try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) }
            catch { throw PinTheoryAuthError.secureStorageUnavailable }
            try check(ticket)
        } catch { throw fail(error, ticket: ticket) }
        installClient()
        try await restore()
    }

    private func useOfflineSession(for expectedUserID: UUID) throws -> Bool {
        guard try !hasMarker(PinTheoryAuthStorageLease.recoveryKey) else { return false }
        guard let local = try storedSession(), let cached = try confirmedIdentity(),
              local.user.id == expectedUserID, cached.userID == expectedUserID else { return false }
        state = .offlineCachedIdentity(cached)
        return true
    }

    /// This is the only path that publishes authenticated or writes confirmation.
    /// It uses /user, never a locally decoded JWT subject or cached user metadata.
    private func confirm(_ session: Session, client: AuthClient, ticket: UInt64,
                         expectedUserID: UUID? = nil) async throws -> String {
        try check(ticket)
        guard try !hasMarker(PinTheoryAuthStorageLease.recoveryKey) else {
            throw PinTheoryAuthError.authenticationRequired
        }
        guard expectedUserID == nil || expectedUserID == session.user.id else {
            throw PinTheoryAuthError.authenticationRequired
        }
        let user = try await client.user(jwt: session.accessToken)
        try check(ticket)
        guard try !hasMarker(PinTheoryAuthStorageLease.recoveryKey) else {
            throw PinTheoryAuthError.authenticationRequired
        }
        guard user.id == session.user.id, !session.isExpired,
              let current = client.currentSession, current.user.id == user.id,
              current.accessToken == session.accessToken else {
            throw PinTheoryAuthError.authenticationRequired
        }
        // SDK storage writes can swallow errors. Require our own durable write
        // before recording server confirmation and permitting offline restoration.
        do {
            try storage.store(key: PinTheoryAuthStorageLease.sessionKey, value: JSONEncoder().encode(session))
            try storage.store(key: PinTheoryAuthStorageLease.confirmationKey, value: Data(user.id.uuidString.utf8))
        } catch { throw PinTheoryAuthError.secureStorageUnavailable }
        state = .authenticated(PinTheoryAuthIdentity(userID: user.id))
        return session.accessToken
    }

    func restore() async throws {
        let (ticket, client) = try begin()
        state = .restoring
        defer { finish(ticket) }
        var cached: PinTheoryAuthIdentity?
        do {
            let recovering = try hasMarker(PinTheoryAuthStorageLease.recoveryKey)
            if recovering { try activateRecovery() }
            let stored = try storedSession()
            if recovering {
                // No offline trust and no confirmation marker, even after restart.
                guard stored != nil else { state = .passwordRecovery; return }
                guard client.currentSession != nil else { throw PinTheoryAuthError.secureStorageUnavailable }
                let session = try await client.session
                try await validateRecovery(session, client: client, ticket: ticket)
                return
            }
            cached = try confirmedIdentity()
            guard let local = stored else {
                // A cold-start email link still needs its persisted PKCE verifier.
                // No session is not a logout: do not erase an outstanding link.
                guard cached == nil else { throw PinTheoryAuthError.secureStorageUnavailable }
                state = .signedOut
                return
            }
            guard client.currentSession != nil else {
                throw PinTheoryAuthError.secureStorageUnavailable
            }
            // An unconfirmed cached session may be verified online, never offline.
            if let cached, cached.userID != local.user.id {
                throw PinTheoryAuthError.authenticationRequired
            }
            let session = try await client.session
            _ = try await confirm(session, client: client, ticket: ticket, expectedUserID: cached?.userID)
        } catch {
            guard ticket == generation else { throw PinTheoryAuthError.cancelled }
            if error as? PinTheoryAuthError == .secureStorageUnavailable {
                throw fail(error, ticket: ticket)
            }
            if Task.isCancelled { throw fail(CancellationError(), ticket: ticket) }
            do {
                if Self.isTransient(error), let cached, try useOfflineSession(for: cached.userID) { return }
            } catch { throw fail(error, ticket: ticket) }
            throw fail(error, ticket: ticket)
        }
    }

    /// For sync callers only: pass the UID of the isolated account being synced.
    /// Rechecks the current session AND a server-authenticated user on every call.
    /// Callers must still generation/account-guard their own in-flight requests.
    func authenticatedAccessToken(for expectedUserID: UUID) async throws -> String {
        switch state {
        case .authenticated(let identity), .offlineCachedIdentity(let identity):
            guard identity.userID == expectedUserID else { throw PinTheoryAuthError.authenticationRequired }
        default: throw PinTheoryAuthError.authenticationRequired
        }
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            let session = try await client.session
            return try await confirm(session, client: client, ticket: ticket, expectedUserID: expectedUserID)
        } catch {
            guard ticket == generation else { throw PinTheoryAuthError.cancelled }
            if Task.isCancelled { throw fail(CancellationError(), ticket: ticket) }
            let preserved: Bool
            do {
                if Self.isTransient(error) { preserved = try useOfflineSession(for: expectedUserID) }
                else { preserved = false }
            } catch { throw fail(error, ticket: ticket) }
            if preserved {
                lastError = .authenticationRequired
                throw PinTheoryAuthError.authenticationRequired
            }
            throw fail(error, ticket: ticket)
        }
    }

    /// Native Apple UI retains this opaque ticket with its request, including
    /// failure/cancellation callbacks. The raw nonce stays private in this service.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) throws -> UInt64 {
        try requireOrdinarySignIn()
        let (ticket, _) = try begin()
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            finish(ticket)
            throw PinTheoryAuthError.signInFailed
        }
        let nonce = bytes.map { String(format: "%02x", $0) }.joined()
        appleNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        request.state = String(ticket)
        return ticket
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>, requestID: UInt64) async throws {
        let ticket = requestID
        // Reject stale success AND failure/cancellation before touching any state.
        guard ticket == generation, isBusy, let nonce = appleNonce, let client else {
            throw PinTheoryAuthError.cancelled
        }
        appleNonce = nil // Consume exactly once, including cancellation/failure.
        defer { finish(ticket) }
        do {
            try check(ticket)
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  credential.state == String(ticket), let bytes = credential.identityToken,
                  let token = String(data: bytes, encoding: .utf8), !token.isEmpty else {
                throw PinTheoryAuthError.signInFailed
            }
            try check(ticket)
            let session = try await client.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: nonce))
            _ = try await confirm(session, client: client, ticket: ticket)
        } catch { throw fail(error, ticket: ticket) }
    }

    /// Google uses official SDK OAuth + PKCE, NOT a native Google SDK ID token.
    /// The future UI supplies/retains an ASWebAuthenticationSession browser and its
    /// presentation anchor. Validate the complete destination before SDK exchange.
    func signInWithGoogle(
        launchFlow: @escaping @MainActor @Sendable (URL) async throws -> URL
    ) async throws {
        try requireOrdinarySignIn()
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            let session = try await client.signInWithOAuth(provider: .google,
                redirectTo: PinTheoryAuthConfiguration.callbackURL,
                launchFlow: { [weak self] url in
                    guard let self else { throw PinTheoryAuthError.cancelled }
                    try self.check(ticket)
                    try self.requirePKCEVerifier()
                    let callback = try await launchFlow(url)
                    try self.check(ticket)
                    try PinTheoryAuthConfiguration.validateCallback(callback, allowRecovery: false)
                    return callback
                })
            _ = try await confirm(session, client: client, ticket: ticket)
        } catch { throw fail(error, ticket: ticket) }
    }

    func sendEmailMagicLink(to email: String) async throws {
        try requireOrdinarySignIn()
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            try await client.signInWithOTP(email: email, redirectTo: PinTheoryAuthConfiguration.callbackURL)
            try check(ticket)
            try requirePKCEVerifier()
        } catch {
            // Expose fixed operational categories only; never provider messages,
            // recipient addresses, URLs, credentials or response bodies.
            throw fail(Self.emailRequestError(error), ticket: ticket, preserveVerifier: true)
        }
    }

    private static func emailRequestError(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return error }
        if error is PinTheoryAuthError { return error }
        if let error = error as? URLError { return PinTheoryAuthError.networkError(error) }
        if let authError = error as? AuthError,
           case let .api(_, code, _, response) = authError {
            switch code.rawValue {
            case "over_email_send_rate_limit", "over_request_rate_limit": return PinTheoryAuthError.emailRateLimited
            case "email_provider_disabled", "signup_disabled", "otp_disabled": return PinTheoryAuthError.emailProviderDisabled
            case "captcha_failed": return PinTheoryAuthError.captchaRequired
            case "email_address_not_authorized", "email_address_invalid", "validation_failed": return PinTheoryAuthError.emailRequestRejected
            default: break
            }
            switch response.statusCode {
            case 401, 403: return PinTheoryAuthError.accountServiceUnauthorized
            case 429: return PinTheoryAuthError.emailRateLimited
            case 500...599: return PinTheoryAuthError.emailDeliveryUnavailable
            default: return PinTheoryAuthError.emailRequestRejected
            }
        }
        return PinTheoryAuthError.emailDeliveryUnavailable
    }

    /// Existing magic-link-only accounts receive the same invalid-credentials
    /// category as every incorrect password. No local account-existence lookup.
    func signInWithPassword(email: String, password: String) async throws {
        try await signIn { client in
            do { return try await client.signIn(email: email, password: password) }
            catch { throw Self.passwordError(error) }
        }
    }

    /// True means check email, not proof that a new account was created.
    /// Supabase may deliberately obfuscate an existing account with a user-only response.
    func signUpWithPassword(email: String, password: String) async throws -> Bool {
        try requireOrdinarySignIn()
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        var receivedSession = false
        do {
            let response = try await client.signUp(email: email, password: password,
                redirectTo: PinTheoryAuthConfiguration.callbackURL)
            try check(ticket)
            switch response {
            case .user:
                try requirePKCEVerifier()
                state = .signedOut
                return true
            case .session(let session):
                receivedSession = true
                _ = try await confirm(session, client: client, ticket: ticket)
                return false
            }
        } catch {
            throw fail(Self.passwordError(error), ticket: ticket, preserveVerifier: !receivedSession)
        }
    }

    func sendPasswordReset(email: String) async throws {
        try requireOrdinarySignIn()
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            // Persist intent even if the request times out after delivery. This
            // also prevents a rewritten /callback destination opening Home.
            do { try storage.store(key: PinTheoryAuthStorageLease.pendingRecoveryKey, value: Data("1".utf8)) }
            catch { throw PinTheoryAuthError.secureStorageUnavailable }
            try await client.resetPasswordForEmail(email, redirectTo: PinTheoryAuthConfiguration.passwordResetURL)
            try check(ticket)
            try requirePKCEVerifier()
        } catch { throw fail(Self.emailRequestError(error), ticket: ticket, preserveVerifier: true) }
    }

    func resendSignupConfirmation(email: String) async throws {
        try requireOrdinarySignIn()
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            try await client.resend(email: email, type: .signup,
                emailRedirectTo: PinTheoryAuthConfiguration.callbackURL)
            try check(ticket)
            try requirePKCEVerifier()
        } catch { throw fail(Self.emailRequestError(error), ticket: ticket, preserveVerifier: true) }
    }

    /// Server policy is authoritative. UI should recommend at least eight
    /// characters for NEW passwords; never apply that minimum to existing login.
    func completePasswordReset(password: String) async throws {
        guard state == .passwordRecovery else { throw PinTheoryAuthError.authenticationRequired }
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            guard try hasMarker(PinTheoryAuthStorageLease.recoveryKey), try storedSession() != nil else {
                throw PinTheoryAuthError.authenticationRequired
            }
            let session = try await client.session
            try await validateRecovery(session, client: client, ticket: ticket)
            let user = try await client.update(user: UserAttributes(password: password))
            try check(ticket)
            guard user.id == session.user.id else { throw PinTheoryAuthError.authenticationRequired }
        } catch { throw fail(Self.passwordError(error), ticket: ticket) }
        // Outside the operation catch: logout advances generation, and storage
        // failures must surface as storage failures, not stale-ticket cancellation.
        // Never confirm/open Home. This is the existing LOCAL logout API.
        try signOut()
    }

    private static func passwordError(_ error: Error) -> Error {
        if error is PinTheoryAuthError || error is CancellationError { return error }
        if let error = error as? URLError {
            return PinTheoryAuthError.networkError(error)
        }
        if let authError = error as? AuthError {
            switch authError {
            case .weakPassword: return PinTheoryAuthError.weakPassword
            case let .api(_, code, _, response):
                switch code.rawValue {
                case "weak_password", "same_password": return PinTheoryAuthError.weakPassword
                case "email_not_confirmed": return PinTheoryAuthError.emailNotConfirmed
                case "invalid_credentials", "invalid_grant", "user_not_found": return PinTheoryAuthError.invalidCredentials
                // Never expose whether an address already has an account.
                case "email_exists", "user_already_exists": return PinTheoryAuthError.signInFailed
                default: break
                }
                if response.statusCode == 429 { return PinTheoryAuthError.emailRateLimited }
                if (500...599).contains(response.statusCode) { return PinTheoryAuthError.networkUnavailable }
            default: break
            }
        }
        return PinTheoryAuthError.signInFailed
    }

    func verifyEmailCode(email: String, code: String) async throws {
        // A legacy generic OTP must not turn a pending reset into normal login.
        guard try !hasMarker(PinTheoryAuthStorageLease.pendingRecoveryKey) else {
            throw PinTheoryAuthError.authenticationRequired
        }
        try await signIn(preserveVerifierOnPreSessionFailure: true) { client in
            guard let session = try await client.verifyOTP(email: email, token: code, type: .email).session else {
                throw PinTheoryAuthError.signInFailed
            }
            return session
        }
    }

    /// Only route URLs here explicitly; do not also call SDK handle(_:).
    func handleCallback(_ url: URL) async throws {
        try PinTheoryAuthConfiguration.validateCallback(url)
        guard !isBusy else { throw PinTheoryAuthError.operationInProgress }
        let recovering = try hasMarker(PinTheoryAuthStorageLease.recoveryKey)
        let pending = try hasMarker(PinTheoryAuthStorageLease.pendingRecoveryKey)
        if PinTheoryAuthConfiguration.isPasswordResetCallback(url) || recovering || pending {
            // A reset link supersedes an ordinary session. activateRecovery()
            // gates every window before the old session is removed/exchanged.
            let (ticket, _) = try begin()
            defer { finish(ticket) }
            do {
                try activateRecovery()
                if !recovering {
                    // Never restore an older ordinary session if exchange fails.
                    lease?.revoke()
                    do { try storage.remove(key: PinTheoryAuthStorageLease.sessionKey) }
                    catch { throw PinTheoryAuthError.secureStorageUnavailable }
                    installClient()
                }
                guard let client else { throw PinTheoryAuthError.secureStorageUnavailable }
                try requirePKCEVerifier()
                let session = try await client.session(from: url)
                try check(ticket)
                try await validateRecovery(session, client: client, ticket: ticket)
            } catch { throw fail(error, ticket: ticket, preserveVerifier: true) }
        } else {
            // Query `type=recovery` is NOT trusted as routing authority.
            try await signIn(preserveVerifierOnPreSessionFailure: true) { client in
                try self.requirePKCEVerifier()
                return try await client.session(from: url)
            }
        }
    }

    private func signIn(preserveVerifierOnPreSessionFailure: Bool = false,
                        _ action: (AuthClient) async throws -> Session) async throws {
        try requireOrdinarySignIn()
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        var receivedSession = false
        do {
            let session = try await action(client)
            receivedSession = true
            _ = try await confirm(session, client: client, ticket: ticket)
        } catch {
            // Wrong/expired OTPs must not invalidate an outstanding magic link.
            // Always discard partial SDK sessions; a /user failure after sign-in
            // is NOT a pre-session failure and receives full cleanup.
            throw fail(error, ticket: ticket,
                       preserveVerifier: preserveVerifierOnPreSessionFailure && !receivedSession)
        }
    }

    /// Local logout/cancel, including PKCE and confirmation. No server revocation
    /// request is made. Revoke the old SDK's storage before clearing/replacing it.
    /// On Keychain failure the process remains locked; retry logout when unlocked.
    func signOut() throws {
        try clearLocalSession(preservingVerifier: false, explicitLogout: true)
    }

    private func clearLocalSession(preservingVerifier: Bool, explicitLogout: Bool = false) throws {
        generation &+= 1
        lease?.revoke()
        lease = nil
        client = nil
        appleNonce = nil
        isBusy = false
        state = .signedOut
        lastError = nil
        var failed = false
        var keys = [PinTheoryAuthStorageLease.confirmationKey, PinTheoryAuthStorageLease.sessionKey]
        if !preservingVerifier { keys.append(PinTheoryAuthStorageLease.verifierKey) }
        for key in keys {
            do { try storage.remove(key: key) } catch { failed = true }
        }
        if explicitLogout && !failed {
            // Recovery marker is removed LAST, only after credential deletion.
            for key in [PinTheoryAuthStorageLease.pendingRecoveryKey, PinTheoryAuthStorageLease.recoveryKey] {
                do {
                    if try storage.retrieve(key: key) != nil { try storage.remove(key: key) }
                } catch { failed = true; break }
            }
        }
        guard !failed else {
            lastError = .secureStorageUnavailable
            throw PinTheoryAuthError.secureStorageUnavailable
        }
        installClient()
    }

    private func fail(_ error: Error, ticket: UInt64, preserveVerifier: Bool = false) -> PinTheoryAuthError {
        guard ticket == generation else { return .cancelled }
        let recovering: Bool
        var storageFailed = error as? PinTheoryAuthError == .secureStorageUnavailable
        do { recovering = try hasMarker(PinTheoryAuthStorageLease.recoveryKey) }
        catch { recovering = false; storageFailed = true }
        if storageFailed {
            // Lock in-process, but preserve durable bytes for recovery/inspection.
            // retrySecureStorage reinstalls a fresh lease without deleting bytes.
            generation &+= 1
            lease?.revoke()
            lease = nil
            client = nil
            appleNonce = nil
            isBusy = false
            state = .signedOut
            lastError = .secureStorageUnavailable
            return .secureStorageUnavailable
        }
        let sanitized: PinTheoryAuthError
        if error is CancellationError || (error as? URLError)?.code == .cancelled
            || (error as? ASAuthorizationError)?.code == .canceled
            || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
            sanitized = .cancelled
        } else { sanitized = (error as? PinTheoryAuthError) ?? .signInFailed }
        if recovering {
            // Retryable update/exchange/network failures must retain verifier,
            // restricted session and marker. No offline account access.
            state = .passwordRecovery
            lastError = sanitized
            return sanitized
        }
        do { try clearLocalSession(preservingVerifier: preserveVerifier) }
        catch { return .secureStorageUnavailable }
        lastError = sanitized
        return sanitized
    }

    private static func isTransient(_ error: Error) -> Bool {
        // Auth 2.55.4 exposes the HTTP response on this four-value API case.
        // Definitive invalid grants/revocation must never enable local access.
        if let authError = error as? AuthError,
           case let .api(_, code, _, response) = authError {
            let invalidGrants = ["invalid_grant", "invalid_credentials", "invalid_jwt", "bad_jwt",
                                 "session_not_found", "session_expired", "refresh_token_not_found",
                                 "refresh_token_already_used", "user_not_found", "user_banned"]
            guard !invalidGrants.contains(code.rawValue) else { return false }
            return response.statusCode == 408 || response.statusCode == 429
                || (500...599).contains(response.statusCode)
        }
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                .cannotConnectToHost, .dnsLookupFailed, .timedOut].contains(error.code)
    }
}