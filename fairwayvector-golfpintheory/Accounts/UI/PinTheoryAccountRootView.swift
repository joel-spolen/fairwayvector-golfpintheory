import SwiftUI

struct PinTheoryAccountRootView: View {
    @ObservedObject var session: PinTheoryAccountSession
    @AppStorage("map.hasSeenSplash", store: .standard) private var hasSeenSplash = false
    @State private var showingSplash = true

    var body: some View {
        Group {
            if let auth = session.auth {
                PinTheoryAuthenticatedGate(session: session, auth: auth)
            } else {
                ContentUnavailableView("Sign-in unavailable", systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(session.message ?? "Account configuration is unavailable."))
            }
        }
        .environmentObject(session)
        .overlay {
            if showingSplash {
                SplashView(isReturningUser: hasSeenSplash) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingSplash = false
                        hasSeenSplash = true
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .preferredColorScheme(.light)
        .onAppear { session.start() }
        .onOpenURL { url in Task { await session.handle(url) } }
    }
}

private struct PinTheoryAuthenticatedGate: View {
    @ObservedObject var session: PinTheoryAccountSession
    @ObservedObject var auth: PinTheoryAuthService
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingReset = false

    var body: some View {
        Group {
            switch auth.state {
            case .signedOut:
                if let deletionNotice = session.accountDeletionNotice {
                    PinTheoryLoginView(auth: auth, browser: session.browser, notice: deletionNotice)
                } else if auth.lastError == .secureStorageUnavailable || session.message != nil {
                    ContentUnavailableView {
                        Label("Secure account storage unavailable", systemImage: "lock.shield")
                    } description: {
                        Text(session.message ?? "Unlock this device and retry. Existing credentials have been preserved where possible.")
                    } actions: {
                        Button("Retry secure storage") { Task { await session.retrySecureStorage() } }
                        Button("Clear sign-in and retry", role: .destructive) { confirmingReset = true }
                    }
                } else if session.started {
                    PinTheoryLoginView(auth: auth, browser: session.browser)
                } else { ProgressView("Restoring your account…") }
            case .restoring:
                ProgressView("Restoring your account…")
            case .passwordRecovery:
                PinTheoryPasswordRecoveryView(auth: auth)
            case .authenticated, .offlineCachedIdentity:
                if let data = session.accountData {
                    ContentView(accountData: data).id(data.id)
                } else {
                    ContentUnavailableView {
                        Label("Account storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(session.message ?? "Existing records have been preserved.")
                    } actions: {
                        Button("Retry") { session.openAccountAgain() }
                        Button("Sign out") { session.signOut() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PureLineStyle.canvas)
        .confirmationDialog("Clear saved sign-in?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Clear sign-in", role: .destructive) { session.signOut() }
        } message: {
            Text("This removes local sign-in credentials, not golf records. You will need to sign in again.")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !auth.isBusy else { return }
            switch auth.state {
            case .authenticated(let identity), .offlineCachedIdentity(let identity):
                Task { _ = try? await auth.authenticatedAccessToken(for: identity.userID) }
            default: break
            }
        }
    }
}