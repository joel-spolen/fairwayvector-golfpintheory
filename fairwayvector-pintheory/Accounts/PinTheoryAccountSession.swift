import Combine
import Foundation

/// One session owner for all windows. Account content is never opened before auth.
@MainActor
final class PinTheoryAccountSession: ObservableObject {
    let auth: PinTheoryAuthService?
    let browser = PinTheoryWebAuthenticationBroker()
    @Published private(set) var accountData: PinTheoryAccountData?
    @Published private(set) var message: String?
    @Published private(set) var started = false
    private let projectHost: String?
    private var subscription: AnyCancellable?
    private var restoreTask: Task<Void, Never>?
    private var pendingCallback: URL?
    private var busySubscription: AnyCancellable?

    init() {
        do {
            guard let configuration = try PinTheoryAuthConfiguration.load() else {
                auth = nil; projectHost = nil
                message = "Account sign-in is not configured in this build."
                return
            }
            projectHost = configuration.projectURL.host
            let service = PinTheoryAuthService(configuration: configuration)
            auth = service
            subscription = service.$state.sink { [weak self] state in self?.apply(state) }
            busySubscription = service.$isBusy.sink { [weak self] busy in
                guard !busy else { return }
                Task { @MainActor [weak self] in await self?.processPendingCallback() }
            }
        } catch {
            auth = nil; projectHost = nil
            message = "Account configuration is unavailable. Please contact the developer."
        }
    }

    func start() {
        guard !started else { return }
        started = true
        restore()
    }

    func restore() {
        guard let auth, !auth.isBusy else { return }
        restoreTask?.cancel()
        restoreTask = Task { @MainActor in
            do { try await auth.restore() }
            catch { /* The service publishes a sanitized error and locks on storage failure. */ }
        }
    }

    func openAccountAgain() {
        guard let auth else { return }
        apply(auth.state)
    }

    func retrySecureStorage() async {
        message = nil
        do { try await auth?.retrySecureStorage() }
        catch { /* Sanitized service error drives recovery UI. */ }
    }

    func handle(_ url: URL) async {
        guard PinTheoryAuthConfiguration.acceptsCallback(url), auth != nil else { return }
        // Google callbacks are consumed directly by ASWebAuthenticationSession.
        guard !browser.isAuthenticating else { return }
        pendingCallback = url
        if !started { start() }
        await processPendingCallback()
    }

    private func processPendingCallback() async {
        // A cold-start link must wait until restoration has examined Keychain.
        await restoreTask?.value
        guard let auth, !auth.isBusy, let url = pendingCallback else { return }
        pendingCallback = nil
        guard auth.state == .signedOut else { return }
        do { try await auth.handleCallback(url) }
        catch { /* Never display callback URLs or raw server errors. */ }
    }

    func signOut() {
        pendingCallback = nil
        browser.cancel()
        restoreTask?.cancel()
        accountData = nil
        message = nil
        do { try auth?.signOut() }
        catch { message = "Secure sign-out could not finish. Please retry before using another account." }
    }

    private func apply(_ state: PinTheoryAuthState) {
        switch state {
        case .authenticated(let identity), .offlineCachedIdentity(let identity):
            guard let projectHost else { return }
            do {
                if accountData?.id.hasSuffix(identity.userID.uuidString.lowercased()) == true { return }
                accountData = nil
                accountData = try PinTheoryAccountData(projectHost: projectHost, userID: identity.userID)
                message = nil
            } catch {
                accountData = nil
                message = "Your account storage could not be opened. Existing records have been preserved. Retry or sign out."
            }
        case .signedOut, .restoring:
            accountData = nil
        }
    }
}