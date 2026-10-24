# Golf PinTheory for iOS

Golf PinTheory is a SwiftUI golf companion for course discovery and on-course planning, round scoring and statistics, handicap projections, club setup, wedge planning, and golf-shot trajectory estimates.

**Rename (2026-10-21):** The repository, project, target, product and source/test directories now use `fairwayvector-golfpintheory`; Swift module/entry/test identifiers use `fairwayvector_golfpintheory`. The registered app bundle ID `com.fairwayvector.app.pintheory`, test bundle IDs, `PinTheoryAccounts` storage directory, `com.fairwayvector.pintheory.*` storage identities, auth configuration and `golfpintheory` callback URLs are intentionally preserved; this is not a storage migration. A fresh Debug simulator `build-for-testing` passed after the filesystem rename; no app or tests were executed. Reopen the renamed Xcode project if the editor still references the old location.

## Requirements

- macOS with Xcode installed. The project currently sets an iOS deployment target of 26.5; use an Xcode version and simulator/runtime that support the project settings.
- Git for source control.
- Swift Package Manager access on the first build. The staged account service uses the official Supabase `Auth` product, pinned to 2.55.4; commit the shared package-resolution lockfile.

## Project layout

| Path                                           | Purpose                                                               |
| ---------------------------------------------- | --------------------------------------------------------------------- |
| `fairwayvector-golfpintheory/`                 | SwiftUI app sources and bundled resources                             |
| `fairwayvector-golfpintheory/Services/`        | Course, weather, round-storage, and terrain services                  |
| `fairwayvector-golfpintheory/Trajectory/`      | Shot inputs, trajectory physics, prediction, and club recommendations |
| `fairwayvector-golfpintheory/HCPProjection/`   | Handicap projection and course-selection flows                        |
| `fairwayvector-golfpintheory/WedgeMatrix/`     | Wedge carry matrix and club selection                                 |
| `fairwayvector-golfpintheory/Assets.xcassets/` | App icon, splash art, and illustration assets                         |
| `fairwayvector-golfpintheoryTests/`            | Swift Testing unit and regression tests                               |
| `fairwayvector-golfpintheoryUITests/`          | XCUITest coverage                                                     |
| `tools/`                                       | Offline terrain preparation and saved-course packaging tools          |
| `exports/`                                     | Local-only export staging; ignored by Git                             |

The Xcode project is `fairwayvector-golfpintheory.xcodeproj`; its shared scheme and app target are `fairwayvector-golfpintheory`.

## Build

Open the project in Xcode, select the `fairwayvector-golfpintheory` scheme, and choose an iOS Simulator destination. Or build from the repository root:

```sh
xcodebuild -project fairwayvector-golfpintheory.xcodeproj \
  -scheme fairwayvector-golfpintheory \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

To compile the app and test bundles without executing tests, replace `build` with `build-for-testing`. Use Xcode's Test action only when test execution is authorized for the current development task.

## API configuration and development safety

Golf API and GPXZ are **mocked by default** in both Debug and Release. Their tracked defaults are in `fairwayvector-golfpintheory/GolfAPI.xcconfig` and `fairwayvector-golfpintheory/GPXZ.xcconfig`. Each may optionally include a local, ignored configuration file:

- `fairwayvector-golfpintheory/GolfAPI.local.xcconfig`
- `fairwayvector-golfpintheory/GPXZ.local.xcconfig`

Keep API keys in these local files or another approved secret store. Do not commit credentials, paste them into chat, or add them to tracked project settings. A key by itself does not enable a live provider: live access requires an explicit `GOLF_API_MODE = live` or `GPXZ_API_MODE = live` build-setting override. Confirm the intended provider mode in the app's Settings before testing. Return it to `mock` when live testing is complete.

Open-Meteo weather and Apple Maps are separate from these provider switches and may use network access. Mock terrain and demo course data are for development only; do not describe them as surveyed or official data.

## Tests and validation

The repository includes unit/regression tests and UI tests. Many regression tests use local fixtures or intercepted requests; inspect the test before running it and do not allow accidental live API traffic. The project has previously been validated with a Debug simulator build and `git diff --check`. A successful compile does not verify runtime behavior, persistence migration, simulator/device layouts, or test assertions.

## Email and Google login — prerelease integration (2026-10-19)

**Email/password update (2026-10-21):** The login screen supports email + password, account creation, confirmation resend, Forgot password, restricted password recovery and password change. Google browser OAuth is enabled. Sign in with Apple is temporarily paused while the Apple Developer membership migrates; its login button is disabled and the Xcode capability is removed until membership access is restored. Add `golfpintheory://auth/reset-password` to Supabase's allowed redirects alongside `golfpintheory://auth/callback`. Configure **Confirm signup** and **Reset Password** email templates (retain `{{ .ConfirmationURL }}`); Magic Link is no longer the signup template used by this UI. Returning password logins do not send email. Confirmation/reset still rely on working SMTP and same-installation PKCE. Recovery is persisted as a restricted state before exchange and blocks Home/offline content/cloud tokens. Passwords are never persisted locally. See [current dashboard checklist](backend/LOGIN_SETUP_GUIDE.md#current-email--password-configuration-supersedes-magic-link-instructions-below). Original passwordless behavior described below is superseded by this paragraph.

