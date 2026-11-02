import Foundation

nonisolated enum PinTheoryAuthError: Error, LocalizedError, Equatable {
    case invalidConfiguration, invalidCallback, signInFailed, cancelled
    case authenticationRequired, operationInProgress, secureStorageUnavailable
    case emailRateLimited, emailDeliveryUnavailable, emailProviderDisabled
    case emailRequestRejected, networkUnavailable, accountServiceUnauthorized, captchaRequired
    case accountServiceUnavailable
    case invalidCredentials, weakPassword, emailNotConfirmed
    case recentAuthenticationRequired, accountDeletionUnavailable, authRequired
    case emailIdentityRequired
    case googleOAuthSetupFailed, googleOAuthCallbackFailed, googleOAuthUnavailable
    case accountPasswordUpdateUnavailable
    case invalidDisplayName, displayNameUpdateUnavailable
    /// Numeric URL-loading code only, never NSError userInfo or failing URL.
    case connectionFailure(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration, .accountServiceUnauthorized, .captchaRequired:
            L("Sign-in isn't available right now. Please try again later.")
        case .invalidCallback, .signInFailed: L("Sign-in could not be completed. Please try again.")
        case .cancelled: L("Sign-in was cancelled.")
        case .authenticationRequired: L("Please connect and sign in again.")
        case .operationInProgress: L("Another account operation is in progress.")
        case .secureStorageUnavailable: L("Secure account storage is unavailable. Please try again.")
        case .emailRateLimited: L("Too many attempts. Please wait a few minutes and try again.")
        case .emailDeliveryUnavailable: L("We couldn't send the email. Please try again later.")
        case .emailProviderDisabled: L("Email sign-in isn't available right now. Please try again later.")
        case .emailRequestRejected: L("We couldn't send an email to that address. Check it and try again.")
        case .networkUnavailable: L("No internet connection. Check your connection and that Golf PinTheory is allowed to use mobile data in Settings.")
        case .accountServiceUnavailable: L("The account service could not complete your request. Please try again later.")
        case .connectionFailure(let code): Self.connectionDescription(code)
        case .invalidCredentials: L("The email or password is incorrect. Try again or reset your password.")
        case .weakPassword: L("Please choose a stronger password.")
        case .emailNotConfirmed: L("Confirm your email before signing in. Check your inbox or request another confirmation email.")
        case .recentAuthenticationRequired: L("Your password could not be verified. Check it and try again.")
        case .accountDeletionUnavailable: L("Account deletion could not be completed. Please try again later.")
        case .authRequired: L("Your account session is no longer valid. Sign in again and retry.")
        case .emailIdentityRequired: L("This action is available only for accounts with an email sign-in method.")
        case .googleOAuthSetupFailed, .googleOAuthCallbackFailed, .googleOAuthUnavailable:
            L("Google sign-in couldn't be completed. Please try again.")
        case .accountPasswordUpdateUnavailable: L("The password could not be updated. Please try again later.")
        case .invalidDisplayName: L("Names must be 80 characters or fewer.")
        case .displayNameUpdateUnavailable: L("Your display name could not be saved. Please try again.")
        }
    }

    static func networkError(_ error: URLError) -> Self {
        switch error.code {
        case .cancelled: .cancelled
        case .notConnectedToInternet: .networkUnavailable
        default: .connectionFailure(error.code.rawValue)
        }
    }

    private static func connectionDescription(_ code: Int) -> String {
        switch URLError.Code(rawValue: code) {
        case .timedOut, .networkConnectionLost:
            L("The network connection was interrupted. Reconnect and try again.")
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            L("A secure connection couldn't be made. Check that your device's date and time are correct, then try again.")
        default:
            L("We couldn't connect. Check your internet connection and try again.")
        }
    }
}

/// Public client configuration only. No enabled flag, redirect override, JWT API key,
/// secret key or service-role key is accepted. Never log this value or its key.
nonisolated struct PinTheoryAuthConfiguration: Sendable {
    static let callbackURL = URL(string: "golfpintheory://auth/callback")!
    /// Must be separately allowlisted in Supabase Auth redirect URLs.
    static let passwordResetURL = URL(string: "golfpintheory://auth/reset-password")!
    let projectURL: URL
    let publishableKey: String

    var accountDeletionURL: URL {
        projectURL.appendingPathComponent("functions").appendingPathComponent("v1")
            .appendingPathComponent("delete-account")
    }

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
        let allowedDestination = (parts.scheme == "golfpintheory" && parts.percentEncodedPath == "/callback")
            || (parts.scheme == "golfpintheory" && parts.percentEncodedPath == "/reset-password")
        return allowedDestination && parts.host == "auth"
            && parts.user == nil && parts.password == nil && parts.port == nil
            && parts.percentEncodedHost == "auth"
            && (parts.fragment == nil || parts.fragment?.isEmpty == true)
    }

    static func isPasswordResetCallback(_ url: URL) -> Bool {
        acceptsCallback(url)
            && URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == "/reset-password"
    }

    static func validateCallback(_ url: URL, allowRecovery: Bool = true) throws {
        guard callbackValidationFailure(url, allowRecovery: allowRecovery) == nil else {
            throw PinTheoryAuthError.invalidCallback
        }
    }

    /// A value-free diagnostic for callback failures. Never include query values,
    /// which may contain authorization codes or provider response details.
    static func callbackValidationFailure(_ url: URL, allowRecovery: Bool = true) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "unparseable_callback"
        }
        // Keep these as sequential checks so a rejection always identifies its
        // actual failing component (instead of reporting a combined predicate).
        guard parts.scheme == "golfpintheory" else { return "unexpected_callback_scheme" }
        guard parts.host == "auth", parts.percentEncodedHost == "auth" else { return "unexpected_callback_host" }
        guard parts.user == nil, parts.password == nil else { return "unexpected_callback_userinfo" }
        guard parts.port == nil else { return "unexpected_callback_port" }
        guard parts.percentEncodedPath == "/callback" || parts.percentEncodedPath == "/reset-password" else {
            return "unexpected_callback_path"
        }
        guard parts.fragment == nil || parts.fragment?.isEmpty == true else { return "unexpected_callback_fragment" }
        guard allowRecovery || parts.percentEncodedPath != "/reset-password" else {
            return "callback_purpose_not_allowed"
        }
        guard let items = parts.queryItems else { return "missing_callback_query" }
        guard !items.contains(where: { $0.name.hasPrefix("error") }) else {
            return "provider_returned_oauth_error"
        }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1 else { return codes.isEmpty ? "missing_authorization_code" : "duplicate_authorization_code" }
        guard let code = codes.first?.value, !code.isEmpty else { return "empty_authorization_code" }
        return nil
    }

    /// Removes a harmless trailing `#` before the SDK parses OAuth parameters.
    /// Non-empty fragments are rejected by callbackValidationFailure.
    static func callbackURLForCodeExchange(_ url: URL) throws -> URL {
        try validateCallback(url, allowRecovery: false)
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw PinTheoryAuthError.invalidCallback
        }
        guard parts.fragment?.isEmpty == true else { return url }
        var normalized = parts
        normalized.fragment = nil
        guard let result = normalized.url else { throw PinTheoryAuthError.invalidCallback }
        return result
    }
}