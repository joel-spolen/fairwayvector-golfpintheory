import Auth
import Combine
import Foundation
import Testing
@testable import fairwayvector_golfpintheory

/// SOURCE ONLY. All HTTP is intercepted; no Keychain, browser or live service.
@MainActor
struct AccountPasswordTests {
    private func service(_ storage: PasswordMemoryStorage, _ transport: PasswordFetch) throws -> PinTheoryAuthService {
        let configuration = try PinTheoryAuthConfiguration(projectURL: URL(string: "https://password.example.test")!,
            publishableKey: "sb_publishable_password_fixture")
        return PinTheoryAuthService(configuration: configuration, storage: storage,
            fetch: { try await transport.respond($0, storage: storage) })
    }

    private func seed(_ storage: PasswordMemoryStorage, recovery: Bool, confirmed: Bool = false) throws {
        try storage.store(key: PinTheoryAuthStorageLease.sessionKey, value: JSONEncoder().encode(PasswordWire.session))
        if recovery { try storage.store(key: PinTheoryAuthStorageLease.recoveryKey, value: Data("1".utf8)) }
        if confirmed {
            try storage.store(key: PinTheoryAuthStorageLease.confirmationKey,
                value: Data(PasswordWire.id.uuidString.utf8))
        }
    }

    @Test func exactResetDestinationAndGoogleExclusion() throws {
        #expect(PinTheoryAuthConfiguration.callbackURL.absoluteString == "golfpintheory://auth/callback")
        let callback = URL(string: "golfpintheory://auth/callback?code=fixture")!
        #expect(PinTheoryAuthConfiguration.acceptsCallback(callback))
        #expect(!PinTheoryAuthConfiguration.isPasswordResetCallback(callback))
        try PinTheoryAuthConfiguration.validateCallback(callback, allowRecovery: false)
        #expect(PinTheoryAuthConfiguration.passwordResetURL.absoluteString == "golfpintheory://auth/reset-password")
        let reset = URL(string: "golfpintheory://auth/reset-password?code=fixture")!
        #expect(PinTheoryAuthConfiguration.acceptsCallback(reset))
        #expect(PinTheoryAuthConfiguration.isPasswordResetCallback(reset))
        try PinTheoryAuthConfiguration.validateCallback(reset)
        #expect(throws: PinTheoryAuthError.invalidCallback) {
            try PinTheoryAuthConfiguration.validateCallback(reset, allowRecovery: false)
        }
        for raw in ["golfpintheory://auth/reset-password/?code=x", "golfpintheory://auth/%72eset-password?code=x",
                    "golfpintheory://auth/reset-password?code=x&code=y", "golfpintheory://auth/reset-password?code=",
                    "golfpintheory://auth/reset-password?code=x#type=recovery", "golfpintheory://other/reset-password?code=x",
                    "golfpintheory://user@auth/reset-password?code=x", "golfpintheory://auth:443/reset-password?code=x",
                    "golfpintheory://auth/reset-password?error=expired", "golfpintheory://auth/reset-password?type=recovery"] {
            #expect(throws: PinTheoryAuthError.invalidCallback) {
                try PinTheoryAuthConfiguration.validateCallback(URL(string: raw)!)
            }
        }
    }

    @Test(arguments: [
        "pintheory://auth/reset-password?code=x", "pintheory://auth/callback?code=x",
        "golfpintheoryx://auth/reset-password?code=x", "golfpintheory:/auth/reset-password?code=x",
        "golfpintheory://auth/reset-password/?code=x", "golfpintheory://auth/%72eset-password?code=x",
        "golfpintheory://auth/Reset-password?code=x", "golfpintheory://auth/reset-password/extra?code=x",
        "golfpintheory://auth?code=x", "golfpintheory://other/reset-password?code=x",
        "golfpintheory://user@auth/reset-password?code=x", "golfpintheory://auth:443/reset-password?code=x",
        "golfpintheory://auth/reset-password?code=x#type=recovery"
    ])
    func rejectsOldSchemeAndMalformedResetDestinations(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(!PinTheoryAuthConfiguration.acceptsCallback(url))
        #expect(!PinTheoryAuthConfiguration.isPasswordResetCallback(url))
        #expect(throws: PinTheoryAuthError.invalidCallback) {
            try PinTheoryAuthConfiguration.validateCallback(url)
        }
    }

    @Test func passwordGrantRequiresServerUserAndAllowsExistingShortPassword() async throws {
        let storage = PasswordMemoryStorage()
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        // No new-password minimum is imposed on an existing account's password.
        try await auth.signInWithPassword(email: "fixture@example.test", password: "old")
        #expect(auth.state == .authenticated(.init(userID: PasswordWire.id)))
        #expect(await transport.paths == ["POST /auth/v1/token", "GET /auth/v1/user"])
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == Data(PasswordWire.id.uuidString.utf8))
        #expect(!storage.containsPassword())
    }

    @Test(arguments: [false, true])
    func signupUserOnlyVersusImmediateSession(confirmation: Bool) async throws {
        let storage = PasswordMemoryStorage()
        let transport = PasswordFetch()
        await transport.setConfirmation(confirmation)
        let auth = try service(storage, transport)
        #expect(try await auth.signUpWithPassword(email: "fixture@example.test", password: "fixture-new-password") == confirmation)
        if confirmation {
            #expect(auth.state == .signedOut)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) != nil)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == nil)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
            let restarted = try service(storage, transport)
            try await restarted.restore()
            #expect(restarted.state == .signedOut)
            try await restarted.handleCallback(URL(string: "golfpintheory://auth/callback?code=signup")!)
            #expect(restarted.state == .authenticated(.init(userID: PasswordWire.id)))
        } else {
            #expect(auth.state == .authenticated(.init(userID: PasswordWire.id)))
        }
        #expect(!auth.isBusy)
        #expect(!storage.containsPassword())
    }

    @Test func resendConfirmationUsesSignupAndPKCEWithoutOpeningAccount() async throws {
        let storage = PasswordMemoryStorage()
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        try await auth.resendSignupConfirmation(email: "fixture@example.test")
        #expect(auth.state == .signedOut)
        #expect(await transport.paths == ["POST /auth/v1/resend"])
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) != nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
    }

    @Test(arguments: ["golfpintheory://auth/reset-password", "golfpintheory://auth/callback"])
    func pendingResetSurvivesRestartAndNeverConfirmsEvenIfDestinationRewritten(destination: String) async throws {
        let storage = PasswordMemoryStorage()
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        try await auth.sendPasswordReset(email: "fixture@example.test")
        #expect(auth.state == .signedOut)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.pendingRecoveryKey) == Data("1".utf8))
        let verifier = try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey)
        #expect(verifier != nil)
        let restarted = try service(storage, transport)
        try await restarted.restore()
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == verifier)
        await transport.requireRecoveryMarker()
        var states: [PinTheoryAuthState] = []
        let observation = restarted.$state.sink { states.append($0) }
        defer { observation.cancel() }
        try await restarted.handleCallback(URL(string: "\(destination)?code=reset&type=signup")!)
        #expect(restarted.state == .passwordRecovery)
        #expect(!states.contains(.authenticated(.init(userID: PasswordWire.id))))
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) == Data("1".utf8))
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
        do {
            _ = try await restarted.authenticatedAccessToken(for: PasswordWire.id)
            Issue.record("Recovery exposed a cloud token")
        } catch { #expect(error as? PinTheoryAuthError == .authenticationRequired) }
    }

    @Test func callbackQueryTypeIsNotRecoveryAuthority() async throws {
        let storage = PasswordMemoryStorage()
        try storage.store(key: PinTheoryAuthStorageLease.verifierKey, value: Data("fixture-verifier".utf8))
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        try await auth.handleCallback(URL(string: "golfpintheory://auth/callback?code=ordinary&type=recovery")!)
        #expect(auth.state == .authenticated(.init(userID: PasswordWire.id)))
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) == nil)
    }

    @Test func distinctResetURLIsRestrictedWithoutPendingMarker() async throws {
        let storage = PasswordMemoryStorage()
        try storage.store(key: PinTheoryAuthStorageLease.verifierKey, value: Data("fixture-verifier".utf8))
        let transport = PasswordFetch()
        await transport.requireRecoveryMarker()
        let auth = try service(storage, transport)
        try await auth.handleCallback(URL(string: "golfpintheory://auth/reset-password?code=reset")!)
        #expect(auth.state == .passwordRecovery)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
    }

    @Test(arguments: [false, true])
    func recoveryRestartClearsOldConfirmationAndNeverAllowsOffline(offline: Bool) async throws {
        let storage = PasswordMemoryStorage()
        try seed(storage, recovery: true, confirmed: true)
        let transport = PasswordFetch()
        await transport.setOffline(offline)
        let auth = try service(storage, transport)
        do { try await auth.restore(); #expect(!offline) }
        catch { #expect(offline); #expect(error is PinTheoryAuthError) }
        #expect(auth.state == .passwordRecovery)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) != nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) != nil)
        #expect(!auth.isBusy)
        do { try await auth.signInWithPassword(email: "fixture@example.test", password: "old")
            Issue.record("Recovery bypassed with ordinary login")
        } catch { #expect(error as? PinTheoryAuthError == .authenticationRequired) }
    }

    @Test func confirmedPasswordUpdateRequiresFreshLogin() async throws {
        let storage = PasswordMemoryStorage()
        try seed(storage, recovery: true)
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        try await auth.restore()
        var states: [PinTheoryAuthState] = []
        let observation = auth.$state.sink { states.append($0) }
        defer { observation.cancel() }
        try await auth.completePasswordReset(password: "fixture-new-password")
        #expect(auth.state == .signedOut)
        #expect(!states.contains(.authenticated(.init(userID: PasswordWire.id))))
        #expect(await transport.paths.contains("PUT /auth/v1/user"))
        for key in PasswordMemoryStorage.authKeys { #expect(try storage.retrieve(key: key) == nil) }
        #expect(!storage.containsPassword())
        try await auth.signInWithPassword(email: "fixture@example.test", password: "old")
        #expect(auth.state == .authenticated(.init(userID: PasswordWire.id)))
    }

    @Test(arguments: ["weak_password", "offline", "reauthentication_needed", "same_password"])
    func failedUpdateRetainsRecoveryAcrossRestartAndCanRetry(code: String) async throws {
        let storage = PasswordMemoryStorage()
        try seed(storage, recovery: true)
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        try await auth.restore()
        await transport.setUpdateFailure(code)
        do { try await auth.completePasswordReset(password: "fixture-new-password")
            Issue.record("Failed update accepted")
        } catch {
            let expected: PinTheoryAuthError = code == "offline" ? .networkUnavailable
                : (["weak_password", "same_password"].contains(code) ? .weakPassword : .signInFailed)
            #expect(error as? PinTheoryAuthError == expected)
            #expect(!error.localizedDescription.contains("private"))
        }
        #expect(auth.state == .passwordRecovery)
        #expect(!auth.isBusy)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) != nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) != nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
        await transport.setUpdateFailure(nil)
        let restarted = try service(storage, transport)
        try await restarted.restore()
        #expect(restarted.state == .passwordRecovery)
        try await restarted.completePasswordReset(password: "fixture-new-password")
        #expect(restarted.state == .signedOut)
    }

    @Test func exchangeFailureRetainsVerifierAndActivationForRetry() async throws {
        let storage = PasswordMemoryStorage()
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        try await auth.sendPasswordReset(email: "fixture@example.test")
        let verifier = try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey)
        await transport.setOffline(true)
        do { try await auth.handleCallback(URL(string: "golfpintheory://auth/reset-password?code=reset")!)
            Issue.record("Offline exchange succeeded")
        } catch { #expect(error is PinTheoryAuthError) }
        #expect(auth.state == .passwordRecovery)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == verifier)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) != nil)
        await transport.setOffline(false)
        let restarted = try service(storage, transport)
        try await restarted.restore()
        #expect(restarted.state == .passwordRecovery)
        try await restarted.handleCallback(URL(string: "golfpintheory://auth/reset-password?code=reset")!)
        #expect(restarted.state == .passwordRecovery)
        try restarted.signOut()
        for key in PasswordMemoryStorage.authKeys { #expect(try storage.retrieve(key: key) == nil) }
    }

    @Test(arguments: ["invalid_credentials", "email_not_confirmed", "weak_password", "user_not_found", "email_exists"])
    func passwordErrorsAreFixedAndNonEnumerating(code: String) async throws {
        let storage = PasswordMemoryStorage()
        let transport = PasswordFetch()
        await transport.setTokenFailure(code)
        let auth = try service(storage, transport)
        do { try await auth.signInWithPassword(email: "fixture@example.test", password: "old")
            Issue.record("Invalid credentials accepted")
        } catch {
            let expected: PinTheoryAuthError
            switch code {
            case "email_not_confirmed": expected = .emailNotConfirmed
            case "weak_password": expected = .weakPassword
            case "email_exists": expected = .signInFailed
            default: expected = .invalidCredentials
            }
            #expect(error as? PinTheoryAuthError == expected)
            #expect(!error.localizedDescription.contains("private"))
            #expect(!error.localizedDescription.contains("fixture@example.test"))
        }
        #expect(auth.state == .signedOut)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
    }

    @Test(arguments: ["POST /auth/v1/token", "PUT /auth/v1/user"])
    func logoutRejectsLateExchangeOrUpdate(path: String) async throws {
        let storage = PasswordMemoryStorage()
        let transport = PasswordFetch()
        let gate = PasswordRequestGate()
        let auth = try service(storage, transport)
        if path.hasPrefix("PUT") {
            try seed(storage, recovery: true)
            try await auth.restore()
        } else {
            try await auth.sendPasswordReset(email: "fixture@example.test")
        }
        await transport.setGate(gate, path: path)
        let operation = Task { @MainActor in
            if path.hasPrefix("PUT") { try await auth.completePasswordReset(password: "fixture-new-password") }
            else { try await auth.handleCallback(URL(string: "golfpintheory://auth/reset-password?code=late")!) }
        }
        await gate.waitUntilEntered()
        try auth.signOut()
        // A newer ordinary login must not be overwritten by the old SDK lease.
        await transport.setGate(nil, path: nil)
        try await auth.signInWithPassword(email: "fixture@example.test", password: "old")
        let bytes = try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey)
        await gate.release()
        do { try await operation.value; Issue.record("Late recovery operation succeeded") }
        catch { #expect(error as? PinTheoryAuthError == .cancelled) }
        #expect(auth.state == .authenticated(.init(userID: PasswordWire.id)))
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == bytes)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) == nil)
        #expect(!auth.isBusy)
    }

    @Test func signupServerFailureIsNotReportedAsOffline() async throws {
        let configuration = try PinTheoryAuthConfiguration(
            projectURL: URL(string: "https://password.example.test")!,
            publishableKey: "sb_publishable_password_fixture")
        let auth = PinTheoryAuthService(configuration: configuration, storage: PasswordMemoryStorage(),
            fetch: { request in
                throw AuthError.api(message: "private provider detail", errorCode: .unexpectedFailure,
                    underlyingData: Data(), underlyingResponse: HTTPURLResponse(
                        url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
            })
        do {
            _ = try await auth.signUpWithPassword(email: "fixture@example.test", password: "fixture-password")
            Issue.record("Server failure was accepted")
        } catch {
            #expect(error as? PinTheoryAuthError == .accountServiceUnavailable)
            #expect(!error.localizedDescription.contains("-1009"))
            #expect(!error.localizedDescription.contains("private"))
        }
    }

    @Test func googleCannotConsumeRecoveryDestination() async throws {
        let storage = PasswordMemoryStorage()
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        do {
            try await auth.signInWithGoogle { _ in URL(string: "golfpintheory://auth/reset-password?code=wrong-flow")! }
            Issue.record("Google accepted a reset URL")
        } catch { #expect(error as? PinTheoryAuthError == .googleOAuthCallbackFailed) }
        #expect(await transport.paths.isEmpty)
        #expect(auth.state == .signedOut)
    }

    @Test(arguments: [PinTheoryAuthStorageLease.recoveryKey, PinTheoryAuthStorageLease.confirmationKey])
    func failedRecoveryGateStorageNeverReachesExchange(key: String) async throws {
        let storage = PasswordMemoryStorage()
        try storage.store(key: PinTheoryAuthStorageLease.verifierKey, value: Data("fixture-verifier".utf8))
        storage.setFailure(key)
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        do { try await auth.handleCallback(URL(string: "golfpintheory://auth/reset-password?code=reset")!)
            Issue.record("Storage gate failure was ignored")
        } catch { #expect(error as? PinTheoryAuthError == .secureStorageUnavailable) }
        #expect(await transport.paths.isEmpty)
        #expect(auth.state == .signedOut)
        #expect(!auth.isBusy)
        storage.setFailure(nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) != nil)
        if key == PinTheoryAuthStorageLease.confirmationKey {
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) != nil)
        }
    }

    @Test func failedLogoutKeepsRecoveryMarkerUntilCredentialDeletionSucceeds() async throws {
        let storage = PasswordMemoryStorage()
        try seed(storage, recovery: true)
        let transport = PasswordFetch()
        let auth = try service(storage, transport)
        try await auth.restore()
        storage.setFailure(PinTheoryAuthStorageLease.sessionKey)
        #expect(throws: PinTheoryAuthError.secureStorageUnavailable) { try auth.signOut() }
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) != nil)
        #expect(auth.lastError == .secureStorageUnavailable)
        storage.setFailure(nil)
        try auth.signOut()
        for key in PasswordMemoryStorage.authKeys { #expect(try storage.retrieve(key: key) == nil) }
    }

    @Test(arguments: [false, true])
    func serverUserMismatchCannotAuthenticateOrUpdate(recovery: Bool) async throws {
        let storage = PasswordMemoryStorage()
        let transport = PasswordFetch()
        await transport.setDifferentUser()
        let auth = try service(storage, transport)
        if recovery { try seed(storage, recovery: true) }
        do {
            if recovery { try await auth.restore() }
            else { try await auth.signInWithPassword(email: "fixture@example.test", password: "old") }
            Issue.record("Mismatched server identity accepted")
        } catch { #expect(error is PinTheoryAuthError) }
        #expect(auth.state == (recovery ? .passwordRecovery : .signedOut))
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
        #expect(!(await transport.paths).contains("PUT /auth/v1/user"))
    }
}

nonisolated private enum PasswordWire {
    static let id = UUID(uuidString: "D6E18B9C-075F-4B46-9702-F718A80D23C1")!
    static var session: Session {
        let now = Date()
        return Session(accessToken: "fixture-access", tokenType: "bearer", expiresIn: 3600,
            expiresAt: now.addingTimeInterval(3600).timeIntervalSince1970, refreshToken: "fixture-refresh",
            user: User(id: id, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, updatedAt: now))
    }
    static func user() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "aud": "authenticated",
            "created_at": "2026-10-21T12:00:00Z", "updated_at": "2026-10-21T12:00:00Z"])
    }
    static func sessionBody() throws -> Data {
        let user = try JSONSerialization.jsonObject(with: user())
        return try JSONSerialization.data(withJSONObject: ["user": user, "access_token": "fixture-access",
            "refresh_token": "fixture-refresh", "token_type": "bearer", "expires_in": 3600,
            "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970])
    }
}

private actor PasswordFetch {
    private(set) var paths: [String] = []
    private var confirmation = false
    private var offline = false
    private var recoveryMarkerRequired = false
    private var tokenFailure: String?
    private var updateFailure: String?
    private var gate: PasswordRequestGate?
    private var gatedPath: String?
    private var differentUser = false
    func setConfirmation(_ value: Bool) { confirmation = value }
    func setOffline(_ value: Bool) { offline = value }
    func setTokenFailure(_ value: String?) { tokenFailure = value }
    func setUpdateFailure(_ value: String?) { updateFailure = value }
    func requireRecoveryMarker() { recoveryMarkerRequired = true }
    func setDifferentUser() { differentUser = true }
    func setGate(_ value: PasswordRequestGate?, path: String?) { gate = value; gatedPath = path }

    func respond(_ request: URLRequest, storage: PasswordMemoryStorage) async throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let path = "\(request.httpMethod ?? "") \(url.path)"
        paths.append(path)
        #expect(url.host == "password.example.test")
        let responseGate = path == gatedPath ? gate : nil
        if offline { throw URLError(.notConnectedToInternet) }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let json: [String: Any]?
        if let data = request.httpBody { json = try JSONSerialization.jsonObject(with: data) as? [String: Any] }
        else { json = nil }
        var body = Data("{}".utf8)
        var failure: String?
        switch path {
        case "POST /auth/v1/token":
            let grant = query.first { $0.name == "grant_type" }?.value
            #expect(grant == "password" || grant == "pkce")
            if grant == "password" {
                #expect(json?["email"] as? String == "fixture@example.test")
                #expect(json?["password"] as? String == "old")
            } else {
                #expect((json?["code_verifier"] as? String)?.isEmpty == false)
                if recoveryMarkerRequired {
                    #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) == Data("1".utf8))
                    #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
                }
            }
            failure = tokenFailure
            body = try PasswordWire.sessionBody()
        case "POST /auth/v1/signup", "POST /auth/v1/recover", "POST /auth/v1/resend":
            #expect(json?["email"] as? String == "fixture@example.test")
            #expect((json?["code_challenge"] as? String)?.isEmpty == false)
            #expect(json?["code_challenge_method"] as? String == "s256")
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) != nil)
            let redirect = path.hasSuffix("recover") ? "golfpintheory://auth/reset-password" : "golfpintheory://auth/callback"
            #expect(query.first { $0.name == "redirect_to" }?.value == redirect)
            if path.hasSuffix("signup") {
                #expect(json?["password"] as? String == "fixture-new-password")
                if confirmation { body = try PasswordWire.user() }
                else { body = try PasswordWire.sessionBody() }
            }
            if path.hasSuffix("resend") { #expect(json?["type"] as? String == "signup") }
        case "GET /auth/v1/user":
            body = try PasswordWire.user()
            if differentUser {
                body = Data(String(decoding: body, as: UTF8.self)
                    .replacingOccurrences(of: PasswordWire.id.uuidString, with: UUID().uuidString).utf8)
            }
        case "PUT /auth/v1/user":
            #expect(json?["password"] as? String == "fixture-new-password")
            #expect(json?["email"] == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access")
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.recoveryKey) != nil)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
            if updateFailure == "offline" { throw URLError(.notConnectedToInternet) }
            failure = updateFailure
            body = try PasswordWire.user()
        default: Issue.record("Unexpected intercepted auth request"); throw URLError(.badServerResponse)
        }
        if let failure {
            body = try JSONSerialization.data(withJSONObject: ["code": failure,
                "msg": "private fixture@example.test https://example.test/?token=private"])
        }
        // Validate request-time storage before simulating a response that arrives
        // after logout; the old request must not demand markers from a new login.
        if let responseGate { await responseGate.suspend() }
        return (body, HTTPURLResponse(url: url, statusCode: failure == nil ? 200 : 400, httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "X-Supabase-Api-Version": "2024-01-01"])!)
    }
}

private actor PasswordRequestGate {
    private var entered = false
    private var listener: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?
    func suspend() async {
        entered = true
        listener?.resume(); listener = nil
        await withCheckedContinuation { blocked = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { listener = $0 }
    }
    func release() { blocked?.resume(); blocked = nil }
}

nonisolated private final class PasswordMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    static let authKeys = [PinTheoryAuthStorageLease.sessionKey, PinTheoryAuthStorageLease.verifierKey,
        PinTheoryAuthStorageLease.confirmationKey, PinTheoryAuthStorageLease.recoveryKey,
        PinTheoryAuthStorageLease.pendingRecoveryKey]
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var failedKey: String?
    func setFailure(_ key: String?) { lock.lock(); defer { lock.unlock() }; failedKey = key }
    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if failedKey == key { throw PinTheoryAuthError.secureStorageUnavailable }
        values[key] = value
    }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if failedKey == key { throw PinTheoryAuthError.secureStorageUnavailable }
        values[key] = nil
    }
    func containsPassword() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return values.values.contains { String(decoding: $0, as: UTF8.self).contains("fixture-new-password") }
    }
}