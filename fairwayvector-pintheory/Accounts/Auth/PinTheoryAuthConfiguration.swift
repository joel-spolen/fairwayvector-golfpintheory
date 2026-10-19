import Foundation

nonisolated enum PinTheoryAuthError: Error, LocalizedError, Equatable {
    case invalidConfiguration, invalidCallback, signInFailed, cancelled
    case authenticationRequired, operationInProgress, secureStorageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Account sign-in is not configured correctly."
        case .invalidCallback, .signInFailed: "Sign-in could not be completed. Please try again."
        case .cancelled: "Sign-in was cancelled."
        case .authenticationRequired: "Please connect and sign in again."
        case .operationInProgress: "Another account operation is in progress."
        case .secureStorageUnavailable: "Secure account storage is unavailable. Please try again."
        }
    }
}

/// Public client configuration only. No enabled flag, redirect override, JWT API key,
/// secret key or service-role key is accepted. Never log this value or its key.
nonisolated struct PinTheoryAuthConfiguration: Sendable {
    static let callbackURL = URL(string: "pintheory://auth/callback")!
    let projectURL: URL
    let publishableKey: String

    init(projectURL: URL, publishableKey: String) throws {
        guard let parts = URLComponents(url: projectURL, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/",
              host.utf8.allSatisfy({ $0 == 45 || $0 == 46 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }),
              !host.contains(".."), !host.hasPrefix("."), !host.hasSuffix("."),
              publishableKey.hasPrefix("sb_publishable_"),
              publishableKey.count > "sb_publishable_".count,
              publishableKey.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 })
        else { throw PinTheoryAuthError.invalidConfiguration }
        var root = URLComponents()
        root.scheme = "https"
        root.host = host.lowercased()
        guard let canonicalURL = root.url else { throw PinTheoryAuthError.invalidConfiguration }
        self.projectURL = canonicalURL
        self.publishableKey = publishableKey
    }

    /// Missing/blank values leave auth disabled. Malformed nonblank values fail closed.
    /// Bundle entries are wired to blank build settings; this service does not create itself.
    static func load(bundle: Bundle = .main) throws -> Self? {
        try load(projectURL: bundle.object(forInfoDictionaryKey: "PINTHEORY_SUPABASE_URL") as? String,
                 publishableKey: bundle.object(forInfoDictionaryKey: "PINTHEORY_SUPABASE_PUBLISHABLE_KEY") as? String)
    }

    static func load(projectURL: String?, publishableKey: String?) throws -> Self? {
        let url = projectURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = publishableKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty, !key.isEmpty else { return nil }
        guard let parsed = URL(string: url) else { throw PinTheoryAuthError.invalidConfiguration }
        return try Self(projectURL: parsed, publishableKey: key)
    }

    /// Match the literal destination, not just a custom scheme. PKCE query content
    /// is validated separately; fragments/implicit access-token grants are unsupported.
    static func acceptsCallback(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "pintheory" && parts.host == "auth"
            && parts.user == nil && parts.password == nil && parts.port == nil
            && parts.percentEncodedHost == "auth" && parts.percentEncodedPath == "/callback"
            && parts.fragment == nil
    }

    static func validateCallback(_ url: URL) throws {
        guard acceptsCallback(url),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              !items.contains(where: { $0.name.hasPrefix("error") }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty
        else { throw PinTheoryAuthError.invalidCallback }
    }
}