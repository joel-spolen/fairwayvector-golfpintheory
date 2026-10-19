import Auth
import AuthenticationServices
import Foundation
import Testing
@testable import fairwayvector_pintheory

/// Source only: no Keychain access, browser, live sign-in or test execution.
@MainActor
struct AccountAuthTests {
    private func configuration() throws -> PinTheoryAuthConfiguration {
        try PinTheoryAuthConfiguration(projectURL: URL(string: "https://staging.example.test/")!,
                                       publishableKey: "sb_publishable_fixture_only")
    }

    private func session(id: UUID = UUID(), expired: Bool = false) -> Session {
        let now = Date()
        let user = User(id: id, appMetadata: [:], userMetadata: [:], aud: "authenticated",
                        createdAt: now, updatedAt: now)
        // Deliberately NOT a JWT. A local subject must never grant cloud access.
        return Session(accessToken: "unverified-local-token", tokenType: "bearer", expiresIn: 3600,
                       expiresAt: now.addingTimeInterval(expired ? -3600 : 3600).timeIntervalSince1970,
                       refreshToken: "fixture-refresh", user: user)
    }

    private func seed(_ session: Session, confirmed: UUID?, storage: AuthMemoryStorage) throws {
        try storage.store(key: PinTheoryAuthStorageLease.sessionKey, value: JSONEncoder().encode(session))
        if let confirmed {
            try storage.store(key: PinTheoryAuthStorageLease.confirmationKey, value: Data(confirmed.uuidString.utf8))
        }
    }