**Email and Google login are connected to startup; Apple login is temporarily paused.** Cloud sync is enabled by default per account and can be turned off in Settings. It syncs player name/low Handicap Index, saved scorecards, handicap-only entries, custom clubs/courses/tees, and wedge setup/calibration on app start, foreground return, and saved-data changes. Active rounds, preferences, downloaded course catalogs, and course geometry remain local. Conflicts are retained and reported, but the UI does not yet provide per-record resolution. Migrations and SQL regression scripts are tested in a local disposable PostgreSQL instance; the user reports the strict-sync capability check is installed in their Supabase project. Two-device runtime verification is still required. When Apple membership access is restored, native Apple setup can resume. Account deletion/provider revocation and full privacy review remain release gates.

**Callback scheme update (2026-10-21):** This prelaunch app does not retain the old scheme. Update the hosted redirect allowlist and any mobile Site URL as described in the setup guide; Google's HTTPS provider callback is unchanged. This scheme change has source/editor checks only, not a new build or runtime verification.

- Email uses a PKCE magic link on the requesting installation, with optional 6–10-digit email-code entry when the Supabase template includes a code. Only the `golfpintheory` URL scheme is registered; ordinary callbacks require the exact `golfpintheory://auth/callback` destination, while recovery uses `golfpintheory://auth/reset-password`. Cold-start pending email verifiers are preserved. Busy callbacks are queued in memory, never logged or persisted as URLs.
- Google uses a retained `ASWebAuthenticationSession` anchored to the actual login window, not the native Google SDK. The browser consumes its own callback; the root handles email links. Cancellation and late responses cannot open a superseded account.
- The app-wide session gates all windows and validates on foreground when possible. Previously server-confirmed sessions may reopen isolated local content offline; temporary transport/408/429/5xx failures preserve it, while known invalid credentials lock the app. Secure-storage failures have nondestructive retry and explicit credential-clearing recovery.
- SwiftData, the round archive/draft, profile, wedge data, flags and recent course selections now use project-host + user UUID storage. Explicit persistent content sentinels prevent fallback into legacy standard defaults. Legacy unowned data is preserved but never imported automatically. Units/calculator presentation preferences remain device-local. Global wedge reads were replaced with explicit account snapshots, including recommendation invalidation.
- Settings includes a default-on cloud-sync checkbox immediately before About, a manual Sync now action, and Sign out with a warning about unsaved form edits. Sync is owner-scoped and uses a durable outbox/change journal; approved domain changes auto-sync, while preferences and active drafts remain local. Signing out removes local credentials and gates the account; local records/drafts remain on this device for that account. Deletion clears local records on the current device and calls the separately configured server deletion endpoint, but does not revoke every provider session.
- Login and Settings expose current account/privacy information; the privacy manifest now declares linked email and user identity for app functionality. Public policy/store disclosures and provider data review still require release work.

- [Backend setup](backend/README.md) and [wire contract](backend/CONTRACT.md): staged SQL sources for per-user ownership, compare-and-swap revisions, immutable ordered changes, soft deletion, replay protection and strict domain payload validation. The migrations and SQL regression scripts remain undeployed/unexecuted until the operator completes the disposable-staging checklist.
- [Authentication service](fairwayvector-golfpintheory/Accounts/Auth/README.md): official Supabase Auth, browser Google sign-in, Apple auth service methods retained for future resumption, ThisDeviceOnly Keychain, cached offline identity and server-verified token access. Provider dashboard/capability configuration still must match the app bundle and environment.
- [Sync journal](fairwayvector-golfpintheory/Accounts/Sync/AccountSyncJournal.swift) and [domain adapter](fairwayvector-golfpintheory/Accounts/Sync/AccountSyncDomainAdapter.swift): the journal holds a durable outbox/conflict history and pull cursor; adapters cover the disclosed sync domains, excluding course geometry and active drafts.
- Focused offline adapter/journal tests have run successfully. The full existing suite has unrelated failures; the backend SQL migrations and SQL regression scripts have not been executed.

