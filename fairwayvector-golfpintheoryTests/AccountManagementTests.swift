import Auth
import Foundation
import Testing
@testable import fairwayvector_golfpintheory

/// SOURCE ONLY. Every request is intercepted; no real account, Keychain, or endpoint is used.
@MainActor
struct AccountManagementTests {
    private func service(_ transport: AccountManagementFetch) throws -> PinTheoryAuthService {
        let configuration = try PinTheoryAuthConfiguration(
            projectURL: URL(string: "https://management.example.test")!,
            publishableKey: "sb_publishable_management_fixture")
        return PinTheoryAuthService(configuration: configuration, storage: AccountManagementStorage(),
            fetch: { try await transport.respond($0) },
            deletionFetch: { try await transport.respond($0) },
            deletionEndpointAvailable: true)
    }

    @Test func accountDetailsExposeOnlyVerifiedEmailAndProviderNames() async throws {
        let transport = AccountManagementFetch()
        let auth = try service(transport)
        try await auth.signInWithPassword(email: AccountManagementWire.email, password: "fixture-password")
        let details = try await auth.accountDetails()
        #expect(details.email == AccountManagementWire.email)
        #expect(details.pendingEmail == nil)
        #expect(details.providers == ["email", "google"])
        #expect(details.supportsEmailManagement)
        #expect(details.firstName.isEmpty)
        #expect(details.lastName.isEmpty)
        #expect(details.displayName.isEmpty)
        #expect(auth.state == .authenticated(.init(userID: AccountManagementWire.id)))
        #expect(!(await transport.paths).contains { $0.contains("password") })
    }

    @Test func accountDetailsUseGoogleIdentityNameWhenNoNameWasSaved() async throws {
        let transport = AccountManagementFetch()
        await transport.setGoogleIdentityData([
            "name": "Ada Lovelace",
            "given_name": "Ada",
            "family_name": "Lovelace",
        ])
        let auth = try service(transport)
        try await auth.signInWithPassword(email: AccountManagementWire.email, password: "fixture-password")
        let details = try await auth.accountDetails()
        #expect(details.firstName == "Ada")
        #expect(details.lastName == "Lovelace")
        #expect(details.displayName == "Ada Lovelace")
    }

    @Test func emailAccountCanSaveOptionalDisplayNameToAuthMetadata() async throws {
        let transport = AccountManagementFetch()
        let auth = try service(transport)
        try await auth.signInWithPassword(email: AccountManagementWire.email, password: "fixture-password")
        let updated = try await auth.updateDisplayName(firstName: " Ada ", lastName: "Lovelace ")
        #expect(updated.firstName == "Ada")
        #expect(updated.lastName == "Lovelace")
        #expect(updated.displayName == "Ada Lovelace")
        #expect(await transport.savedMetadata["display_name"] as? String == "Ada Lovelace")
        #expect(await transport.savedMetadata["first_name"] as? String == "Ada")
        #expect(await transport.savedMetadata["last_name"] as? String == "Lovelace")
    }

    @Test func displayNameCanBeCleared() async throws {
        let transport = AccountManagementFetch()
        let auth = try service(transport)
        try await auth.signInWithPassword(email: AccountManagementWire.email, password: "fixture-password")
        let updated = try await auth.updateDisplayName(firstName: "", lastName: "")
        #expect(updated.firstName.isEmpty)
        #expect(updated.lastName.isEmpty)
        #expect(updated.displayName.isEmpty)
        #expect(await transport.savedMetadata["display_name"] is NSNull)
    }

