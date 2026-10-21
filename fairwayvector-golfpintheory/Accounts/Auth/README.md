# iOS auth service — password/Google and restricted recovery

## Current password contract (2026-10-21)

Service/config/storage and new `AccountPasswordTests.swift` source only. The root,
account-session owner and login UI are owned by the separate UI integration work.
Do not ship until their exhaustive state switches and callback routing support
`.passwordRecovery`, including callbacks when already in that restricted state.
The session owner must detach account data for recovery, never open an account.

- `signInWithPassword(email:password:) async throws`: official SDK password grant,
  then matching online `/user` confirmation. No minimum length for existing login.
  Magic-link-only accounts with no password receive generic invalid credentials.
- `signUpWithPassword(email:password:) async throws -> Bool`: `true` means check
  confirmation email (SDK user-only response), **not** proof an account was created;
  `false` means a session was independently confirmed and authenticated. Retains
  the persisted PKCE verifier for user-only responses. No identity/existence result.
- `sendPasswordReset(email:) async throws`: SDK recovery email with PKCE and the
  exact distinct redirect `golfpintheory://auth/reset-password`.
- `completePasswordReset(password:) async throws`: restricted state and durable
  marker required; online user validation followed by SDK
  `update(user: UserAttributes(password:))`. A matching successful update performs
  the existing **local** `signOut()` and requires ordinary login again. No Home,
  confirmation marker, cloud token or offline cache access from recovery. Local
  logout does not revoke remote sessions; SDK remote logout is not invoked.
- `resendSignupConfirmation(email:) async throws`: SDK `.signup` resend, callback
  redirect and durable PKCE verifier; no account-existence result.
- Legacy magic-link/code methods remain for source compatibility; the new UI
  should use password plus Google. Google explicitly rejects recovery destinations.
- Server enforces password policy. UI should recommend at least eight characters
  for new signup/reset passwords. Never log or persist passwords. `weakPassword`,
  `invalidCredentials`, `emailNotConfirmed` are fixed sanitized categories; the last
  asks the user to confirm email or request another confirmation email. Provider
  error messages, weak-password reasons, addresses and response bodies are hidden.

### Callback and durable marker contract

**Supabase prerequisite:** separately allowlist both literal redirects
`golfpintheory://auth/callback` and `golfpintheory://auth/reset-password` in Auth URL
Configuration. This change does not edit the hosted allowlist or any console.
Callbacks require the exact literal path and one nonempty PKCE code; fragments,
credentials, ports, encoded-path aliases and error parameters are rejected.
Only the `golfpintheory` scheme is registered. `acceptsCallback` / `validateCallback`
accept only the exact destinations above; the old scheme is not supported.
`validateCallback(_:allowRecovery: false)` rejects reset URLs for Google.
Query `type=recovery` is not recovery authority: routing uses the distinct path
and locally persisted intent/activation, never an SDK auth-event listener.

Service-owned Keychain markers (same host-scoped ThisDeviceOnly storage as tokens):

| Key                                       | Value / lifecycle                                                                                                                                                                                                                               |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `password-recovery-request-v1`            | UTF-8 `1`; stored before sending reset. Preserved on ambiguous send errors/restart. Also restricts a rewritten ordinary callback. A deliberately initiated ordinary login/signup/resend supersedes this pending intent, not activated recovery. |
| `password-recovery-required-v1`           | UTF-8 `1`, no identity; persisted **before** PKCE exchange. Removed only after confirmed update + local credential cleanup, or explicit successful logout. Never removed by error cleanup.                                                      |
| `server-confirmed-user-v1`                | Existing ordinary-login UUID marker; removed on recovery activation and restart before any recovery validation. Never written in recovery.                                                                                                      |
| `session-v1` / `session-v1-code-verifier` | Existing SDK session/default JSON encoder-decoder and PKCE keys. No password storage.                                                                                                                                                           |

After restart an activated marker restricts even an otherwise confirmed session:
online `/user` validation may restore only identity-free `.passwordRecovery`.
Missing session stays restricted for callback retry; network/invalid-session/update
errors never permit offline recovery/Home. Exchange errors retain needed verifier;
update errors retain the marker and restricted session. Storage errors lock the
client nondestructively for `retrySecureStorage()`. Explicit logout deletes the
recovery marker **last**, after session/verifier/confirmation cleanup succeeds.
Generation checks and revoked SDK leases reject late exchange/update responses.

### Validation for this password change

Local SDK source APIs were read before editing. Added injected fake-fetch test
sources for password grant, both signup modes, resend, reset destination, marker
before exchange, restart/offline gating, retry/update/logout and late responses,
Google exclusion and sanitized errors. Editor diagnostics reported no errors in
changed Swift files; this is **not compiler or runtime verification**. No commands,
builds, tests, app launches, network calls or secret reads were performed.

---

## Historical email/Google integration notes (superseded where above differs)

Source-only, using the installed **Auth** product from supabase-swift **2.55.4**.
The app-wide `PinTheoryAccountSession` now constructs the service and gates Home through the email/Google UI. Cloud golf-record sync, account deletion and public-release compliance remain incomplete. Apple methods are unexposed.

## Service contract (historical phase-one details below)

Current integration supplies URL-scheme registration/routing, browser presentation, account-local storage and Settings logout. Foreground checks refresh on demand; temporary HTTP 408/429/5xx and connectivity failures preserve confirmed cached access. `retrySecureStorage()` offers nondestructive recovery. Invalid email-code attempts preserve a pending link's verifier while clearing partial session state. The root retains callbacks only in memory until restoration/active operations finish. Full Debug app/test compilation passed, without running tests, sending email or attempting provider login. Statements below describing absent UI/startup are historical phase-one limitations superseded by this paragraph and the project README.

- `PinTheoryAuthConfiguration.load(bundle:)` reads only `PINTHEORY_SUPABASE_URL`
  and `PINTHEORY_SUPABASE_PUBLISHABLE_KEY`. Missing/blank either value returns
  `nil` (disabled); malformed nonblank configuration throws a sanitized error.
  Only an HTTPS root URL and `sb_publishable_…` key are supported. No legacy JWT
  API keys or secrets. The ordinary redirect is always `golfpintheory://auth/callback`.
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
