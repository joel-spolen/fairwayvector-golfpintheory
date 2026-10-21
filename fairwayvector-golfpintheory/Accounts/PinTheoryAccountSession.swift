import Combine
import Foundation

/// One session owner for all windows. Account content is never opened before auth.
@MainActor
final class PinTheoryAccountSession: ObservableObject {
    let auth: PinTheoryAuthService?
    let browser = PinTheoryWebAuthenticationBroker()
    @Published private(set) var accountData: PinTheoryAccountData?
    @Published private(set) var message: String?
    @Published private(set) var accountDeletionNotice: String?
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
        if PinTheoryAuthConfiguration.isPasswordResetCallback(url) {
            // Recovery must detach any open account, including in other windows.
            accountData = nil
        } else {
            guard auth.state == .signedOut || auth.state == .passwordRecovery else { return }
        }
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

    func deleteAccount() async throws {
        guard let auth else { throw PinTheoryAuthError.authenticationRequired }
        accountDeletionNotice = nil
        let existingData = accountData
        do { try await auth.deleteAccount() }
        catch {
            // The server may have confirmed deletion even if local Keychain cleanup failed.
            // Continue to the signed-out UI only for that confirmed-success state.
            guard auth.accountWasDeleted else { throw error }
        }
        // Backend deletion succeeded. Never restore this identity locally even if
        // device cleanup reports an error; surface that partial-cleanup result.
        accountData = nil
        var localCleanupFailed = false
        if let existingData {
            do { try existingData.eraseLocalContent() }
            catch { localCleanupFailed = true }
        }
        accountDeletionNotice = localCleanupFailed
            ? "Your account was deleted, but some records remain on this device. Remove Golf PinTheory from this device or contact support."
            : "Your Golf PinTheory account was deleted."
    }

    private func apply(_ state: PinTheoryAuthState) {
        switch state {
        case .authenticated(let identity), .offlineCachedIdentity(let identity):
            if auth?.accountWasDeleted != true { accountDeletionNotice = nil }
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
        case .signedOut, .restoring, .passwordRecovery:
            accountData = nil
                if message?.hasPrefix("Your Golf PinTheory account was deleted") != true,
                    message?.hasPrefix("Your account was deleted") != true {
                message = nil
            }
        }
    }
}