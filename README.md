# PinTheory for iOS

PinTheory is a SwiftUI golf companion for course discovery and on-course planning, round scoring and statistics, handicap projections, club setup, wedge planning, and golf-shot trajectory estimates.

## Requirements

- macOS with Xcode installed. The project currently sets an iOS deployment target of 26.5; use an Xcode version and simulator/runtime that support the project settings.
- Git for source control.
- Swift Package Manager access on the first build. The staged account service uses the official Supabase `Auth` product, pinned to 2.55.4; commit the shared package-resolution lockfile.

## Project layout

| Path                                       | Purpose                                                               |
| ------------------------------------------ | --------------------------------------------------------------------- |
| `fairwayvector-pintheory/`                 | SwiftUI app sources and bundled resources                             |
| `fairwayvector-pintheory/Services/`        | Course, weather, round-storage, and terrain services                  |
| `fairwayvector-pintheory/Trajectory/`      | Shot inputs, trajectory physics, prediction, and club recommendations |
| `fairwayvector-pintheory/HCPProjection/`   | Handicap projection and course-selection flows                        |
| `fairwayvector-pintheory/WedgeMatrix/`     | Wedge carry matrix and club selection                                 |
| `fairwayvector-pintheory/Assets.xcassets/` | App icon, splash art, and illustration assets                         |
| `fairwayvector-pintheoryTests/`            | Swift Testing unit and regression tests                               |
| `fairwayvector-pintheoryUITests/`          | XCUITest coverage                                                     |
| `tools/`                                   | Offline terrain preparation and saved-course packaging tools          |
| `exports/`                                 | Local-only export staging; ignored by Git                             |

The Xcode project is `fairwayvector-pintheory.xcodeproj`; its shared scheme and app target are `fairwayvector-pintheory`.

## Build

Open the project in Xcode, select the `fairwayvector-pintheory` scheme, and choose an iOS Simulator destination. Or build from the repository root:

```sh
xcodebuild -project fairwayvector-pintheory.xcodeproj \
  -scheme fairwayvector-pintheory \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

To compile the app and test bundles without executing tests, replace `build` with `build-for-testing`. Use Xcode's Test action only when test execution is authorized for the current development task.

## API configuration and development safety

Golf API and GPXZ are **mocked by default** in both Debug and Release. Their tracked defaults are in `fairwayvector-pintheory/GolfAPI.xcconfig` and `fairwayvector-pintheory/GPXZ.xcconfig`. Each may optionally include a local, ignored configuration file:

- `fairwayvector-pintheory/GolfAPI.local.xcconfig`
- `fairwayvector-pintheory/GPXZ.local.xcconfig`

Keep API keys in these local files or another approved secret store. Do not commit credentials, paste them into chat, or add them to tracked project settings. A key by itself does not enable a live provider: live access requires an explicit `GOLF_API_MODE = live` or `GPXZ_API_MODE = live` build-setting override. Confirm the intended provider mode in the app's Settings before testing. Return it to `mock` when live testing is complete.

Open-Meteo weather and Apple Maps are separate from these provider switches and may use network access. Mock terrain and demo course data are for development only; do not describe them as surveyed or official data.

## Tests and validation

The repository includes unit/regression tests and UI tests. Many regression tests use local fixtures or intercepted requests; inspect the test before running it and do not allow accidental live API traffic. The project has previously been validated with a Debug simulator build and `git diff --check`. A successful compile does not verify runtime behavior, persistence migration, simulator/device layouts, or test assertions.

## Email and Google login — prerelease integration (2026-10-19)

**Email and Google login are connected to startup; cloud sync is not.** A configured build restores its session or shows the login screen before Home. Apple is intentionally absent from the login UI. This is a prerelease test integration, not ready for public distribution: account deletion/provider revocation, full privacy review and cloud saved-content integration remain outstanding.

- Email uses a PKCE magic link on the requesting installation, with optional 6–10-digit email-code entry when the Supabase template includes a code. The `pintheory` URL scheme is registered; only the exact `pintheory://auth/callback` destination is accepted. Cold-start pending email verifiers are preserved. Busy callbacks are queued in memory, never logged or persisted as URLs.
- Google uses a retained `ASWebAuthenticationSession` anchored to the actual login window, not the native Google SDK. The browser consumes its own callback; the root handles email links. Cancellation and late responses cannot open a superseded account.
- The app-wide session gates all windows and validates on foreground when possible. Previously server-confirmed sessions may reopen isolated local content offline; temporary transport/408/429/5xx failures preserve it, while known invalid credentials lock the app. Secure-storage failures have nondestructive retry and explicit credential-clearing recovery.
- SwiftData, the round archive/draft, profile, wedge data, flags and recent course selections now use project-host + user UUID storage. Explicit persistent content sentinels prevent fallback into legacy standard defaults. Legacy unowned data is preserved but never imported automatically. Units/calculator presentation preferences remain device-local. Global wedge reads were replaced with explicit account snapshots, including recommendation invalidation.
- Settings includes Sign out with a warning about unsaved form edits. Signing out removes local credentials and gates the account; saved records/drafts remain on this device for the same account, not another account. It does not delete the server account or revoke all remote sessions. Nothing uploads golf records yet, so there is no cloud backup or cross-device restore.
- Login and Settings expose current account/privacy information; the privacy manifest now declares linked email and user identity for app functionality. Public policy/store disclosures and provider data review still require release work.

