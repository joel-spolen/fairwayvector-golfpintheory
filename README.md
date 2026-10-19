# PinTheory for iOS

PinTheory is a SwiftUI golf companion for course discovery and on-course planning, round scoring and statistics, handicap projections, club setup, wedge planning, and golf-shot trajectory estimates.

## Requirements

- macOS with Xcode installed. The project currently sets an iOS deployment target of 26.5; use an Xcode version and simulator/runtime that support the project settings.
- Git for source control.
- No third-party package resolution is required for the standard app build.

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

## App branding and assets

The iOS display name is `PinTheory` in `fairwayvector-pintheory/Info.plist`. The animated splash uses the `splashscreen` image set in `Assets.xcassets`; the iOS home-screen icon is the `AppIcon` image set. Explanatory golf illustrations are individual image sets in the same catalog. Keep each asset's catalog name stable when replacing its image, since SwiftUI loads many by name.

## Offline terrain tooling

`tools/TERRAIN_PREPARATION.md` describes an **archived** Hills DEM preparation workflow. It is not part of the active GPXZ runtime. `tools/prepare_hills_terrain.py` requires the optional packages listed in `tools/terrain-requirements.txt`; install them in a project-specific Python environment only if working on that archived tool. Never fetch provider data or use credentials unless the task explicitly authorizes it.
