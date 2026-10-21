import AuthenticationServices
import Combine
import SwiftUI
import UIKit

/// Retain at the login root and pass to PinTheoryLoginView when logout must also
/// dismiss the browser. cancel() only ends the browser; it never signs out.
@MainActor
final class PinTheoryWebAuthenticationBroker: NSObject, ObservableObject {
    @Published private(set) var hasPresentationAnchor = false
    private weak var window: UIWindow?
    private var session: ASWebAuthenticationSession?
    private var provider: WindowPresentationProvider?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var requestID: UUID?
    var isAuthenticating: Bool { requestID != nil }

    func setPresentationWindow(_ window: UIWindow?) {
        self.window = window
        hasPresentationAnchor = window != nil
    }

    /// Use directly inside the service's @MainActor @Sendable launchFlow closure.
    func authenticate(_ url: URL) async throws -> URL {
        try Task.checkCancellation()
        guard requestID == nil else { throw PinTheoryAuthError.operationInProgress }
        guard let window, !window.isHidden, window.windowScene != nil else {
            throw PinTheoryAuthError.signInFailed
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.requestID = id
                self.continuation = continuation
                let provider = WindowPresentationProvider(window: window)
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: PinTheoryAuthConfiguration.callbackURL.scheme
                ) { [weak self] callback, error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let error {
                            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                            self.finish(id, result: .failure(cancelled ? PinTheoryAuthError.cancelled : .signInFailed))
                        } else if let callback {
                            // Full destination + PKCE validation belongs to the service.
                            self.finish(id, result: .success(callback))
                        } else {
                            self.finish(id, result: .failure(.signInFailed))
                        }
                    }
                }
                session.presentationContextProvider = provider
                self.provider = provider
                self.session = session
                if !session.start() {
                    self.finish(id, result: .failure(.signInFailed))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(requestID: id) }
        }
    }

    func cancel() {
        guard let requestID else { return }
        cancel(requestID: requestID)
    }

    private func cancel(requestID id: UUID) {
        guard requestID == id else { return }
        let activeSession = session
        // Consume before cancel(): a late browser callback cannot resume twice,
        // or complete a subsequent request.
        finish(id, result: .failure(.cancelled))
        activeSession?.cancel()
    }

    private func finish(_ id: UUID, result: Result<URL, PinTheoryAuthError>) {
        guard requestID == id, let continuation else { return }
        self.continuation = nil
        requestID = nil
        session = nil
        provider = nil
        switch result {
        case .success(let url): continuation.resume(returning: url)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

@MainActor
private final class WindowPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow

    init(window: UIWindow) { self.window = window }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}

/// Captures ONLY the window actually hosting this SwiftUI login view.
@MainActor
struct PinTheoryAuthenticationWindowReader: UIViewRepresentable {
    let broker: PinTheoryWebAuthenticationBroker

    func makeUIView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.broker = broker
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ uiView: WindowReaderView, context: Context) {
        uiView.broker = broker
    }

    final class WindowReaderView: UIView {
        weak var broker: PinTheoryWebAuthenticationBroker?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Defer publication out of SwiftUI's view-update transaction and read
            // the current window, not a potentially superseded attachment.
            Task { @MainActor [weak self] in
                guard let self else { return }
                broker?.setPresentationWindow(window)
            }
        }
    }
}