    private func userResponse(id: UUID) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "aud": "authenticated",
            "app_metadata": [:], "user_metadata": [:], "created_at": "2026-10-19T12:00:00Z",
            "updated_at": "2026-10-19T12:00:00Z"] as [String: Any])
    }

    @Test func configurationIsOptInAndStrict() throws {
        #expect(try PinTheoryAuthConfiguration.load(projectURL: nil, publishableKey: nil) == nil)
        #expect(try PinTheoryAuthConfiguration.load(projectURL: "  ", publishableKey: "sb_publishable_test") == nil)
        #expect(try PinTheoryAuthConfiguration.load(projectURL: "https://example.test", publishableKey: "\n") == nil)
        let value = try configuration()
        #expect(value.projectURL.absoluteString == "https://staging.example.test")
        #expect(PinTheoryAuthConfiguration.callbackURL.absoluteString == "pintheory://auth/callback")
        for url in ["http://example.test", "https://user:pass@example.test", "https://example.test/auth/v1",
                    "https://example.test/?q=value", "https://example.test/#fragment", "https://example.test:444",
                    "https://example.test/%2F", "https://example..test"] {
            #expect(throws: PinTheoryAuthError.self) {
                try PinTheoryAuthConfiguration(projectURL: URL(string: url)!, publishableKey: value.publishableKey)
            }
        }
        for key in ["", "sb_publishable_", "sb_secret_fixture", "eyJhbGciOiJIUzI1NiJ9.fixture",
                    "service_role", "sb_publishable_has space", "sb_publishable_\n", "$(AUTH_KEY)"] {
            #expect(throws: PinTheoryAuthError.self) {
                try PinTheoryAuthConfiguration(projectURL: value.projectURL, publishableKey: key)
            }
        }
    }

    @Test func callbackRequiresExactDestinationAndOnePKCECode() throws {
        try PinTheoryAuthConfiguration.validateCallback(URL(string: "pintheory://auth/callback?code=fixture")!)
        for url in ["other://auth/callback?code=x", "pintheory://other/callback?code=x",
                    "pintheory://auth/callback/?code=x", "pintheory://auth/%63allback?code=x",
                    "pintheory://user@auth/callback?code=x", "pintheory://auth:443/callback?code=x",
                    "pintheory://auth/callback?code=x#access_token=secret", "pintheory://auth/callback",
                    "pintheory://auth/callback?code=", "pintheory://auth/callback?code=x&code=y",
                    "pintheory://auth/callback?error_description=expired", "https://auth/callback?code=x"] {
            #expect(throws: PinTheoryAuthError.self) {
                try PinTheoryAuthConfiguration.validateCallback(URL(string: url)!)
            }
        }
    }

    @Test func revokedLeaseCannotWriteReadOrDeleteNewSession() throws {
        let storage = AuthMemoryStorage()
        let old = PinTheoryAuthStorageLease(storage: storage)
        try old.store(key: PinTheoryAuthStorageLease.sessionKey, value: Data("old".utf8))
        old.revoke()
        let new = PinTheoryAuthStorageLease(storage: storage)
        let bytes = Data("new".utf8)
        try new.store(key: PinTheoryAuthStorageLease.sessionKey, value: bytes)
        #expect(try old.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == nil)
        #expect(throws: PinTheoryAuthError.self) {
            try old.store(key: PinTheoryAuthStorageLease.sessionKey, value: Data("late".utf8))
        }
        try old.remove(key: PinTheoryAuthStorageLease.sessionKey)
        #expect(try new.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == bytes)
        try storage.store(key: "supabase.session", value: Data("legacy".utf8))
        #expect(try new.retrieve(key: "supabase.session") == nil)
    }

    @Test func offlineRestorationRequiresServerConfirmationAndMatchingUID() async throws {
        let local = session(expired: true)
        let storage = AuthMemoryStorage()
        try seed(local, confirmed: local.user.id, storage: storage)
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage,
                                          fetch: { _ in throw URLError(.notConnectedToInternet) })
        try await service.restore()
        #expect(service.state == .offlineCachedIdentity(.init(userID: local.user.id)))
        do {
            _ = try await service.authenticatedAccessToken(for: local.user.id)
            Issue.record("Offline identity returned a cloud token")
        } catch { #expect(error as? PinTheoryAuthError == .authenticationRequired) }
        try service.signOut()
        #expect(service.state == .signedOut)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)

        for marker in [Optional<UUID>.none, UUID()] {
            let untrusted = AuthMemoryStorage()
            try seed(local, confirmed: marker, storage: untrusted)
            let blocked = PinTheoryAuthService(configuration: try configuration(), storage: untrusted,
                                              fetch: { _ in throw URLError(.notConnectedToInternet) })
            do { try await blocked.restore(); Issue.record("Unconfirmed/mismatched identity restored offline") }
            catch { #expect(error is PinTheoryAuthError) }
            #expect(blocked.state == .signedOut)
        }
    }

    @Test func freshRestorePreservesPendingEmailVerifierForColdStartLink() async throws {
        let storage = AuthMemoryStorage()
        let verifier = Data("pending-email-verifier".utf8)
        try storage.store(key: PinTheoryAuthStorageLease.verifierKey, value: verifier)
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage,
                                          fetch: { _ in throw URLError(.notConnectedToInternet) })
        try await service.restore()
        #expect(service.state == .signedOut)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == verifier)
    }

    @Test func freshOfflineInstallationRemainsSignedOut() async throws {
        let service = PinTheoryAuthService(configuration: try configuration(), storage: AuthMemoryStorage(),
                                          fetch: { _ in throw URLError(.notConnectedToInternet) })
        try await service.restore()
        #expect(service.state == .signedOut)
    }

    @Test(arguments: [408, 429, 500, 503, 599], [false, true])
    func transientAPIFailuresRetainConfirmedAccount(status: Int, expired: Bool) async throws {
        let local = session(expired: expired)
        let storage = AuthMemoryStorage()
        try seed(local, confirmed: local.user.id, storage: storage)
        let bytes = try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey)
        let marker = try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey)
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
            // Cover both /token refresh and /user confirmation API failures.
            throw AuthError.api(message: "private server detail", errorCode: .unexpectedFailure,
                                underlyingData: Data(), underlyingResponse: HTTPURLResponse(
                                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        try await service.restore()
        #expect(service.state == .offlineCachedIdentity(.init(userID: local.user.id)))
        do {
            _ = try await service.authenticatedAccessToken(for: local.user.id)
            Issue.record("Transient failure returned a cloud token")
        } catch { #expect(error as? PinTheoryAuthError == .authenticationRequired) }
        #expect(service.state == .offlineCachedIdentity(.init(userID: local.user.id)))
        #expect(!service.isBusy)
        #expect(storage.removalCount == 0)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == bytes)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == marker)
    }

    @Test func storageRetryPreservesReadFailuresThenRestoresWithoutLogout() async throws {
        for failedKey in [PinTheoryAuthStorageLease.sessionKey, PinTheoryAuthStorageLease.confirmationKey,
                          PinTheoryAuthStorageLease.verifierKey] {
            let local = session()
            let storage = AuthMemoryStorage()
            try seed(local, confirmed: local.user.id, storage: storage)
            let verifier = Data("outstanding-magic-link-verifier".utf8)
            try storage.store(key: PinTheoryAuthStorageLease.verifierKey, value: verifier)
            let bytes = try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey)
            let marker = try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey)
            let body = try userResponse(id: local.user.id)
            storage.setFailRetrievals(for: PinTheoryAuthStorageLease.sessionKey)
            let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
                (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            do { try await service.restore(); Issue.record("Storage read error was ignored") }
            catch { #expect(error as? PinTheoryAuthError == .secureStorageUnavailable) }
            storage.setFailRetrievals(for: failedKey)
            do { try await service.retrySecureStorage(); Issue.record("Retry ignored storage read error") }
            catch { #expect(error as? PinTheoryAuthError == .secureStorageUnavailable) }
            #expect(service.state == .signedOut)
            #expect(service.lastError == .secureStorageUnavailable)
            #expect(!service.isBusy)
            #expect(storage.removalCount == 0)
            storage.setFailRetrievals(for: nil)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == bytes)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == marker)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == verifier)
            try await service.retrySecureStorage()
            #expect(service.state == .authenticated(.init(userID: local.user.id)))
            #expect(service.lastError == nil)
            #expect(!service.isBusy)
            #expect(storage.removalCount == 0)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == verifier)
        }
    }

    @Test func server503AfterOnlineConfirmationRetainsAccountButDeniesCloudToken() async throws {
        let local = session()
        let storage = AuthMemoryStorage()
        try seed(local, confirmed: nil, storage: storage)
        let user = try userResponse(id: local.user.id)
        let failure = AuthHTTPFailure()
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
            let status = await failure.status ?? 200
            let body = status == 200 ? user : Data("{\"message\":\"temporarily unavailable\"}".utf8)
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        try await service.restore()
        #expect(service.state == .authenticated(.init(userID: local.user.id)))
        let bytes = try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey)
        let marker = try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey)
        await failure.setStatus(503)
        do { _ = try await service.authenticatedAccessToken(for: local.user.id)
            Issue.record("503 allowed a cloud token")
        } catch { #expect(error as? PinTheoryAuthError == .authenticationRequired) }
        #expect(service.state == .offlineCachedIdentity(.init(userID: local.user.id)))
        #expect(storage.removalCount == 0)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == bytes)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == marker)
        await failure.setStatus(nil)
        #expect(try await service.authenticatedAccessToken(for: local.user.id) == local.accessToken)
        #expect(service.state == .authenticated(.init(userID: local.user.id)))
    }

    @Test(arguments: [400, 401, 403], [false, true])
    func invalidGrantsClearConfirmedCredentials(status: Int, expired: Bool) async throws {
        let local = session(expired: expired)
        let storage = AuthMemoryStorage()
        try seed(local, confirmed: local.user.id, storage: storage)
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
            throw AuthError.api(message: "private invalid grant", errorCode: ErrorCode("invalid_grant"),
                                underlyingData: Data(), underlyingResponse: HTTPURLResponse(
                                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        do { try await service.restore(); Issue.record("Invalid grant restored account") }
        catch { #expect(error as? PinTheoryAuthError == .signInFailed) }
        #expect(service.state == .signedOut)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
    }

    @Test func restoreRetrievalFailuresPreserveSessionAndConfirmationAndLockService() async throws {
        for key in [PinTheoryAuthStorageLease.sessionKey, PinTheoryAuthStorageLease.confirmationKey] {
            let local = session()
            let storage = AuthMemoryStorage()
            try seed(local, confirmed: local.user.id, storage: storage)
            let bytes = try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey)
            let confirmation = try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey)
            storage.setFailRetrievals(for: key)
            let service = PinTheoryAuthService(configuration: try configuration(), storage: storage,
                                              fetch: { _ in
                Issue.record("Storage failure must not reach the auth server")
                throw URLError(.badServerResponse)
            })
            do { try await service.restore(); Issue.record("Unavailable storage interpreted as signed out") }
            catch { #expect(error as? PinTheoryAuthError == .secureStorageUnavailable) }
            #expect(service.state == .signedOut)
            #expect(!service.isBusy)
            #expect(service.lastError == .secureStorageUnavailable)
            #expect(storage.removalCount == 0)

            storage.setFailRetrievals(for: nil)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == bytes)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == confirmation)
            // Storage becoming readable must not silently unlock the old SDK client.
            do { try await service.restore(); Issue.record("Storage-locked service restarted implicitly") }
            catch { #expect(error as? PinTheoryAuthError == .secureStorageUnavailable) }
            #expect(storage.removalCount == 0)
        }
    }

    @Test func invalidStoredSessionPreservesOriginalBytesAndConfirmation() async throws {
        for bytes in [Data("not-json".utf8), Data("{}".utf8)] {
            let storage = AuthMemoryStorage()
            let confirmation = Data(UUID().uuidString.utf8)
            try storage.store(key: PinTheoryAuthStorageLease.sessionKey, value: bytes)
            try storage.store(key: PinTheoryAuthStorageLease.confirmationKey, value: confirmation)
            let service = PinTheoryAuthService(configuration: try configuration(), storage: storage,
                                              fetch: { _ in
                Issue.record("Invalid stored session must not reach the auth server")
                throw URLError(.badServerResponse)
            })
            do { try await service.restore(); Issue.record("Invalid stored session interpreted as absent") }
            catch { #expect(error as? PinTheoryAuthError == .secureStorageUnavailable) }
            #expect(service.state == .signedOut)
            #expect(!service.isBusy)
            #expect(service.lastError == .secureStorageUnavailable)
            #expect(storage.removalCount == 0)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == bytes)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == confirmation)
            do { try await service.restore(); Issue.record("Invalid-session lock was bypassed") }
            catch { #expect(error as? PinTheoryAuthError == .secureStorageUnavailable) }
            do { try await service.retrySecureStorage(); Issue.record("Retry accepted invalid stored bytes") }
            catch { #expect(error as? PinTheoryAuthError == .secureStorageUnavailable) }
            #expect(storage.removalCount == 0)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == bytes)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == confirmation)
        }
    }

    @Test func onlineRestoreConfirmsServerUIDAndTokenMethodChecksAgain() async throws {
        let local = session()
        let storage = AuthMemoryStorage()
        try seed(local, confirmed: nil, storage: storage)
        let body = try userResponse(id: local.user.id)
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
            guard request.url?.path == "/auth/v1/user",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer unverified-local-token" else {
                throw URLError(.badServerResponse)
            }
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        try await service.restore()
        #expect(service.state == .authenticated(.init(userID: local.user.id)))
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == Data(local.user.id.uuidString.utf8))
        #expect(try await service.authenticatedAccessToken(for: local.user.id) == local.accessToken)
        do { _ = try await service.authenticatedAccessToken(for: UUID()); Issue.record("Cross-account token exposed") }
        catch { #expect(error as? PinTheoryAuthError == .authenticationRequired) }
    }

    @Test func differentServerUserAndKnownRevocationFailClosed() async throws {
        let local = session()
        let differentUser = try userResponse(id: UUID())
        for status in [200, 401, 403] {
            let storage = AuthMemoryStorage()
            try seed(local, confirmed: local.user.id, storage: storage)
            let body = status == 200 ? differentUser : Data("{\"message\":\"private server detail\"}".utf8)
            let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
                (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
            do { try await service.restore(); Issue.record("Untrusted server identity accepted") }
            catch {
                #expect(error is PinTheoryAuthError)
                #expect(!error.localizedDescription.contains("private server detail"))
            }
            #expect(service.state == .signedOut)
            #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
        }
    }

    @Test func emailCodeEstablishesSessionOnlyAfterServerConfirmation() async throws {
        let id = UUID()
        let storage = AuthMemoryStorage()
        let user = try userResponse(id: id)
        let userObject = try #require(JSONSerialization.jsonObject(with: user) as? [String: Any])
        let signedIn = try JSONSerialization.data(withJSONObject: ["user": userObject,
            "access_token": "fixture-server-token", "refresh_token": "fixture-server-refresh",
            "token_type": "bearer", "expires_in": 3600,
            "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970] as [String: Any])
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
            let body: Data
            switch request.url?.path {
            case "/auth/v1/verify": body = signedIn
            case "/auth/v1/user": body = user
            default: throw URLError(.badServerResponse)
            }
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        try await service.verifyEmailCode(email: "fixture@example.test", code: "123456")
        #expect(service.state == .authenticated(.init(userID: id)))
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == Data(id.uuidString.utf8))
        try service.signOut()
        #expect(service.state == .signedOut)
    }

    @Test func expiredEmailCodeDoesNotExposeServerDetailsOrPersistConfirmation() async throws {
        let storage = AuthMemoryStorage()
        let body = Data("{\"message\":\"expired private callback https://example.test/?code=secret\"}".utf8)
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
            (body, HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!)
        })
        do {
            try await service.verifyEmailCode(email: "fixture@example.test", code: "expired")
            Issue.record("Expired code accepted")
        } catch {
            #expect(error as? PinTheoryAuthError == .signInFailed)
            #expect(!error.localizedDescription.contains("secret"))
            #expect(!error.localizedDescription.contains("https://"))
        }
        #expect(service.state == .signedOut)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
    }

    @Test func wrongOTPPreservesVerifierButCannotOpenAccountGate() async throws {
        let storage = AuthMemoryStorage()
        let verifier = Data("outstanding-magic-link-verifier".utf8)
        try storage.store(key: PinTheoryAuthStorageLease.verifierKey, value: verifier)
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
            #expect(request.url?.path == "/auth/v1/verify")
            return (Data("{\"message\":\"wrong OTP\",\"error_code\":\"otp_expired\"}".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        })
        do { try await service.verifyEmailCode(email: "fixture@example.test", code: "wrong")
            Issue.record("Wrong OTP accepted")
        } catch { #expect(error as? PinTheoryAuthError == .signInFailed) }
        #expect(service.state == .signedOut)
        #expect(!service.isBusy)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == verifier)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
        try await service.restore()
        #expect(service.state == .signedOut)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == verifier)
        try service.signOut()
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == nil)
    }

    @Test func OTPConfirmationFailureDiscardsUnconfirmedPartialSessionAndVerifier() async throws {
        let local = session()
        let storage = AuthMemoryStorage()
        try storage.store(key: PinTheoryAuthStorageLease.verifierKey, value: Data("pending-verifier".utf8))
        let user = try userResponse(id: local.user.id)
        let userObject = try #require(JSONSerialization.jsonObject(with: user) as? [String: Any])
        let signedIn = try JSONSerialization.data(withJSONObject: ["user": userObject,
            "access_token": local.accessToken, "refresh_token": local.refreshToken,
            "token_type": "bearer", "expires_in": 3600,
            "expires_at": local.expiresAt] as [String: Any])
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage, fetch: { request in
            if request.url?.path == "/auth/v1/verify" {
                return (signedIn, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            #expect(request.url?.path == "/auth/v1/user")
            throw AuthError.api(message: "unavailable", errorCode: .unexpectedFailure,
                                underlyingData: Data(), underlyingResponse: HTTPURLResponse(
                                    url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        })
        do { try await service.verifyEmailCode(email: "fixture@example.test", code: "123456")
            Issue.record("Unconfirmed session accepted")
        } catch { #expect(error as? PinTheoryAuthError == .signInFailed) }
        #expect(service.state == .signedOut)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.confirmationKey) == nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == nil)
        try await service.restore()
        #expect(service.state == .signedOut)
    }

    @Test func googleLateCallbackAfterLogoutCannotCreateSession() async throws {
        let storage = AuthMemoryStorage()
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage,
                                          fetch: { _ in throw URLError(.badServerResponse) })
        do {
            try await service.signInWithGoogle { _ in
                try service.signOut()
                return URL(string: "pintheory://auth/callback?code=late")!
            }
            Issue.record("Late callback accepted")
        } catch { #expect(error as? PinTheoryAuthError == .cancelled) }
        #expect(service.state == .signedOut)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.sessionKey) == nil)
        #expect(try storage.retrieve(key: PinTheoryAuthStorageLease.verifierKey) == nil)
    }

    @Test func staleAppleFailureOrCancellationCannotConsumeNewerRequest() async throws {
        let storage = AuthMemoryStorage()
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage,
                                          fetch: { _ in
            Issue.record("Apple failure callbacks must not reach the auth server")
            throw URLError(.badServerResponse)
        })
        let provider = ASAuthorizationAppleIDProvider()
        let requestA = provider.createRequest()
        let ticketA = try service.prepareAppleRequest(requestA)
        try service.signOut()
        let requestB = provider.createRequest()
        let ticketB = try service.prepareAppleRequest(requestB)
        #expect(ticketA != ticketB)
        #expect(requestB.state == String(ticketB))
        let nonceB = requestB.nonce
        let removals = storage.removalCount

        let errors: [Error] = [URLError(.badServerResponse), ASAuthorizationError(.canceled)]
        for error in errors {
            do {
                try await service.completeAppleSignIn(.failure(error), requestID: ticketA)
                Issue.record("Stale Apple callback accepted")
            } catch { #expect(error as? PinTheoryAuthError == .cancelled) }
            #expect(service.isBusy)
            #expect(service.state == .signedOut)
            #expect(service.lastError == nil)
            #expect(requestB.nonce == nonceB)
            #expect(storage.removalCount == removals)
        }

        // B's own cancellation must still consume B and finish its operation.
        do {
            try await service.completeAppleSignIn(.failure(ASAuthorizationError(.canceled)), requestID: ticketB)
            Issue.record("Apple cancellation accepted as success")
        } catch { #expect(error as? PinTheoryAuthError == .cancelled) }
        #expect(!service.isBusy)
        #expect(service.lastError == .cancelled)
        #expect(storage.removalCount == removals + 3)
    }

    @Test func storageFailureOnLogoutIsReportedAndLocksCurrentService() throws {
        let storage = AuthMemoryStorage()
        let service = PinTheoryAuthService(configuration: try configuration(), storage: storage,
                                          fetch: { _ in throw URLError(.notConnectedToInternet) })
        storage.setFailRemovals(true)
        #expect(throws: PinTheoryAuthError.self) { try service.signOut() }
        #expect(service.state == .signedOut)
        #expect(service.lastError == .secureStorageUnavailable)
        storage.setFailRemovals(false)
        try service.signOut()
        #expect(service.lastError == nil)
    }
}

private actor AuthHTTPFailure {
    private(set) var status: Int?

    func setStatus(_ status: Int?) { self.status = status }
}

/// Synchronous Sendable injection matching the official SDK storage protocol.
nonisolated private final class AuthMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var failRemovals = false
    private var failedRetrievalKey: String?
    private var removals = 0

    var removalCount: Int {
        lock.lock(); defer { lock.unlock() }
        return removals
    }

    func setFailRetrievals(for key: String?) {
        lock.lock(); defer { lock.unlock() }
        failedRetrievalKey = key
    }

    func setFailRemovals(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        failRemovals = value
    }

    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        // Deliberately not a service error: retrieval failures must be sanitized,
        // not mistaken for connectivity failures eligible for offline identity.
        if failedRetrievalKey == key { throw URLError(.notConnectedToInternet) }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        removals += 1
        if failRemovals { throw PinTheoryAuthError.secureStorageUnavailable }
        values[key] = nil
    }
}