Public configuration defaults are blank in [Accounts.xcconfig](fairwayvector-golfpintheory/Accounts.xcconfig), included by the existing build configuration. The ignored local override has the user-supplied project URL and publishable key. Use an `sb_publishable_` client key only, never a service-role/provider secret. Xcode URL values must escape the `//` comment delimiter (for example, `https:/$()/project-ref.supabase.co`). Configuration files and the internal auth README are excluded from app resources. Build/install configuration is required; code integration does not verify your provider dashboards.

### Next integration gates

1. Verify the strict-sync capability RPC is present in the configured Supabase project before syncing.
2. On two devices, use the same account to verify initial merge/restore for every sync domain, offline retries, concurrent edits/conflicts, custom hierarchy, deletions/tombstones, account isolation, and deletion. Conflict inspection/resolution UI remains outstanding.
3. Before public release, review backup/retention/access controls, provider revocation, privacy/store disclosures, and operational recovery. Android remains a separate client workstream using this contract.

**Validation:** Debug app and full `build-for-testing` compilation passed after login integration; the existing missing `throws` test annotation was corrected. All account test sources compile, but no tests have executed. Release validation remains outstanding after the prior Xcode internal failure. No app launch, database deployment, live sign-in, email send, Golf API/GPXZ calls or secret inspection occurred. Runtime/provider and small-screen/accessibility checks remain unverified.

### First authorized device check

Startup correction (2026-10-21): the splash is now owned by the account root, so it appears before sign-in/restoration rather than only after login, and does not repeat when Home is constructed. Email request failures now display fixed operational categories (network, unauthorized project configuration, rate limit, disabled email/signup, rejected request, CAPTCHA requirement, delivery failure) without printing raw server details or recipient addresses. A successful request is not proof of inbox delivery. Check Supabase Authentication logs and your SMTP provider delivery/bounce logs at the request time if mail does not arrive. Mocked SDK request/response regressions were added and full Debug build-for-testing passed; no tests executed, app launched or emails sent for this correction. Actual delivery failure cause remains unverified without the device error/provider logs.

1. Build/install the configured app from Xcode. Expect email and Google sign-in, a disabled Apple placeholder while membership migration is pending, and no Home until sign-in.
2. Use a Google test account listed in your Google project's audience; confirm return to Home and a Google identity in Supabase Authentication → Users.
3. Sign out in Settings. Request an email link, open it on the same device and confirm Home. Code fallback needs `{{ .Token }}` in the email template.
4. Save test account-local data, restart and check restoration; after a successful login, test offline reopening. Sign out and use another account: the original data must not appear. Sign back into the first account to recover that device's records.
5. Do not enable sync until the domain-validation migration and SQL regressions pass in disposable staging. Then explicitly opt in with a disposable account on device one and restore it on device two; verify scorecards, profile facts, custom course hierarchy, wedge calibration, and handicap-only entries. Confirm drafts/preferences/downloaded catalogs/geometry remain local. Report sanitized errors only—never callback links, codes, tokens, or credentials.

## App branding and assets

The iOS display name is `Golf PinTheory` in `fairwayvector-golfpintheory/Info.plist`. The animated splash uses the `splashscreen` image set in `Assets.xcassets`; the iOS home-screen icon is the `AppIcon` image set. Explanatory golf illustrations are individual image sets in the same catalog. Keep each asset's catalog name stable when replacing its image, since SwiftUI loads many by name.

## Offline terrain tooling

`tools/TERRAIN_PREPARATION.md` describes an **archived** Hills DEM preparation workflow. It is not part of the active GPXZ runtime. `tools/prepare_hills_terrain.py` requires the optional packages listed in `tools/terrain-requirements.txt`; install them in a project-specific Python environment only if working on that archived tool. Never fetch provider data or use credentials unless the task explicitly authorizes it.
