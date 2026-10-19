# iOS auth service — prerelease email/Google integration

Source-only, using the installed **Auth** product from supabase-swift **2.55.4**.
The app-wide `PinTheoryAccountSession` now constructs the service and gates Home through the email/Google UI. Cloud golf-record sync, account deletion and public-release compliance remain incomplete. Apple methods are unexposed.

## Service contract (historical phase-one details below)

Current integration supplies URL-scheme registration/routing, browser presentation, account-local storage and Settings logout. Foreground checks refresh on demand; temporary HTTP 408/429/5xx and connectivity failures preserve confirmed cached access. `retrySecureStorage()` offers nondestructive recovery. Invalid email-code attempts preserve a pending link's verifier while clearing partial session state. The root retains callbacks only in memory until restoration/active operations finish. Full Debug app/test compilation passed, without running tests, sending email or attempting provider login. Statements below describing absent UI/startup are historical phase-one limitations superseded by this paragraph and the project README.

- `PinTheoryAuthConfiguration.load(bundle:)` reads only `PINTHEORY_SUPABASE_URL`
  and `PINTHEORY_SUPABASE_PUBLISHABLE_KEY`. Missing/blank either value returns
  `nil` (disabled); malformed nonblank configuration throws a sanitized error.
  Only an HTTPS root URL and `sb_publishable_…` key are supported. No legacy JWT
  API keys or secrets. The redirect is always `pintheory://auth/callback`.
- No configuration, plist, URL scheme, entitlement, provider console or project
  changes are supplied. Configure those separately before any live use.
- Create one main-actor service per project, explicitly call `restore()`, and
  bind only the token-free state/identity. Offline state permits previously
  confirmed, account-isolated **local cache** access, not cloud authorization.
- Apple UI retains the opaque ticket returned by `prepareAppleRequest`, then
  passes its authorization result to `completeAppleSignIn(_:requestID:)` with
  that same ticket, including failure/cancellation callbacks. Stale callbacks
  are rejected before consuming a newer nonce or changing its busy/error state.
  A random raw nonce stays private; the request uses its
  SHA256 hash and official ID-token exchange receives the raw nonce. Names are
  not persisted or copied into a profile. Capability/provider setup remains due.
- Google uses official SDK browser OAuth with PKCE. The UI must supply and retain
  an `ASWebAuthenticationSession` through `signInWithGoogle(launchFlow:)`, including
  its presentation anchor and cancellation. The returned destination is checked
  before SDK session exchange. Native Google SDK integration is **deferred**.
- Email uses SDK OTP sending, PKCE magic-link callback exchange and `.email` code
  verification. The server email template must actually expose an OTP for code
  fallback. Explicitly route callbacks to `handleCallback`, never SDK `handle`.
  Invalid, expired and replayed links expose only fixed generic error messages.
  PKCE links need this installation's persisted verifier; cross-device link
  completion is unsupported. Logout removes the verifier, invalidating pending links.
- Cloud callers use `authenticatedAccessToken(for:)` with the account they are
  syncing. This checks the refreshed/current session UID and `/user` response
  before returning a token; no locally decoded JWT subject grants access. The
  caller must independently guard its request/result against logout/account change.

## Persistence and limitations

- Host-scoped, nonsynchronizable Keychain items use
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. No shared access group or legacy
  global SDK-session migration. The confirmation marker contains only a UUID,
  written after a matching server `/user` response and durable session storage.
  An unconfirmed local session may be verified online, never trusted offline.
- Revocable per-client storage and main-actor operation generations prevent late
  SDK writes and stale state publication after logout. Operations are serialized;
  `signOut()` also cancels logical sign-in. It does **not** dismiss a UI-owned
  browser/Apple sheet or cancel every underlying HTTP request.
- Logout is **local-only**: clears the session, verifier and confirmation marker;
  no server token revocation or provider logout is implemented. Already-issued
  access tokens can remain server-valid until expiry/revocation. Pending sync/data
  discard policy and account cache cleanup belong to later integration.
- Keychain failures fail closed and are reported. A failed logout locks this
  service in-process; retry when storage is available. Durable deletion cannot
  be promised after a Keychain failure. Keychain data can survive uninstall;
  install-bound credential cleanup is not implemented.
- Restore explicitly reads and decodes the stored session through throwing
  storage before interpreting an SDK `currentSession == nil`. Retrieval or
  invalid-session decoding failures lock this service and report secure storage
  unavailable without deleting session bytes or the confirmation marker. Storage
  recovery alone does not unlock the client; explicit logout is destructive.
- No background auto-refresh or auth-event listener. Restore/token access refresh
  on demand. Revocation is discovered on those calls, not instantly, especially
  offline. Only explicit connectivity URLErrors allow offline restoration with a
  matching marker/session. Other non-storage failures conservatively clear local auth.
- Confirmation is a local historical trust marker, not proof of a currently valid
  server session and not a security boundary on a compromised device.
- No UI, startup/settings/account isolation, account deletion, provider linking,
  native Google SDK, backend provisioning or complete sync integration is included.
- SDK logger is disabled; errors never contain underlying URLs, tokens, keys or
  server messages. Callers must also avoid logging configuration or returned tokens.

## Validation status

Added source-only tests for configuration/callback strictness, storage lease
revocation, offline trust boundaries, server UID verification, local logout and
late callback suppression, ticket-linked Apple cancellation, and non-destructive
restore retrieval/decode failures. They use fake storage and injected official SDK fetch
closures, never the real Keychain or auth server. **No tests, builds, browser,
sign-in or network commands were run for this change.** Compilation through the
main application/test build and runtime/provider validation remain required.
