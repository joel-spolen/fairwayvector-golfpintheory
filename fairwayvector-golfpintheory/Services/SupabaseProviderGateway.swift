import Foundation

nonisolated struct SupabaseProviderResponse: Sendable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]

    func value(forHTTPHeaderField name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

nonisolated enum SupabaseProviderError: Error, LocalizedError, Sendable {
    case configurationUnavailable
    case authenticationRequired
    case requestRejected
    case transportUnavailable
    case httpStatus(Int, code: String?, message: String?)

    var errorDescription: String? {
        switch self {
        case .configurationUnavailable:
            "Supabase data service is not configured."
        case .authenticationRequired:
            "Sign in and reconnect before requesting provider data."
        case .requestRejected:
            "Supabase rejected the provider-data request."
        case .transportUnavailable:
            "Supabase provider data could not be reached. No provider credential was sent by this device."
        case .httpStatus(_, _, let message):
            message ?? "Supabase provider data is temporarily unavailable."
        }
    }
}

/// Public, app-embedded project configuration is used only to address the Edge
/// Function. Provider API credentials remain in Supabase Edge Function secrets.
nonisolated enum SupabaseProviderEndpoint {
    static func functionBase(projectURL: URL? = nil) -> URL? {
        let configuredURL = projectURL ?? (Bundle.main.object(forInfoDictionaryKey: "PINTHEORY_SUPABASE_URL") as? String)
            .flatMap(URL.init(string:))
        guard let configuredURL,
              let components = URLComponents(url: configuredURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.host != nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return nil }
        return configuredURL.appending(path: "functions/v1/golf-data/api/v1")
    }

    static func dataURL(projectURL: URL? = nil, route: String) -> URL? {
        guard route.hasPrefix("/"), !route.hasPrefix("//"),
              !route.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              let base = functionBase(projectURL: projectURL) else { return nil }
        return base.appending(path: String(route.dropFirst()))
    }
}

/// Owns authenticated, no-redirect requests to the fixed user-authenticated Edge
/// Function. It never accepts provider URLs or stores a user session token.
@MainActor
final class SupabaseProviderGateway {
    static let shared = SupabaseProviderGateway()

    private weak var auth: PinTheoryAuthService?
    private var configuration: AccountSyncSupabaseConfiguration?
    private let session: URLSession

    private init() {
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 30
        settings.timeoutIntervalForResource = 60
        session = URLSession(configuration: settings, delegate: ProviderNoRedirectDelegate(), delegateQueue: nil)
    }

    func configure(configuration: AccountSyncSupabaseConfiguration, auth: PinTheoryAuthService) {
        self.configuration = configuration
        self.auth = auth
    }

    func authorizedRequest(_ originalRequest: URLRequest) async throws -> URLRequest {
        guard let configuration, let expectedHost = configuration.projectURL.host,
              let url = originalRequest.url,
              url.scheme?.lowercased() == "https", url.host?.lowercased() == expectedHost.lowercased(),
              url.port == configuration.projectURL.port,
              url.path.hasPrefix("/functions/v1/golf-data/api/v1/"),
              !(originalRequest.allHTTPHeaderFields?.keys.contains(where: {
                  ["origin", "x-api-key", "authorization", "apikey"].contains($0.lowercased())
              }) ?? false) else {
            throw SupabaseProviderError.configurationUnavailable
        }
        guard let auth else { throw SupabaseProviderError.authenticationRequired }
        let token: String
        do { token = try await auth.providerDataAccessToken() }
        catch { throw SupabaseProviderError.authenticationRequired }

        var request = originalRequest
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        if let body = request.httpBody, body.count > 300_000 { throw SupabaseProviderError.requestRejected }
        return request
    }

    func send(_ originalRequest: URLRequest) async throws -> SupabaseProviderResponse {
        let request = try await authorizedRequest(originalRequest)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw SupabaseProviderError.transportUnavailable }
        guard let http = response as? HTTPURLResponse else { throw SupabaseProviderError.transportUnavailable }
        guard data.count <= 4_000_000 else { throw SupabaseProviderError.requestRejected }
        let headers: [String: String] = Dictionary(uniqueKeysWithValues: http.allHeaderFields.compactMap { key, value -> (String, String)? in
            guard let key = key as? String else { return nil }
            return (key, String(describing: value))
        })
        return SupabaseProviderResponse(data: data, statusCode: http.statusCode, headers: headers)
    }
}

nonisolated private final class ProviderNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