- [Backend setup](backend/README.md) and [wire contract](backend/CONTRACT.md): undeployed Supabase SQL migration, per-user ownership, compare-and-swap revisions, immutable ordered change events, soft deletion and mutation-ID replay protection. Conflicts return the server version without overwriting either submission. SQL regression scripts are included but have not been executed.
- [Authentication service](fairwayvector-pintheory/Accounts/Auth/README.md): official Supabase Auth, ThisDeviceOnly Keychain, cached offline identity and server-verified token access. Unexposed Apple service methods remain for future work; no Apple capability or button is enabled.
- [Sync journal](fairwayvector-pintheory/Accounts/Sync/AccountSyncJournal.swift): account UUID-scoped atomic local snapshot, durable outbox/conflict history and pull cursor. The coordinator provides bounded push/pull and invalidation guards. This journal is NOT a copy of the existing SwiftData/round/profile stores.
- Account test sources cover configuration, injected auth responses/storage, late callbacks, journal persistence, account separation, conflicts, replay and pagination. No tests have been executed for this phase.

Public configuration defaults are blank in [Accounts.xcconfig](fairwayvector-pintheory/Accounts.xcconfig), included by the existing build configuration. The ignored local override has the user-supplied project URL and publishable key. Use an `sb_publishable_` client key only, never a service-role/provider secret. Xcode URL values must escape the `//` comment delimiter (for example, `https:/$()/project-ref.supabase.co`). Configuration files and the internal auth README are excluded from app resources. Build/install configuration is required; code integration does not verify your provider dashboards.

### Next integration gates

1. Approve typed domain payload allowlists and stable IDs. Split saved profile facts from preferences; exclude downloaded course geometry. Support geometry-free saved-scorecard history, explicit handicap-import linkage, and custom-course references.
2. Extend the account-local repositories with durable domain mutations and pull application. Do not adopt legacy development records into the first account automatically.
3. Add cloud bootstrap, sync status and conflict-resolution UI. Default seeds must not overwrite cloud content. Apple remains deferred by user request; Google-only social login needs App Store guideline 4.8 review before release.
4. Implement authenticated, idempotent server-side account blocking/deletion, provider revocation and retained-event purge. The current immutable audit history intentionally prevents casual cascading deletion; do not deploy without the deletion workflow. Add sign-out handling for unsynced changes/drafts, privacy policy/disclosures, operational retention/backups and review access.
5. Deploy and validate the SQL in isolated staging with two accounts, then perform authorized auth and multi-device tests. Android remains a separate client workstream using this contract.

**Validation:** Debug app and full `build-for-testing` compilation passed after login integration; the existing missing `throws` test annotation was corrected. All account test sources compile, but no tests have executed. Release validation remains outstanding after the prior Xcode internal failure. No app launch, database deployment, live sign-in, email send, Golf API/GPXZ calls or secret inspection occurred. Runtime/provider and small-screen/accessibility checks remain unverified.

### First authorized device check

1. Build/install the configured app from Xcode. Expect email and Google login, no Apple button, and no Home until sign-in.
2. Use a Google test account listed in your Google project's audience; confirm return to Home and a Google identity in Supabase Authentication → Users.
3. Sign out in Settings. Request an email link, open it on the same device and confirm Home. Code fallback needs `{{ .Token }}` in the email template.
4. Save test account-local data, restart and check restoration; after a successful login, test offline reopening. Sign out and use another account: the original data must not appear. Sign back into the first account to recover that device's records.
5. Do not expect a second device to contain golf data yet. Report sanitized error text only, not callback links, codes or session credentials.

## App branding and assets

The iOS display name is `PinTheory` in `fairwayvector-pintheory/Info.plist`. The animated splash uses the `splashscreen` image set in `Assets.xcassets`; the iOS home-screen icon is the `AppIcon` image set. Explanatory golf illustrations are individual image sets in the same catalog. Keep each asset's catalog name stable when replacing its image, since SwiftUI loads many by name.

## Offline terrain tooling

`tools/TERRAIN_PREPARATION.md` describes an **archived** Hills DEM preparation workflow. It is not part of the active GPXZ runtime. `tools/prepare_hills_terrain.py` requires the optional packages listed in `tools/terrain-requirements.txt`; install them in a project-specific Python environment only if working on that archived tool. Never fetch provider data or use credentials unless the task explicitly authorizes it.
