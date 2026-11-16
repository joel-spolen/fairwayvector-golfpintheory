import Auth
import AuthenticationServices
import SwiftUI
import Testing
import UIKit
@testable import fairwayvector_golfpintheory

@MainActor
struct AccountLoginLayoutTests {
    @Test func allSignedOutNoticesKeepTheSameVisibleAppleButton() async throws {
        let configuration = try PinTheoryAuthConfiguration(
            projectURL: URL(string: "https://login.example.test")!,
            publishableKey: "sb_publishable_fixture_only")
        let auth = PinTheoryAuthService(configuration: configuration, storage: LoginLayoutAuthStorage(),
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        let browser = PinTheoryWebAuthenticationBroker()
        func screen(_ notice: String?) -> some View {
            PinTheoryLoginView(auth: auth, browser: browser, notice: notice)
        }
        let host = UIHostingController(rootView: screen(nil))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func findButton(_ view: UIView) -> ASAuthorizationAppleIDButton? {
            if let button = view as? ASAuthorizationAppleIDButton { return button }
            return view.subviews.lazy.compactMap { findButton($0) }.first
        }
        for notice in [nil, "Your Golf PinTheory account was deleted.", "Check your inbox to confirm your email."] {
            host.rootView = screen(notice)
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(10))
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
            }
            let button = try #require(findButton(host.view))
            let rect = button.convert(button.bounds, to: window)
            #expect(window.bounds.contains(rect))
            #expect(rect.width > 300 && rect.height == 48)
            #expect(!button.isHidden && button.alpha == 1)
        }
    }

    @Test func nativeAppleControlSurvivesDisabledStateAndViewReattachment() async throws {
        func screen(enabled: Bool) -> some View {
            ScrollView {
                VStack {
                    Text("Sign in to continue")
                    PinTheoryAppleSignInButton(isEnabled: enabled, onRequest: { _ in }, onCompletion: { _ in })
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .padding(24)
            }
        }
        let host = UIHostingController(rootView: screen(enabled: true))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        func findButton(_ view: UIView) -> ASAuthorizationAppleIDButton? {
            if let button = view as? ASAuthorizationAppleIDButton { return button }
            return view.subviews.lazy.compactMap { findButton($0) }.first
        }
        for enabled in [true, false, true] {
            host.rootView = screen(enabled: enabled)
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(10))
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
                if let button = findButton(host.view), button.isEnabled == enabled,
                   button.bounds.width >= 300 { break }
            }
            let button = try #require(findButton(host.view))
            #expect(button.isEnabled == enabled)
            #expect(button.bounds.width >= 300)
            #expect(button.bounds.height == 48)
            #expect(!button.isHidden && button.alpha > 0)
        }
        window.rootViewController = nil
        window.rootViewController = host
        for _ in 0..<5 { await Task.yield(); window.layoutIfNeeded(); host.view.layoutIfNeeded() }
        let button = try #require(findButton(host.view))
        #expect(button.window === window)
        #expect(button.convert(button.bounds, to: window).intersects(window.bounds))
        #expect(button.accessibilityIdentifier == "account-apple-sign-in")
    }

    @Test func appleButtonRemainsVisibleWhenLoginReturnsToForeground() async throws {
        let configuration = try PinTheoryAuthConfiguration(
            projectURL: URL(string: "https://login.example.test")!,
            publishableKey: "sb_publishable_fixture_only")
        let auth = PinTheoryAuthService(configuration: configuration, storage: LoginLayoutAuthStorage(),
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        let browser = PinTheoryWebAuthenticationBroker()
        func screen(_ phase: ScenePhase) -> some View {
            PinTheoryLoginView(auth: auth, browser: browser,
                notice: "Check your inbox to confirm your email.")
                .environment(\.scenePhase, phase)
        }
        let host = UIHostingController(rootView: screen(.active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        func appleButtons(in view: UIView) -> [ASAuthorizationAppleIDButton] {
            (view as? ASAuthorizationAppleIDButton).map { [$0] } ?? view.subviews.flatMap { appleButtons(in: $0) }
        }
        for phase in [ScenePhase.active, .background, .active] {
            host.rootView = screen(phase)
            // Allow SwiftUI's foreground update and deferred scroll to be applied.
            for _ in 0..<5 { await Task.yield(); window.layoutIfNeeded(); host.view.layoutIfNeeded() }
            if phase == .active {
                let button = try #require(appleButtons(in: host.view).first)
                #expect(!button.isHidden)
                #expect(button.bounds.width > 100)
                #expect(button.bounds.height >= 44)
                #expect(button.convert(button.bounds, to: window).intersects(window.bounds))
            }
        }
    }
}

nonisolated private final class LoginLayoutAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}