    @Test func displayNameLengthIsValidatedBeforeNetworkRequest() async throws {
        let transport = AccountManagementFetch()
        let auth = try service(transport)
        try await auth.signInWithPassword(email: AccountManagementWire.email, password: "fixture-password")
        let pathCount = await transport.paths.count
        do {
            _ = try await auth.updateDisplayName(firstName: String(repeating: "a", count: 81), lastName: "")
            Issue.record("Overlong name was accepted")
        } catch { #expect(error as? PinTheoryAuthError == .invalidDisplayName) }
        #expect(await transport.paths.count == pathCount)
    }

    @Test func passwordChangeFreshlyAuthenticatesAndKeepsSameAccount() async throws {
        let transport = AccountManagementFetch()
        let auth = try service(transport)
        try await auth.signInWithPassword(email: AccountManagementWire.email, password: "fixture-password")
        try await auth.changePassword(currentPassword: "fixture-password", newPassword: "fixture-new-password")
        #expect(auth.state == .authenticated(.init(userID: AccountManagementWire.id)))
        #expect((await transport.paths).filter { $0 == "POST /auth/v1/token" }.count == 2)
        #expect((await transport.paths).contains("PUT /auth/v1/user"))
    }

    @Test func oauthOnlyAccountsCannotChangePasswordButCanDelete() async throws {
        let transport = AccountManagementFetch()
        await transport.setProviders(["google"])
        let auth = try service(transport)
        try await auth.signInWithPassword(email: AccountManagementWire.email, password: "fixture-password")
        do { try await auth.changePassword(currentPassword: "x", newPassword: "y"); Issue.record("Google password change accepted") }
        catch { #expect(error as? PinTheoryAuthError == .emailIdentityRequired) }
        try await auth.deleteAccount()
        #expect(auth.state == .signedOut)
        #expect((await transport.paths).contains("POST /functions/v1/delete-account"))
    }

    @Test func deletionRefreshesSessionThenUsesExactEndpointWithoutPassword() async throws {
        let transport = AccountManagementFetch()
        let auth = try service(transport)
        try await auth.signInWithPassword(email: AccountManagementWire.email, password: "fixture-password")
        try await auth.deleteAccount()
        #expect(auth.state == .signedOut)
        let paths = await transport.paths
        #expect(paths.contains("POST /auth/v1/token"))
        #expect(paths.last == "POST /functions/v1/delete-account")
        #expect(await transport.deletionRequestWasValid)
    }

    @Test(arguments: [401, 403, 503])
    func deletionFailureIsSanitizedAndRetainsLocalSession(status: Int) async throws {
        let transport = AccountManagementFetch()
        await transport.setDeletionStatus(status)
        let auth = try service(transport)
        try await auth.signInWithPassword(email: AccountManagementWire.email, password: "fixture-password")
        do { try await auth.deleteAccount(); Issue.record("Failed deletion was accepted") }
        catch {
            let expected: PinTheoryAuthError = status == 401 ? .authRequired
                : (status == 403 ? .recentAuthenticationRequired : .accountDeletionUnavailable)
            #expect(error as? PinTheoryAuthError == expected)
            #expect(!error.localizedDescription.contains("private"))
        }
        #expect(auth.state == .authenticated(.init(userID: AccountManagementWire.id)))
    }
}

nonisolated private enum AccountManagementWire {
    static let id = UUID(uuidString: "C1769DF3-564D-4AF5-B248-E76CF3DF21D4")!
    static let email = "player@example.test"

    static func user(_ providers: [String], metadata: [String: Any] = [:],
                     googleIdentityData: [String: Any] = [:]) throws -> Data {
        let object: [String: Any] = [
            "id": id.uuidString, "aud": "authenticated", "email": email,
            "app_metadata": [:], "user_metadata": metadata, "created_at": "2026-10-21T12:00:00Z",
            "updated_at": "2026-10-21T12:00:00Z",
            "identities": providers.map { provider in
                var identity: [String: Any] = [
                    "id": "fixture-identity", "identity_id": UUID().uuidString,
                    "user_id": id.uuidString, "provider": provider
                ]
                if provider == "google", !googleIdentityData.isEmpty {
                    identity["identity_data"] = googleIdentityData
                }
                return identity
            }
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func session() throws -> Data {
        let user = try JSONSerialization.jsonObject(with: user(["email", "google"]))
        return try JSONSerialization.data(withJSONObject: [
            "user": user, "access_token": "fixture-access", "refresh_token": "fixture-refresh",
            "token_type": "bearer", "expires_in": 3600,
            "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970
        ])
    }
}

private actor AccountManagementFetch {
    private(set) var paths: [String] = []
    private var providers = ["email", "google"]
    private var deletionStatus = 200
    private var metadata: [String: Any] = [:]
    private var googleIdentityData: [String: Any] = [:]
    private(set) var deletionRequestWasValid = false
    var savedMetadata: [String: Any] { metadata }

    func setProviders(_ value: [String]) { providers = value }
    func setDeletionStatus(_ value: Int) { deletionStatus = value }
    func setGoogleIdentityData(_ value: [String: Any]) { googleIdentityData = value }

    func respond(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let path = "\(request.httpMethod ?? "") \(url.path)"
        paths.append(path)
        #expect(url.host == "management.example.test")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_management_fixture")
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let data: Data
        let status: Int
        switch path {
        case "POST /auth/v1/token":
            let grantType = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            if grantType == "password" {
                #expect(body?["email"] as? String == AccountManagementWire.email)
                #expect(body?["password"] as? String == "fixture-password")
            } else {
                #expect(grantType == "refresh_token")
                #expect(body?["refresh_token"] as? String == "fixture-refresh")
            }
            data = try AccountManagementWire.session()
            status = 200
        case "GET /auth/v1/user":
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            data = try AccountManagementWire.user(providers, metadata: metadata,
                                                  googleIdentityData: googleIdentityData)
            status = 200
        case "PUT /auth/v1/user":
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            if let updatedMetadata = body?["data"] as? [String: Any] {
                metadata.merge(updatedMetadata) { _, new in new }
                data = try AccountManagementWire.user(providers, metadata: metadata,
                                                      googleIdentityData: googleIdentityData)
            } else {
                #expect(body?["password"] as? String == "fixture-new-password")
                data = try AccountManagementWire.user(providers, metadata: metadata,
                                                      googleIdentityData: googleIdentityData)
            }
            status = 200
        case "POST /functions/v1/delete-account":
            deletionRequestWasValid = request.httpMethod == "POST"
                && url.absoluteString == "https://management.example.test/functions/v1/delete-account"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access"
                && request.value(forHTTPHeaderField: "Content-Type") == "application/json"
                && request.httpBody == Data("{}".utf8)
            #expect(deletionRequestWasValid)
            status = deletionStatus
            data = try JSONSerialization.data(withJSONObject: status == 200
                ? ["status": "deleted"] : ["error": "private backend detail"])
        default:
            Issue.record("Unexpected intercepted request: \(path)")
            throw URLError(.badServerResponse)
        }
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!)
    }
}

nonisolated private final class AccountManagementStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values[key] = nil }
}
