import AuthenticationServices
import SwiftUI
import UIKit

/// Keep Apple's native control at an explicit size inside the SwiftUI login scroll view.
/// The coordinator owns each authorization attempt until Apple returns its result.
@MainActor
struct PinTheoryAppleSignInButton: UIViewRepresentable {
    let isEnabled: Bool
    let onRequest: (ASAuthorizationAppleIDRequest) throws -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        button.cornerRadius = 8
        button.accessibilityIdentifier = "account-apple-sign-in"
        button.addTarget(context.coordinator, action: #selector(Coordinator.signIn(_:)), for: .touchUpInside)
        button.isEnabled = isEnabled
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.parent = self
        guard let button = container.subviews.first as? ASAuthorizationAppleIDButton else { return }
        button.isEnabled = isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView,
                     context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 280, height: 48)
    }

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        var parent: PinTheoryAppleSignInButton
        private var controller: ASAuthorizationController?
        private var window: UIWindow?
        private var completion: ((Result<ASAuthorization, Error>) -> Void)?

        init(parent: PinTheoryAppleSignInButton) { self.parent = parent }

        @objc func signIn(_ sender: ASAuthorizationAppleIDButton) {
            guard parent.isEnabled, controller == nil, let window = sender.window else { return }
            let request = ASAuthorizationAppleIDProvider().createRequest()
            do { try parent.onRequest(request) }
            catch { return } // Request preparation displays a sanitized error in the login view.

            self.window = window
            completion = parent.onCompletion
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            // An attempt starts only from a control attached to this retained window.
            window!
        }

        func authorizationController(controller: ASAuthorizationController,
                                     didCompleteWithAuthorization authorization: ASAuthorization) {
            finish(controller, result: .success(authorization))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            finish(controller, result: .failure(error))
        }

        private func finish(_ controller: ASAuthorizationController, result: Result<ASAuthorization, Error>) {
            guard self.controller === controller else { return }
            let completion = self.completion
            self.completion = nil
            self.controller = nil
            window = nil
            completion?(result)
        }
    }
}