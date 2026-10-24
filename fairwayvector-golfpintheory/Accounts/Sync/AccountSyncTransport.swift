import Foundation

nonisolated protocol AccountSyncTransport: Sendable {
    func validateServerContract(accessToken: String) async throws
    func mutate(_ mutation: AccountSyncMutation, accessToken: String) async throws -> AccountSyncMutationResult
    func changes(_ request: AccountSyncChangesRequest, accessToken: String) async throws -> AccountSyncChangePage
}

/// Only public project configuration belongs here. Legacy JWT API keys (including
/// service_role) are deliberately unsupported; use a new sb_publishable_ key.
nonisolated struct AccountSyncSupabaseConfiguration: Sendable {
    let projectURL: URL
    let publishableKey: String

    init(projectURL: URL, publishableKey: String) throws {
        guard let parts = URLComponents(url: projectURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              publishableKey.hasPrefix("sb_publishable_"), publishableKey.count > "sb_publishable_".count,
              publishableKey.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw AccountSyncError.invalidConfiguration
        }
        self.projectURL = projectURL
        self.publishableKey = publishableKey
    }
}

/// No redirect may forward the per-request bearer credential to another endpoint.
nonisolated private final class AccountSyncNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated final class URLSessionAccountSyncTransport: AccountSyncTransport, Sendable {
    private struct Capabilities: Decodable {
        let syncSchemaVersion: Int
        let payloadValidationVersion: Int

        enum CodingKeys: String, CodingKey {
            case syncSchemaVersion = "sync_schema_version"
            case payloadValidationVersion = "payload_validation_version"
        }
    }

    private let configuration: AccountSyncSupabaseConfiguration
    private let session: URLSession

    init(configuration: AccountSyncSupabaseConfiguration) {
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 30
        settings.timeoutIntervalForResource = 60
        session = URLSession(configuration: settings, delegate: AccountSyncNoRedirectDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func validateServerContract(accessToken: String) async throws {
        let capabilities: Capabilities = try await post("pintheory_sync_capabilities",
            body: EmptyRPCBody(), accessToken: accessToken)
        guard capabilities.syncSchemaVersion == 1, capabilities.payloadValidationVersion == 1 else {
            throw AccountSyncError.serverContractUnavailable
        }
    }

    func mutate(_ mutation: AccountSyncMutation, accessToken: String) async throws -> AccountSyncMutationResult {
        try mutation.validate()
        let result: AccountSyncMutationResult = try await post("pintheory_sync_mutate", body: mutation, accessToken: accessToken)
        try result.validate(for: mutation)
        return result
    }

    func changes(_ request: AccountSyncChangesRequest, accessToken: String) async throws -> AccountSyncChangePage {
        // Revalidate even requests decoded from external data.
        _ = try AccountSyncChangesRequest(after: request.after, through: request.through, limit: request.limit)
        let page: AccountSyncChangePage = try await post("pintheory_sync_changes", body: request, accessToken: accessToken)
        try page.validate(for: request)
        return page
    }

    nonisolated private struct RPCError: Decodable { let code: String? }
    nonisolated private struct EmptyRPCBody: Encodable {}

    private func post<Body: Encodable, Response: Decodable>(
        _ rpc: String, body: Body, accessToken: String
    ) async throws -> Response {
        guard !accessToken.isEmpty, accessToken.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw AccountSyncError.authenticationRequired
        }
        let url = configuration.projectURL.appendingPathComponent("rest/v1/rpc").appendingPathComponent(rpc)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do { request.httpBody = try JSONEncoder().encode(body) }
        catch { throw AccountSyncError.invalidWire }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            // Never propagate URLSession error descriptions, URLs, headers or server messages.
            throw AccountSyncError.transportUnavailable
        }
        guard let http = response as? HTTPURLResponse else { throw AccountSyncError.transportUnavailable }
        guard (200...299).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(RPCError.self, from: data))?.code
            if http.statusCode == 401 || code == "28000" || code == "PGRST301" || code == "PGRST303" {
                throw AccountSyncError.authenticationRequired
            }
            if code == "PGRST202" || code == "42883" {
                throw AccountSyncError.serverContractUnavailable
            }
            if code == "42501" || code == "23503" { throw AccountSyncError.accountUnavailable }
            if http.statusCode == 429 || http.statusCode >= 500 || code == "40001" || code == "40P01" {
                throw AccountSyncError.transportUnavailable
            }
            throw AccountSyncError.requestRejected
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AccountSyncError.invalidWire }
    }
}