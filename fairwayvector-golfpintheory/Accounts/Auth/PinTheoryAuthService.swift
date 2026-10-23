import Auth
import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import Network
import OSLog
import SwiftUI

nonisolated private final class PinTheoryNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated struct PinTheoryAuthIdentity: Equatable, Sendable {
    let userID: UUID
}

/// Verified profile details safe for display; never contains session credentials.
nonisolated struct PinTheoryAccountDetails: Equatable, Sendable {
    let email: String?
    let pendingEmail: String?
    let providers: [String]
    let firstName: String
    let lastName: String
    let displayName: String
    var supportsEmailManagement: Bool { providers.contains("email") }
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
    @Published private(set) var accountWasDeleted = false
    private let networkMonitor = NWPathMonitor()
    private static let noRedirectSession = URLSession(configuration: .ephemeral,
        delegate: PinTheoryNoRedirectDelegate(), delegateQueue: nil)

    private let configuration: PinTheoryAuthConfiguration
    private let storage: any AuthLocalStorage
    private let fetch: AuthClient.FetchHandler
    private let deletionFetch: AuthClient.FetchHandler
    private let deletionEndpointAvailable: Bool
    private var client: AuthClient?
    private var lease: PinTheoryAuthStorageLease?
    private var generation: UInt64 = 0
    private var appleNonce: String?

    private struct VerifiedAccountContext {
        let user: User
        let providers: [String]
        let identities: [UserIdentity]
    }

    var canRequestAccountDeletion: Bool { deletionEndpointAvailable }

    init(configuration: PinTheoryAuthConfiguration, storage: (any AuthLocalStorage)? = nil,
         fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) },
         deletionFetch: AuthClient.FetchHandler? = nil,
         deletionEndpointAvailable: Bool = Bundle.main.object(forInfoDictionaryKey: "GOLFPINTHEORY_ACCOUNT_DELETION_ENABLED") as? String == "YES") {
        self.configuration = configuration
        self.storage = storage ?? PinTheoryKeychainAuthStorage(configuration: configuration)
        self.fetch = fetch
        self.deletionFetch = deletionFetch ?? { try await Self.noRedirectSession.data(for: $0) }
        self.deletionEndpointAvailable = deletionEndpointAvailable
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
    /// The UI supplies/retains an ASWebAuthenticationSession browser and its
    /// presentation anchor. Validate the complete destination before SDK exchange.
    func signInWithGoogle(
        launchFlow: @escaping @MainActor @Sendable (URL) async throws -> URL
    ) async throws {
        try requireOrdinarySignIn()
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        var stage = "authorization_setup"
        do {
            let authorizationURL = try client.getOAuthSignInURL(provider: .google,
                redirectTo: PinTheoryAuthConfiguration.callbackURL)
            try check(ticket)
            try requirePKCEVerifier()

            stage = "browser_authorization"
            let callback = try await launchFlow(authorizationURL)
            try check(ticket)

            stage = "app_callback_validation"
            if let reason = PinTheoryAuthConfiguration.callbackValidationFailure(callback, allowRecovery: false) {
                Self.logGoogleOAuthStage("Callback rejected: \(reason)")
            }
            try PinTheoryAuthConfiguration.validateCallback(callback, allowRecovery: false)
            let normalizedCallback = try PinTheoryAuthConfiguration.callbackURLForCodeExchange(callback)
            stage = "pkce_verifier_validation"
            do { try requirePKCEVerifier() }
            catch {
                Self.logGoogleOAuthStage("Callback verifier unavailable")
                throw error
            }

            stage = "authorization_code_exchange"
            let session = try await client.session(from: normalizedCallback)
            try check(ticket)

            stage = "server_session_verification"
            _ = try await confirm(session, client: client, ticket: ticket)
            Self.logGoogleOAuthStage("Sign-in completed")
        } catch {
            Self.logGoogleOAuthStage("Sign-in failed at \(stage)")
            throw fail(Self.googleOAuthError(error), ticket: ticket)
        }
    }

    private static func logGoogleOAuthStage(_ message: String) {
        #if DEBUG
        Logger(subsystem: "com.fairwayvector.pintheory", category: "GoogleOAuth")
            .notice("\(message, privacy: .public)")
        #endif
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
        } catch {
            let mapped = (error as? PinTheoryAuthError) == .recentAuthenticationRequired
                ? PinTheoryAuthError.recentAuthenticationRequired
                : Self.passwordError(error)
            throw fail(mapped, ticket: ticket)
        }
        // Outside the operation catch: logout advances generation, and storage
        // failures must surface as storage failures, not stale-ticket cancellation.
        // Never confirm/open Home. This is the existing LOCAL logout API.
        try signOut()
    }

    /// Returns server-verified profile and provider data for the currently authenticated UID.
    /// Offline-cached identity is deliberately insufficient for account management.
    func accountDetails() async throws -> PinTheoryAccountDetails {
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            let context = try await verifiedAccountContext(ticket: ticket, client: client)
            return PinTheoryAccountDetails(email: context.user.email, pendingEmail: context.user.newEmail,
                providers: context.providers, firstName: Self.accountName(context).first,
                lastName: Self.accountName(context).last, displayName: Self.accountName(context).display)
        } catch {
            throw recordManagementFailure(error, ticket: ticket, fallback: .authRequired)
        }
    }

    /// Stores an optional user-facing name in Supabase Auth user metadata.
    /// `display_name` is the display value; first/last are retained separately.
    /// This metadata is not an authorization source.
    func updateDisplayName(firstName: String, lastName: String) async throws -> PinTheoryAccountDetails {
        let first = Self.normalizedName(firstName)
        let last = Self.normalizedName(lastName)
        guard first.count <= 80, last.count <= 80 else { throw PinTheoryAuthError.invalidDisplayName }
        let displayName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            let context = try await verifiedAccountContext(ticket: ticket, client: client)
            let metadata: [String: AnyJSON] = [
                "first_name": first.isEmpty ? .null : .string(first),
                "last_name": last.isEmpty ? .null : .string(last),
                "display_name": displayName.isEmpty ? .null : .string(displayName),
            ]
            let updated = try await client.update(user: UserAttributes(data: metadata))
            try check(ticket)
            guard updated.id == context.user.id,
                  let current = client.currentSession, current.user.id == context.user.id else {
                throw PinTheoryAuthError.authenticationRequired
            }
            let token = try await confirm(current, client: client, ticket: ticket,
                                          expectedUserID: context.user.id)
            let verified = try await client.user(jwt: token)
            let verifiedIdentities = try await client.userIdentities()
            try check(ticket)
            guard verified.id == context.user.id,
                verifiedIdentities.allSatisfy({ $0.userId == context.user.id }),
                Self.metadataString("first_name", in: verified) == first,
                Self.metadataString("last_name", in: verified) == last,
                Self.metadataString("display_name", in: verified) == displayName else {
                throw PinTheoryAuthError.displayNameUpdateUnavailable
            }
            return PinTheoryAccountDetails(email: verified.email, pendingEmail: verified.newEmail,
                providers: context.providers, firstName: first, lastName: last,
                displayName: displayName)
        } catch {
            throw recordManagementFailure(error, ticket: ticket, fallback: .displayNameUpdateUnavailable)
        }
    }

    private static func metadataString(_ key: String, in user: User) -> String {
        guard case .string(let value)? = user.userMetadata[key] else { return "" }
        return value
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Re-authenticates the email identity before changing its password. Both authentication
    /// and update responses must remain bound to the same confirmed UID.
    func changePassword(currentPassword: String, newPassword: String) async throws {
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            let context = try await verifiedAccountContext(ticket: ticket, client: client)
            guard context.providers.contains("email"), let email = context.user.email else {
                throw PinTheoryAuthError.emailIdentityRequired
            }
            _ = try await reauthenticateEmailPassword(client: client, email: email,
                password: currentPassword, expectedUserID: context.user.id, ticket: ticket)
            try check(ticket)
            // Password grant just refreshed this same account's session; Supabase
            // applies its configured recent-auth policy to the following update.
            let updated = try await client.update(user: UserAttributes(password: newPassword))
            try check(ticket)
            guard updated.id == context.user.id,
                  let current = client.currentSession, current.user.id == context.user.id else {
                throw PinTheoryAuthError.authenticationRequired
            }
            _ = try await confirm(current, client: client, ticket: ticket, expectedUserID: context.user.id)
        } catch {
            throw recordManagementFailure(error, ticket: ticket, fallback: .accountPasswordUpdateUnavailable)
        }
    }

    /// Refreshes the existing authenticated session to satisfy the backend's
    /// recent-authentication requirement, then requests deletion. No password is needed.
    func deleteAccount() async throws {
        accountWasDeleted = false
        guard deletionEndpointAvailable else { throw PinTheoryAuthError.accountDeletionUnavailable }
        let (ticket, client) = try begin()
        defer { finish(ticket) }
        do {
            let context = try await verifiedAccountContext(ticket: ticket, client: client)
            let fresh = try await client.refreshSession()
            try check(ticket)
            guard fresh.user.id == context.user.id,
                  let current = client.currentSession, current.user.id == context.user.id,
                  current.accessToken == fresh.accessToken else {
                throw PinTheoryAuthError.authenticationRequired
            }
            let verifiedSession = try await confirm(fresh, client: client, ticket: ticket,
                                                    expectedUserID: context.user.id)
            guard verifiedSession == fresh.accessToken else { throw PinTheoryAuthError.authenticationRequired }
            let reverified = try await client.user(jwt: fresh.accessToken)
            try check(ticket)
            guard reverified.id == context.user.id else { throw PinTheoryAuthError.authenticationRequired }
            let response = try await sendAccountDeletionRequest(accessToken: fresh.accessToken)
            try check(ticket)
            guard response.statusCode == 200,
                  let body = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  body["status"] as? String == "deleted" else {
                if response.statusCode == 401 { throw PinTheoryAuthError.authRequired }
                if response.statusCode == 403 { throw PinTheoryAuthError.recentAuthenticationRequired }
                throw PinTheoryAuthError.accountDeletionUnavailable
            }
        } catch {
            throw recordManagementFailure(error, ticket: ticket, fallback: .accountDeletionUnavailable)
        }
        // Server has confirmed deletion. Clear local credentials only now; never claim
        // completion for the backend's retryable deletion_pending response.
        accountWasDeleted = true
        try signOut()
    }

    private func verifiedAccountContext(ticket: UInt64? = nil, client: AuthClient? = nil) async throws -> VerifiedAccountContext {
        let client = client ?? self.client
        guard let client else { throw PinTheoryAuthError.authenticationRequired }
        if let ticket { try check(ticket) }
        guard case .authenticated(let identity) = state,
              try !hasMarker(PinTheoryAuthStorageLease.recoveryKey) else {
            throw PinTheoryAuthError.authenticationRequired
        }
        let session = try await client.session
        let token = try await confirm(session, client: client, ticket: ticket ?? generation,
                                      expectedUserID: identity.userID)
        guard token == session.accessToken else { throw PinTheoryAuthError.authenticationRequired }
        let user = try await client.user(jwt: token)
        let identities = try await client.userIdentities()
        if let ticket { try check(ticket) }
        guard user.id == identity.userID,
              identities.allSatisfy({ $0.userId == identity.userID }),
              let current = client.currentSession, current.user.id == identity.userID,
              current.accessToken == token else { throw PinTheoryAuthError.authenticationRequired }
        let providers = Set(identities.map(\.provider)).sorted()
        return VerifiedAccountContext(user: user, providers: providers, identities: identities)
    }

    private static func accountName(_ context: VerifiedAccountContext) -> (first: String, last: String, display: String) {
        let googleData = context.identities.first(where: { $0.provider.lowercased() == "google" })?.identityData ?? [:]
        let googleFullName = firstMetadataString(["name", "full_name", "display_name"], in: googleData)
        let googleNameParts = splitFullName(googleFullName)
        let googleFirst = firstMetadataString(["given_name", "first_name"], in: googleData)
        let googleLast = firstMetadataString(["family_name", "last_name"], in: googleData)

        let first = context.user.userMetadata.keys.contains("first_name")
            ? metadataString("first_name", in: context.user) : (googleFirst.isEmpty ? googleNameParts.first : googleFirst)
        let last = context.user.userMetadata.keys.contains("last_name")
            ? metadataString("last_name", in: context.user) : (googleLast.isEmpty ? googleNameParts.last : googleLast)
        let display: String
        if context.user.userMetadata.keys.contains("display_name") {
            display = metadataString("display_name", in: context.user)
        } else {
            let providerDisplay = firstMetadataString(["display_name", "name", "full_name"], in: googleData)
            display = providerDisplay.isEmpty ? [first, last].filter { !$0.isEmpty }.joined(separator: " ") : providerDisplay
        }
        return (first, last, display)
    }

    private static func firstMetadataString(_ keys: [String], in metadata: [String: AnyJSON]) -> String {
        for key in keys {
            if case .string(let value)? = metadata[key] {
                let normalized = normalizedName(value)
                if !normalized.isEmpty { return normalized }
            }
        }
        return ""
    }

    private static func splitFullName(_ name: String) -> (first: String, last: String) {
        let parts = normalizedName(name).split(whereSeparator: \.isWhitespace)
        guard let first = parts.first else { return ("", "") }
        return (String(first), parts.dropFirst().joined(separator: " "))
    }

    private func reauthenticateEmailPassword(client: AuthClient, email: String, password: String,
                                             expectedUserID: UUID, ticket: UInt64) async throws -> Session {
        let fresh: Session
        do { fresh = try await client.signIn(email: email, password: password) }
        catch { throw PinTheoryAuthError.recentAuthenticationRequired }
        try check(ticket)
        guard fresh.user.id == expectedUserID,
              let current = client.currentSession, current.user.id == expectedUserID,
              current.accessToken == fresh.accessToken else {
            throw PinTheoryAuthError.authenticationRequired
        }
        return fresh
    }

    private func sendAccountDeletionRequest(accessToken: String) async throws -> (data: Data, statusCode: Int) {
        let url = configuration.accountDeletionURL
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == configuration.projectURL.host,
              parts.port == nil, parts.percentEncodedPath == "/functions/v1/delete-account",
              parts.query == nil, parts.fragment == nil else {
            throw PinTheoryAuthError.accountDeletionUnavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await deletionFetch(request)
        guard let http = response as? HTTPURLResponse, http.url == url,
              (200...299).contains(http.statusCode) || (400...499).contains(http.statusCode)
        else { throw PinTheoryAuthError.accountDeletionUnavailable }
        return (data, http.statusCode)
    }

    private func recordManagementFailure(_ error: Error, ticket: UInt64,
                                         fallback: PinTheoryAuthError) -> PinTheoryAuthError {
        guard ticket == generation else { return .cancelled }
        let sanitized: PinTheoryAuthError
        if let known = error as? PinTheoryAuthError { sanitized = known }
        else if let urlError = error as? URLError { sanitized = .networkError(urlError) }
        else if let authError = error as? AuthError,
                case let .api(_, code, _, response) = authError {
            if code.rawValue == "weak_password" || code.rawValue == "same_password" {
                sanitized = .weakPassword
            } else if response.statusCode == 401 || response.statusCode == 403 {
                sanitized = .recentAuthenticationRequired
            } else if response.statusCode == 429 {
                sanitized = .emailRateLimited
            } else { sanitized = fallback }
        } else { sanitized = fallback }
        lastError = sanitized
        return sanitized
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
                if (500...599).contains(response.statusCode) { return PinTheoryAuthError.accountServiceUnavailable }
            default: break
            }
        }
        return PinTheoryAuthError.signInFailed
    }

    private static func googleOAuthError(_ error: Error) -> PinTheoryAuthError {
        if let known = error as? PinTheoryAuthError {
            switch known {
            case .invalidCallback: return .googleOAuthCallbackFailed
            case .signInFailed: return .googleOAuthUnavailable
            default: return known
            }
        }
        if let urlError = error as? URLError { return .networkError(urlError) }
        if let authError = error as? AuthError {
            switch authError {
            case .pkceGrantCodeExchange, .implicitGrantRedirect:
                return .googleOAuthCallbackFailed
            case let .api(_, _, _, response):
                if response.statusCode == 401 || response.statusCode == 403 {
                    return .accountServiceUnauthorized
                }
                if (500...599).contains(response.statusCode) { return .accountServiceUnavailable }
                return .googleOAuthSetupFailed
            default:
                return .googleOAuthUnavailable
            }
        }
        if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
            return .cancelled
        }
        return .googleOAuthUnavailable
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