import Auth
import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

nonisolated struct PinTheoryAuthIdentity: Equatable, Sendable {
    let userID: UUID
}

nonisolated enum PinTheoryAuthState: Equatable, Sendable {
    case signedOut
    case restoring
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
        installClient()
    }

    private func installClient() {
        lease?.revoke()
        let lease = PinTheoryAuthStorageLease(storage: storage)
        self.lease = lease
        client = AuthClient(configuration: .init(
            url: configuration.projectURL.appendingPathComponent("auth/v1"),
            headers: ["apikey": configuration.publishableKey], flowType: .pkce,
            redirectToURL: PinTheoryAuthConfiguration.callbackURL,
            storageKey: PinTheoryAuthStorageLease.sessionKey, localStorage: lease,
            logger: nil, fetch: fetch, autoRefreshToken: false,
            emitLocalSessionAsInitialSession: true))
    }

    private func begin() throws -> (UInt64, AuthClient) {
        guard !isBusy else { throw PinTheoryAuthError.operationInProgress }
        guard let client else { throw PinTheoryAuthError.secureStorageUnavailable }
        generation &+= 1
        isBusy = true
        lastError = nil
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
            do { _ = try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) }
            catch { throw PinTheoryAuthError.secureStorageUnavailable }
            try check(ticket)
        } catch { throw fail(error, ticket: ticket) }
        installClient()
        try await restore()
    }

    private func useOfflineSession(for expectedUserID: UUID) throws -> Bool {
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
        guard expectedUserID == nil || expectedUserID == session.user.id else {
            throw PinTheoryAuthError.authenticationRequired
        }
        let user = try await client.user(jwt: session.accessToken)
        try check(ticket)
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
            let stored = try storedSession()
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
        guard state == .signedOut else { throw PinTheoryAuthError.authenticationRequired }
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
        guard state == .signedOut else { throw PinTheoryAuthError.authenticationRequired }
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
                    try PinTheoryAuthConfiguration.validateCallback(callback)
                    return callback
                })
            _ = try await confirm(session, client: client, ticket: ticket)
        } catch { throw fail(error, ticket: ticket) }
    }

    func sendEmailMagicLink(to email: String) async throws {
        guard state == .signedOut else { throw PinTheoryAuthError.authenticationRequired }
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            try await client.signInWithOTP(email: email, redirectTo: PinTheoryAuthConfiguration.callbackURL)
            try check(ticket)
            try requirePKCEVerifier()
        } catch { throw fail(error, ticket: ticket) }
    }

    func verifyEmailCode(email: String, code: String) async throws {
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
        try await signIn { client in try await client.session(from: url) }
    }

    private func signIn(preserveVerifierOnPreSessionFailure: Bool = false,
                        _ action: (AuthClient) async throws -> Session) async throws {
        guard state == .signedOut else { throw PinTheoryAuthError.authenticationRequired }
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
        try clearLocalSession(preservingVerifier: false)
    }

    private func clearLocalSession(preservingVerifier: Bool) throws {
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
        guard !failed else {
            lastError = .secureStorageUnavailable
            throw PinTheoryAuthError.secureStorageUnavailable
        }
        installClient()
    }

    private func fail(_ error: Error, ticket: UInt64, preserveVerifier: Bool = false) -> PinTheoryAuthError {
        guard ticket == generation else { return .cancelled }
        if error as? PinTheoryAuthError == .secureStorageUnavailable {
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