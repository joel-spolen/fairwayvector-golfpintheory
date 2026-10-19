# PinTheory — development API pause + GPXZ terrain

## Shared Golf API course selection in Handicap

**Add round** and **Predict → Choose Golf API course** share Course map's
`GolfAPICourseSelectionModel`, client and persistent detail/search caches, including
the real saved Hills bundle. Handicap selection is selection-only: no map start,
scorecard resume/discard, location permission, coordinate download, terrain request
or provider update check. Course detail is loaded only after explicitly choosing a
course or recent entry; cached detail is reused. Map retains its GPS requirement
and original defaults; Handicap can use rated provider courses without GPS.

The chooser uses the Profile's Men/Women rating category and offers every eligible
tee for that category. A recent HCP or map reference is revalidated by provider ID
and tee ID; a different sex or unavailable tee requires explicit tee choice, never
a silent swap. HCP has its own recent preference and does not overwrite map recents.
Exact selected rating, slope, hole count, actual hole pars/total par and valid unique
provider stroke indices are used. Only real 9/18-hole courses with finite positive
CR (up to 100), slope 55–155 and complete pars (3–6) are accepted. Missing/invalid SI
disables hole-by-hole entry, not adjusted-gross/Stableford; no provider pars or SI
are invented. Nine-hole calculations retain the existing HCP limitations and notices.

**Use a custom course** is explicitly separate user-entered data, not a name match
to provider courses. **No course** preserves manual official-differential entry.
The old Sweden catalog is not an Add round/Predict selection source. Existing
history snapshots, WHS calculators and SwiftData schema/persistence are unchanged;
provider identity lives only in transient selection state and recent references.
Demo courses are excluded from both HCP choosers and rejected by conversion; they
cannot create real HCP history. API mock modes remain paused/read-only, and searches
show saved detail-only courses without requiring GPS caches. Live mode still needs
explicit build-time activation; uncached explicit search/detail may then use Golf API.

Offline regression source covers exact conversion, tee overrides, nine-hole SI,
invalid/missing data, demo exclusion, category-safe recents, detail-only reuse in
both modes and unchanged map GPS gating. Tests must not be executed during the
development pause; compile-only validation does not verify runtime UI or assertions.

## Played rounds, scorecards & Statistics

**Start round** is available from Home, the normal course/tee selector (including
saved-course shortcuts), and the current map's **Round** menu. Selection uses the
existing cached/provider flow; round setup itself adds no fetch. Confirm the loaded
course and tee, choose **Stroke play / Stableford**, **Detailed / Strokes only**,
and add up to seven other named players alongside **You**. Handicap Index defaults
from the shared calculated HCP history, otherwise an explicitly saved exact index
in the shared Profile. Unknown index remains unknown; scratch 0 must be explicit.
Indexes accept −10…54 (plus 2 is −2). Individual casual playing allowance defaults
to 100%, with an explicit 0…100% setting; no event/competition policy is assumed.
All players use the selected rated tee and the chosen global detail mode.

Only an explicitly started/resumed round changes map navigation. **Next hole**
opens a multi-player hole scorecard; its last-hole counterpart scores and reviews
the round. Every player must confirm strokes before advancement. Previously scored
holes are editable from **Scorecard → Review / finish round**; review can select
any hole, and advancement seeks remaining unscored holes rather than silently
finishing a partial card. Casual map browsing never opens score sheets. Current
geometry, tee, actual hole numbers/par/SI and player IDs are snapshotted; changing
course pauses rather than discards the draft. **Resume round** appears
in Choose Course after restart and uses the saved geometry without a new course
load. Existing weather/imagery and committed terrain behavior are unchanged.

Strokes are integer **total strokes, including putts and penalties**, 1…30. Counts
never add strokes twice. Detailed mode has optional putts, bunker-shot counts and
penalty counts, bounded by total strokes; putts + penalties cannot exceed strokes.
Fairway is Yes / No / N/A / Not recorded; par 3 is N/A. Unrecorded details remain
nullable, never fabricated zero. **Estimated GIR** is `strokes − putts ≤ par − 2`
when putts and actual par exist, not a measured green-arrival statistic; penalties,
recovery play and unusual sequences affect the estimate. Strokes-only has no GIR
or invented detail statistics. No pickup/zero-stroke convention is introduced.

Summary shows gross, net, Stableford, optional detail tallies, **Course Handicap**,
**Playing Handicap**, **net-double-bogey adjusted gross** and **HCP score / score
differential (PCC 0)** as distinct values. Valid applicable tee rating/slope, actual
par and unique real SI are required for handicap-dependent results. Missing data
gets guidance and gross-only scoring, not fabricated pars/indexes/ratings. Full
18-hole Course Handicap is `HI × slope/113 + CR − par`, rounding halves upward;
the shared WHS calculator now uses that rounding and corrected plus-handicap
allocation. Nine-hole Course Handicap uses half the HI contribution with the
applicable nine-hole rating/par. Actual odd/even full-course SI on nine-hole sides
is ranked within those nine holes. Positive handicaps receive remainder strokes
on lowest SI; plus handicaps give them back on highest SI. Net and Stableford
use Playing Handicap; points are `max(0, 2 + par − net strokes)`. WHS adjusted gross
uses full Course Handicap independently of the playing allowance.

**Nine-hole scores:** an established Handicap Index enables WHS expected-score
conversion: the played nine-hole differential is combined with the expected
nine-hole differential based on the current Index, then rounded to a tenth. The
expected value follows the published 9-hole expected-differential table. When no
current Handicap Index is available, a nine-hole differential cannot be estimated.
Scores are never doubled or extrapolated. 18-hole differential is
`(adjusted gross − CR − PCC) × 113/slope`, using shared rounding and PCC 0. These
are local estimates, not an official submission. Demo
course results remain visibly synthetic and cannot enter HCP history. A projected
local index is shown only for eligible rounds with at least three existing shared
scoring entries, using the existing chronological exceptional-score/cap rules;
it is not claimed to be an exact official new index.

**Save round to Statistics** is explicit; a durable draft is not a saved round.
One root-injected `PlayedRoundStore` owns versioned Codable storage in Application
Support/FairwayVectorRounds, with atomic protected writes, stable round/player/
hole identities, separate saved records and active draft. Each confirmed hole and
map-hole change persists the draft. Write failures retain the latest memory draft,
show recovery guidance and permit retry; the prior disk archive remains intact.
If writing fails, latest edits cannot survive process termination until retry
succeeds. Corrupt/unsupported storage blocks overwrite and preserves existing
bytes. Discard/delete require confirmation and only publish success after writing.
Saved scorecards are read-only; active draft holes can be edited.

The dedicated **Statistics** tab provides owner-only averages and dated saved
rounds with player-switchable full scorecards. Gross/net per-hole averages use
matched holes, putts use only recorded holes, fairways exclude par 3/N/A/unanswered,
GIR requires putts/par, bunker-hole rates use recorded bunker holes, and penalties
are normalized per 18 **recorded** holes. All denominators are shown. Round total
averages are separated into nine/eighteen-hole groups; putts per round includes
only fully recorded cards. Other players are saved with the card but never included
in your personal aggregates or automatically copied to HCP history.

After saving, **Add your score to Handicap rounds** is a separate owner-only opt-in.
It inserts a real `GolfRound` in the existing SwiftData container, preserving date,
tee rating/slope, total hole scores, actual par/SI, adjusted gross and differential.
An optional additive `sourceSavedRoundID` links the copy, checked directly in the
shared history to prevent repeated imports across restart. Existing
`SharedHandicapSync` observes that history as before. No parallel incompatible HCP
history is introduced. Deleting Statistics retains any explicit Handicap copy,
as explained in the confirmation; manage that copy in Handicap. Existing container
recovery no longer deletes the user's HCP database on opening/migration failure;
it fails closed with the original store preserved. Migration/runtime behavior is
not validated by a compile-only build.

Offline regression **source** covers allocation/plus rounding, nine-hole ranking,
gross/net/WHS separation, nullable denominators and multi-player exclusion,
validation, draft resume/explicit save/delete, corrupt storage preservation,
write-failure retention/retry, shared-HCP idempotence and projection eligibility.
Validation compiles app + unit/UI test bundles only, using generic Debug simulator,
blank keys, both provider modes mock and package resolution disabled. Tests are
**not executed**; no app is launched, APIs called or secrets inspected. Small-screen,
sheet transitions, restart, disk errors and existing-store migration still need
authorized runtime checks. No scheme/package changes are required.

Final fresh Debug `build-for-testing` and Release app compilation succeeded in
`/tmp/fairwayvector-rounds-final-debug-20261005` and
`/tmp/fairwayvector-rounds-final-release-20261005`. The new regression source has
arm64 and x86_64 objects; unit/UI bundles and the xctestrun artifact exist, but were
not executed. Both compiled Info plists were checked: Golf API / GPXZ modes are
`mock`, keys are blank. Editor diagnostics and `git diff --check` are clean.

## Compact Course Map controls

The map uses independent top/bottom safe-area insets rather than an oversized
overlay stack. Front / center / back, selected point and point-to-flag distances
remain at the top (adaptive second row when space is tight), with a single
temperature / wind summary. Wind is a small camera-heading-relative **blowing-TO**
arrow, not a separate large compass card. The bottom contains compact club advice,
a signed committed origin-to-target terrain delta, and one hole / par / stroke
index / length navigation row. Ordinary lower controls fit roughly 180–220 points;
their content-measured scroll area is capped at 170 points plus hole navigation,
so larger accessibility text scrolls instead of clipping or covering the map.
Distances have no fixed-height text container. The main tab bar remains hidden.

- **Tap weather** for the original temperature, humidity, weather elevation,
  surface/sea-level pressure, wind direction/speed/gusts, Open-Meteo source,
  observed time/timezone, fetched/cache age, loading and provider error. Opening
  the sheet reads the existing location-associated store only. The single
  automatic location-load task stays on the summary; Refresh / Retry is manual
  and retains the existing request/cache behavior.
- **Tap terrain**, including **Terrain unavailable**, for the existing full
  Hole / Current shot chart, inspection marker, both shot-leg source metadata,
  provider errors and local budget / planned-span information. Retry / refresh
  now lives here and still requires the same confirmation, retains reservations
  and backoff, and never authorizes live paid acquisition for a simulated origin.
  Opening details, changing chart mode or inspection never loads new terrain.
- **Tap club advice**, even with no target/result/calibration, for complete
  actionable status and **Wedge calibration & matrix** / **Practice / Profile**
  setup sheets. Available advice shows just the best club/scoring combination,
  carry with short/long error and a concise nearest-alternatives line. Details
  retain all ranked/unavailable combinations, trajectories, captured conditions,
  calibration assumptions and source provenance. No Practice inputs or engine
  calculations are changed by the compact presentation.
- **Tap toolbar information or the hole row** for course/club/tee/ratings,
  GPS/tee-fallback and point-only geometry explanations, saved-course update
  errors and data credits. Short **Saved Hills / DEMO terrain** and **Simulated
  position** badges remain on the map; synthetic data is never presented as real.

In DEBUG builds, the persistent **dice / DEV** toolbar menu (accessibility label
**Development tools**) is visible whenever a course is selected, including
loading or missing-hole states. It contains **Random scoring position**, **Use
device GPS**, personal wedge/profile setup and guidance. Entries, not the whole
menu, disable when geometry/calibration is missing or a request/held gesture is
pending; setup remains reachable. Toolbar and hole navigation targets are at
least 44 points. Ordinary advice invalidation no longer sets `shotPending` as if
a gesture were held; a cancelled target drag clears that gate without committing
or fetching. Generator, calibrated threshold, provider modes, real GPS and paid
blocking rules are unchanged. The former large development overlay is removed.

Validation is compile-only (Debug and Release with keys blank, provider modes
mock and package resolution disabled), editor diagnostics and whitespace checks.
No tests, app launch, provider/network requests or secret-file inspection.
Small-screen/Dynamic Type appearance and sheet interactions remain runtime
unverified under those restrictions.

## On-course scoring mode — personal wedge range

### DEBUG-only random scoring position

Course Map has a persistent **Development tools** dice/DEV toolbar menu in DEBUG
builds only. It reads the same `ScoringShotPlan.make(...).maxFullCarryM` as the
recommendation engine: the longest eligible personal Mid/Stock 100% wedge carry,
never a stock 100 m threshold. Missing calibration disables it with guidance to
**Wedge calibration & matrix** / **Practice / Profile**; profile setup is required.
Defaults and unverified legacy carries do not enable it.

The target is the selected point, otherwise the saved custom flag / green target.
A spherical forward geodesic places the golfer toward the tee with ±20° jitter,
normally 25–80% of personal range, with a 3 m preferred minimum when possible and
a cap short of the tee. Very short ranges safely collapse to a single distance;
positions below 0.2 m cannot be generated. The actual `CLLocation` horizontal
distance must exceed 0.1 m and be ≤99% of personal range and pass the existing
scoring helper. Course information shows measured distance and personal threshold. This
directional placement is not verified fairway/obstacle containment.

Simulation is ephemeral view state, bypasses the ordinary 100 m GPS corridor
resolver, and never changes `CLLocationManager`, Practice or the player profile.
**DEV YOU** replaces the real user marker; committed card/detail/terrain labels
say **Simulated golfer · Development**, with `usesGPS == false` and separate
simulation metadata. GPS fixes continue normally but cannot move simulation.
**Use device GPS** clears it and captures real GPS or the normal tee fallback
cache-only. Hole/course/tee/geometry/flag changes and leaving the map clear it.
Bottom hole controls and the hidden main-tab layout are retained.

Random placement immediately selects/commits the target through existing terrain
and recommendation generation/cancellation guards. Mock GPXZ fills only isolated
local synthetic terrain; live GPXZ is **cache-only**, including simulated target
release and confirmed terrain refresh (no failure-lock clearing). Neither button
fetches Golf API or weather. Existing course-associated weather and matching
terrain endpoints are still required: live cache gaps block advice with explicit
guidance, never fake flat heights. Provider modes and keys are unchanged. There
is no release-build button, override state, random generator or simulated marker.

Scoring is selected only when the **committed horizontal origin→target distance
is positive and ≤ the longest eligible personal Mid/Stock 100% wedge carry**.
The existing capture requires distance >0.1 m. Equality is included; even 0.001 m
beyond the range retains ordinary full-bag suggestions. There is no hard-coded
metre/yard limit, and GPS being enabled does **not** activate scoring at 400 m.
Weather/elevation do not alter this nominal mode boundary. The origin, target
and GPS/tee source remain the immutable committed terrain request: subsequent
GPS fixes never move advice or change mode. Target release or confirmed terrain
refresh recaptures the origin using the existing flow.

**True GPS is not required for a testing preview.** Existing tee fallback is
allowed at the same distance threshold and labelled **Tee-fallback scoring
preview**, not golfer proximity. Details state the personal range and rationale;
the card shows the best full shot title (club · Low/Mid/High · 50/75/100%), plus the closest two
valid combinations. Details browse every ranked reachable combination by unique
shot ID, with the selected physics trajectory and corrected scalar outputs.
Unavailable combinations are separately listed with their individual reasons;
an entirely unavailable scoring bag is not replaced with full-bag advice.

### Personal carry sources and migration

- Wedge Matrix remains yards internally regardless of display units; carries
  convert once with 0.9144 m/yd. In-bag wedges with an entered Mid/Stock Full cell
  or an explicitly user-provided Add Club full carry establish the range. The
  new `fullCarryUserProvided` field records Add Club provenance without changing
  existing matrix calculations. Existing cell overrides remain authoritative.
- Untouched `Wedge.defaults`, missing/corrupt saved matrices and legacy
  `fullCarry` values with no override/provenance are **not** user calibration.
  Old Add Club records without a Full override cannot be safely distinguished
  from saved defaults: re-enter Stock Full carry. Partial-only cells do not
  establish a full-wedge range. No fabricated stock threshold is substituted.
- Without an authoritative matching matrix entry, available Practice wedges
  can use the actual effective nominal carry when its source is user-provided,
  calibrated or interpolated from user carry anchors, not handicap baseline.
  Interpolated carries are estimates, not measured wedge calibration. Explicit
  matrix out-of-bag entries exclude their matching Practice wedge. Untouched
  in-bag matrix defaults do not mask a valid Practice calibration.
- Matrix in-bag status is authoritative for calibrated matrix wedges and need
  not mutate the Practice bag. Names map explicitly to PW, GW/50, 52, SW/54,
  56, 58 or LW/60 (including “Wedge” forms). Unknown/custom names are not guessed;
  guidance requests an identifiable loft. No cross-club matching by nearest carry.
- Missing calibration shows setup guidance and a local **Wedge calibration &
  matrix** sheet. Ordinary full-bag advice remains available using its existing
  profile requirements; its shared Practice engine and state are unchanged.

### Nine shots per wedge and honest model limitations

Each eligible wedge contributes **3 trajectories × 3 swing lengths = 9** specs.
Entered per-cell carry is used verbatim. Other cells reuse the **existing Wedge
Matrix model**: half/“50%” carry factor **0.70**, three-quarter/“75%” **0.90**,
Full/“100%” **1.00**; Low **0.92**, Mid/Stock **1.00**, High **0.96**. These are
estimated cell carries, not measured shots. “100%” means stock full carry, not
maximum effort. Swing labels are **not** literal carry or ball-speed percentages.
The on-course engine does not use the matrix selector's invented rollout,
pin-distance bias, swing penalties or strategic ranking.

The current matrix stores **no shot-specific launch angle or spin calibration**.
Consequently Low/High flight shapes cannot be recovered from entered carry alone.
The explicit, unvalidated modeling fallback is effective Practice launch angle
**−6° / unchanged / +6°**, clamped to **5–80°**, with effective profile spin rate
and spin axis retained for every swing. No partial-spin measurement or confidence
interval is fabricated. Each candidate exposes carry source, cell-estimate
factors, launch/spin field provenance and these assumptions in its details.
This flight-shape assumption is not an existing Wedge Matrix measurement or a
claim of validated low/high technique. Actual partial-shot launch/spin may differ
substantially; adding measured per-shot launch/spin storage remains future work.

Ball speed is **inversely fitted**, not scaled by 0.50/0.75: the same bundled
Physics V1.1 + HGB predictor solves nominal carry at **20°C, 1013.25 hPa,
50% humidity, zero wind, level ground**. A bounded first-crossing search uses
16 intervals across 2–90 m/s followed by 14 refinement steps, with closest-fit
error ≤0.5 m. HGB residuals can be discontinuous; unbracketable/non-finite shots
or fits outside tolerance are explicitly unavailable, not presented as exact
calibration. The 0.5 m figure is a numerical fit tolerance, **not real-world
accuracy**. Reference conditions are a modeling convention: matrix carry entries
do not store the conditions in which the user measured them.

After that reference fit, captured temperature, humidity, **local surface
pressure**, meteorological FROM wind rotated to shot tail/right components and
target-minus-origin terrain height are applied normally by the shared engine.
There is no calm/flat weather fallback, sea-level pressure substitution,
double altitude correction or second “plays-like” carry adjustment. Ranking is
the existing absolute **hybrid radial-carry error** with deterministic candidate
order ties. It is not lateral-miss/aim optimization, roll, obstacle clearance,
green reading or a guaranteed target hit. HGB training-domain validity for very
short/low/high shots has not been established; physics paths and corrected
scalar carry remain distinct. Synthetic development terrain keeps its warnings.

Reference fitting and evaluation run on a separate background actor with
cancellation checks and a bounded 126-entry calibration cache. At most 14
in-bag eligible wedges / 126 combinations are supported; larger bags show
guidance rather than synchronously evaluating or silently truncating them.
The existing task cancellation and complete input-equality publication guards
also cover matrix edits, weather, profile and committed target changes. No
Practice selected club, inputs, profile, persisted conditions or prediction are
written. Providers, paid-ledger behavior and default mock modes are untouched.

Offline regression **source** covers inclusive boundaries, GPS-on far targets,
tee preview/immutable origin, 9-per-wedge identities, matrix-cell precedence,
legacy/default rejection, effective Practice carry fallback, out-of-bag status,
unknown loft/invalid cells/oversized bags, reference fitting, stable rankings,
captured wind/pressure/terrain application, cancellation and Practice isolation.
Validation is app + test-source compilation only; no tests execute, app launches,
provider/network requests or credential-file reads are authorized here.
Fresh generic iOS Simulator `build-for-testing` completed successfully with
both provider keys overridden blank and package resolution/updates disabled.
Both compiled provider modes remain `mock`; new regression objects were verified
for arm64 and x86_64, alongside compiled unit/UI test bundles. No tests ran or app
launched. Runtime UI, fit success across a real user's matrix and short-shot
accuracy remain unverified. Editor diagnostics and whitespace checks are clean;
Xcode emitted only its existing supported-platform diagnostic.

## Development pause — default for BOTH Debug and Release

**Golf API and GPXZ default to MOCK, regardless of existing credentials.**
Tracked build settings are `GOLF_API_MODE = mock` and `GPXZ_API_MODE = mock`.
The shared `DevelopmentAPIConfiguration` reads their Info.plist values; only
an explicit `live` value enables a provider. Missing/blank/unknown/unexpanded
values are mock. Existing ignored credential files were not read or edited.
Settings displays each provider's read-only mode. There is no persisted runtime
toggle and no automatic activation when a key exists.

- Golf API search/detail/coordinates/refresh run locally. Complete downloaded
  real provider courses appear **before** demo results, using read-only detail
  and coordinate caches under Application Support / GolfAPI, with reviewed
  bundled real Hills as a read-only fallback on fresh devices. Existing search
  metadata supplies club/country names when detail omits them, but search-only
  records cannot masquerade as available offline geometry. Search filters
  use their cached country, region and club/course names. Force refresh is still
  read-only: no update check, write, migration or network. Saved-course shortcuts
  retain the actual provider course ID, tee ID, ratings, sex and detail location.
- A usable live recent selection takes precedence over an old demo shortcut.
  The live recent preference is not changed in paused mode; paused selections
  use the existing separate development preference. CourseStore first reads
  exact tee-specific durable CourseData or flat legacy geometry, even for real
  Golf API/OSM references, without migration/writes. If necessary it rebuilds
  geometry in memory from cached real provider detail/coordinates. Missing or
  invalid real data reports **APIs paused / downloaded data unavailable**;
  it never remaps that reference or returns invented geometry under a real ID.
- **Demo Hills** remains a separate, clearly labelled invented 18-hole fallback
  for Sweden / Hills searches. Layout near 57.62° N, 12.00° E, tee lengths,
  par/indexes and ratings are **not factual Hills data**. Demo payloads are
  restricted to the explicit demo ID. This is not worldwide offline coverage.
- Synthetic elevations form a smooth coordinate-based rolling surface, with
  coherent shared endpoints, no survey dates and no surveyed height datum.
  Charts/source metadata and recommendations say **Synthetic development terrain**
  / **DEMO DATA**. Not for play, navigation, real ratings or terrain assessment.
- GPXZ mock profiles use the same serialized overlap planner and journal/cache
  machinery, under `development-gpxz-v1:<courseID>` plus a separate versioned
  synthetic sidecar. Open/reopen and target commits can compute local fixtures,
  even with cache-only paid permits. They never read/write the live sidecar or
  inspect/initialize/reserve/reset the live budget, failure locks or backoff.
  UI shows **Mock · 0 paid requests**, not a reset live quota. Historical calls
  (including the existing five), locks and initialization markers stay intact.
- Both clients hard-gate at their final transport method **before URLSession**.
  Mock mode does not load bundle keys; explicit injected keys cannot enable it.
  Golf API mock reads valid saved provider caches, but never writes them.
  Demo IDs are blocked from live provider requests after switching modes.
- **Open-Meteo weather and Apple Maps remain live/cache-backed and unchanged.**
  Recommendations still require complete matching weather and the existing
  Practice bag/calibration; no invented wind, weather or launch calibration.

### Explicit activation for later authorized testing

Leave tracked defaults at `mock`. In the existing ignored local config for the
provider being tested, add **`GOLF_API_MODE = live`** or **`GPXZ_API_MODE = live`**,
respectively. Local includes occur **after** tracked defaults. Keep the existing
`GOLF_API_KEY` / `GPXZ_API_KEY` privately configured there; never paste/print them.
Alternatively set those mode build settings explicitly in Xcode or as xcodebuild
build-setting overrides. Rebuild/reinstall and verify Settings says **LIVE** for
only the intended provider before using it. Keys alone never activate a provider.
To pause again, remove the local mode override or set it to `mock`, rebuild and
verify Settings. No UI action can flip a mock build to live.

Already-downloaded real courses need **no activation** to reopen in paused mode.
For new real-course downloads enable Golf API, select a real provider course
instead of a demo reference, and enable GPXZ separately when authorized. Live
mode retains the existing cache-first release-only acquisition, 100-call ledger,
failure-lock and backoff rules described below. Live course searches/update
checks and explicit missing shot terrain acquisition can spend provider calls.
This does not validate provider acceptance, account credentials or billing.

Offline regression **source** covers fail-safe mode parsing, existing-key mock
gates, saved-before-demo filters, read-only detail/coordinates/flat/durable caches,
real-ID/tee/location preservation, corrupt/missing data without impersonation,
18-hole demo geometry, synthetic endpoints,
reversal/relaunch coverage, untouched five-call ledger/locks/markers/live cache,
and absence of new ledger initialization. Transport-evaluation tests now opt in
to `.live` explicitly **only with intercepted offline URLSessions**. Compilation
is permitted; test execution/app launch/live API calls are not part of this work.

### Portable saved real Hills (2026-10-05)

Earlier simulator inspection found no complete Hills download. The subsequently
authorized connected-iPhone export recovered exactly five already-downloaded JSON
files for real Golf API course **0121161534832877**, club **141519520190750993**.
No new provider download was needed. No keys, ledger, preferences, player profile,
score store or unrelated app files were copied or inspected.

`fairwayvector-pintheory/Resources/SavedCourses/Hills/` contains five portable resources:

- `course-0121161534832877-detail.json`: six original tees and original ratings.
- `course-0121161534832877-coordinates.json`: 121 original public provider points.
- `hills-club.json`: original matching Hills club metadata with **only Hills**;
  the undownloaded Valley course is removed.
- `course-0121161534832877-hills-golf---sports-club-hills-62-male-golfapi-v1.json`:
  byte-exact downloaded 18-hole geometry for tee **62 / Men**, tee ID **185072**,
  rating **74.7**, slope **140**. Paths verified against the original provider
  tee midpoint/green-center coordinates and all 18 original measured lengths.
- `hills-manifest.json`: original/resource SHA256 digests, counts and review limits.

Provider detail/coordinates retain all course fields; account `apiRequestsLeft`
metadata is omitted from portable copies. Club search counters are not bundled.
`BundledSavedCourseStore` reads resources only; paused searches show **Saved Hills
offline · APIs paused** before the separate invented Demo Hills. Complete local
downloads take precedence. CourseStore reads exact local saved geometry first,
then the exact bundled 62/Men export. Other rated tee/sex references rebuild in
memory from original provider payloads (five men's and six women's rated sets).
No tee coordinate is invented or moved to match measured lengths; provider GPS
is point-only and does not supply distinct tee-set positions or fairway polygons.
No live cache is rewritten, migrated or populated by paused bundle reuse.
Missing/malformed resources never trigger paid calls in mock mode.

The five byte-exact originals are retained in ignored
`exports/hills-iphone-2026-10-05/{CourseData,GolfAPI}/` outside the app source root.
In particular `CourseData/terrain-gpxz-v1.json` is a **local-only private backup**:
schema 1, stable identity `golfapi:0121161534832877`, directory identity SHA256
`6916666b421f2b3d096d83384e1e00cf84b22653557eed017a4c22ed27ee091a`,
16 original responses / 3,509 exact samples. Returned provenance says
`gpxz_terrain_30m`, 30 m source resolution, dataset `2025.1`, EGM2008/bilinear,
capture dates 2014–2021. Roughly metre-spaced samples do **not** imply 1 m terrain.

**No real terrain is bundled or used by the app.** No source flags distinguish
clicked map targets from captured golfer origins. The conservative review requires
every original path vertex to coincide with public hole endpoints within the
existing 2 cm tolerance and the entire path to follow that hole segment. None of
the 16 records qualified. No private path/sample coordinates are promoted to public
resources, no records clipped, and no elevations fabricated/interpolated as real.
The ignored backup may be privately transferred for later authorized import, but
there is no new in-app importer. Existing GPXZ mock remains explicitly synthetic
in its separate namespace; it does not read/mix/overwrite this real backup or the
live sidecar, budget, history, locks or markers. Weather and imagery remain
live/cache-backed; only course selection/geometry is portable offline data.

The offline `tools/save_hills_export.mjs` packages only the five staged filenames,
checks identity/public geometry, strips account counters, filters Valley, records
checksums and refuses overwrites. **Internal development only**: retain Golf API
course/GPS credits and GPXZ/source provenance in the local backup. This export is
not a claim of redistribution rights or complete attribution compliance. Review
Golf API, GPXZ and underlying source licence terms before any public distribution;
full source credit/licence records have not been downloaded or bundled.

Regression source covers fresh empty provider caches, saved-before-demo ordering,
Hills-only metadata, read-only force refresh, original tee IDs/ratings/coordinates,
exact bundled geometry/fetched date and other tee reconstruction. Build validation
does not execute tests or launch the app; runtime UI/playback remains unverified.
Fresh generic simulator `build-for-testing` succeeded in
`/tmp/fairwayvector-bundled-hills.0E74uX`; regression source compiled for arm64 and
x86_64, never executed. The actual app contains all five reviewed resources,
verified against SHA256 digests; no private terrain, raw search, local config or
ledger resources. Both compiled modes are `mock` and both compiled keys blank.
Original backup checksums, diff whitespace and editor diagnostics passed. No
provider/network requests or app launch occurred; only the existing Xcode
supported-platform diagnostic appeared.

## Local evaluation configuration

For later explicitly enabled live evaluation, the tracked GPXZ configuration defaults to a blank key. Optionally create
`fairwayvector-pintheory/GPXZ.local.xcconfig` locally and set `GPXZ_API_KEY` there.
It is ignored by Git and excluded from resources. It is independent of the
Golf API key. Opening a course/hole/tee/saved flag reads terrain cache only,
without checking remote credentials. Blank or unresolved build placeholders
produce configuration guidance only on an explicit acquisition, with **zero
GPXZ HTTP requests**; cached terrain can still be used.
Do not paste credentials into chat, commit them, log them, or put them in URLs.

**A direct-client development key is extractable from the app bundle, even when
the local configuration is ignored. Production requires a backend proxy or
equivalent protected credential architecture. This migration does not implement
that backend or account-wide enforcement.** Review GPXZ and underlying data
source terms and credits before redistributing any cached data.

## Provider and validation

In explicitly enabled live mode, only GPXZ `POST /v1/elevation/sample` supplies runtime terrain worldwide.
Paths use WGS84 latitude/longitude vertices, retained in order, with
pipe-separated `latlons`, `samples` between 2 and 512, `interpolation: bilinear`,
`bathymetry: false`, and `x-api-key` in the header only. Maximum path size is
5,000 vertices. Requests use documented `application/x-www-form-urlencoded`
POST fields: `samples` is `String(count)`, a plain ASCII decimal integer,
`interpolation=bilinear`, and `bathymetry=false`. `URLQueryItem` constructs the
percent-encoded body in fixed field order; literal `+` and `|` are escaped
(`%2B`, `%7C`) so form decoding cannot turn coordinate text into spaces or
unescaped separators. For new uncovered spans up to 511 m the requested interval is
approximately 1 m; longer spans use at most 512 samples and honestly wider
spacing, not gratuitous batches. Each disconnected missing interval needs its
own request; bends within a connected missing interval are retained.

HTTP/status/count/finite coordinate, height and resolution/endpoints/order are
validated before saving anything. Raw error bodies and invalid profiles are never
persisted. Only the documented JSON `error` field may be shown, after bounded
decoding, key/URL redaction and rejection of header/credential-bearing detail.
Unknown error formats show HTTP status and an explicit missing-detail message;
transport errors never expose underlying URLSession URLs. Redirects are rejected.
There are no automatic retries, probes,
prefetch, auth checks, expiry downloads, or paid force-refresh operation.
`Retry-After` is persisted and respected by later explicit requests. Timeouts,
cancellations, server failures and other uncertain attempts remain counted.

Every validated returned point is preserved exactly with source name, source
resolution, capture dates, dataset version header, interpolation, fetched date,
and **EGM2008** height datum. Displayed sample interval and actual source
resolution are separate. Terrain alone does not imply guaranteed accuracy,
green-reading or plays-like advice. The profile and Settings link to GPXZ and its public
source/credit/licence catalogue. The sheet displays separate provenance for
origin→target and target→flag, including each path's returned source identifiers,
resolution, dates, version and sample interval. No real source-specific credit
records or full licence texts have been downloaded or bundled, and the links are
not a claim of complete attribution/licence compliance: review the catalogue
entries identified by the actual returned source names. Opening those links is an explicit user browser action, not a terrain
probe or prefetch.

## Durable course-scoped point and line cache

Course geometry and the versioned `terrain-gpxz-v1.json` sidecar live in
Application Support / CourseData / SHA256(stable provider course ID).
Identity is `golfapi:<courseID>` or `osm:<relationID>`; tee names, hole numbers
and changing course display names do not define the terrain cache.
Existing flat course caches are read and copied forward, with originals left
intact. Terrain is not cleared by course refresh, tee switching, or new GPS
fixes. The former Hills RH2000 raster packages are never migrated or loaded.

Each immutable response retains its original polyline, all exact provider
points, original sample chainages and provenance history. Covered intervals are
derived from those original segments using a local geographic numeric
projection and a 2 cm collinearity tolerance—not GPS-sized snapping, nearby
points, or sample chords across bends. Reverse/subsection/partial overlap reuse
works across holes and tees in the same provider course. For example, saved
0–200 m covers 0–150 m and 50–150 m without HTTP; 0–300 m requests only the
uncovered 200–300 m extension (the shared boundary can occur in both responses).
Disconnected points never create line coverage. Exact shared point heights can
anchor other paths. A zero-length path returns a known cached height with zero
delta; otherwise it remains unavailable, with no invented height or API call.

Extracted subpath boundaries and bends are interpolated along **original
provider chainage**, retaining both bracketing provenances and identifying local
interpolation. Missing coverage remains explicit chart gaps. No expiry refresh
or fallback raster/weather/phone altitude is used. A serial acquisition queue
covers read/plan/reserve/send/save through HTTP suspension, so overlapping
pending requests replan after the earlier atomic save. Valid responses are saved
even if the user has moved on; generations suppress obsolete UI publication.
Validated responses are retained immediately in repository-owned pending memory
before any disk write. A full response/cache snapshot is atomically written to a
separate pending journal before replacing the course sidecar. Subsequent explicit
requests first perform storage-only recovery from pending memory or the journal;
no new paid calls are permitted until the snapshot is saved and journal cleanup
succeeds. Outstanding in-memory writes also block requests for other courses
until storage-only recovery succeeds. Restart journal recovery is idempotent
(no duplicate append/refetch).
Corrupt cache or ledger fails closed instead of triggering paid redownload.
Preserve damaged files for recovery. **If storage is totally unavailable, even the
journal cannot be saved: received points survive only in the running repository's
memory, not a process termination.** No implementation can guarantee durable
persistence without writable storage; resolve storage before leaving the app.

## Local monthly safety budget

Application Support / GPXZ / monthly-ledger-v1.json records reservations
**before each outgoing paid attempt**. The limit is 100 attempts per UTC calendar
month, shared by every course and map store on this installation. Atomic writes
must succeed before dispatch. First initialization atomically saves the ledger,
then records initialization in an independent sibling marker and a UserDefaults
marker keyed by SHA256 of the standardized ledger path, before any request.
An existing validated ledger is safely bootstrapped with these markers. A missing
ledger with either marker present fails closed rather than resetting to zero;
marker/persistence failures also prevent dispatch. Old months are retained and
never silently reset on decoding errors. Exhaustion allows saved terrain only; partial cached
profiles stay visible when later gaps cannot be filled. Used/remaining counts
and uncovered-span counts are shown in the profile panel.

The same ledger also stores SHA256 fingerprints of the **actual HTTP body**
and sanitized failure reasons, never request bodies or credentials. Fixed field
order makes the corrected form body's digest deterministic. Historical invalid
JSON digests remain recorded but do not block the different corrected form body.
An identical failed HTTP/transport/validation request is blocked **before another
reservation**, including after reopening a hole, repeating a target commit or
restarting the app. Cached coverage remains usable. Failure locks do not expire
at a month boundary. **Retry terrain requires confirmation** and clears failure
locks only, after already-sent requests finish, archiving their digests/reasons
as failure history; it never refunds/resets used calls,
clears initialization markers, bypasses `Retry-After`, or overwrites saved terrain.
Correct the reported cause before confirming; a genuinely changed request can
still require a new paid attempt. Failure-lock persistence errors fail closed.

This is a **local safety limit**, not cross-device/provider billing authority.
Other devices/tools, reinstall, backup restoration, deletion of the ledger **and
both independent initialization markers**, or another application process can
bypass it. Deleting only the ledger cannot reset an initialized allowance.
Use the provider dashboard and a production
proxy for account-wide control. UTC month boundaries may differ from provider
billing; adjust the ledger policy only after confirming your actual cycle.

## Interaction and privacy

Opening a course, hole, tee, or saved flag is **cache-only**, including the
initial origin→flag/shot chain. There is **no automatic paid hole request**, on
opening, first map tap, or release of a previously paused interaction. Cache-only
permits cannot dispatch; the repository returns saved partial coverage before
request building, credential checks, failure-lock checks, ledger initialization
or reservations. An existing ledger's used count is read without writing it;
opening does not create/repair/reset a ledger. An old HTTP 400 UI status is cleared
on opening, while its ledger failure history remains intact. Without saved
coverage, the panel invites a map tap rather than immediately reporting a
missing key or repeating a previous HTTP 400.

The hole chart in terrain details reads cached coverage only and may remain partial
even after shot acquisition. Distinct holes are never concatenated. The full
chart stays available in the sheet while a target is dragged. Target taps commit at
release; genuine target drags update draft marker/distance on change and commit
once on end. Ordinary pan/zoom/heading and incoming GPS fixes do not request
terrain. Target interaction closes a shared thread-safe dispatch gate and
invalidates **both** hole and shot permits. The displayed hole and its pending
loading state are retained; stale shot values are invalidated and marked pending.
Already-sent responses still finish validation/persistence, even during a drag.
No subsequent gap or queued path can pass the interaction gate while dragging.
The final task creation/resume is performed under the same lock as closing the
gate, not merely checked before an asynchronous executor hop. An already-sent
request can still transfer/finish during interaction; it is not cancelled or refunded.
Release/commit reopens it for **clicked shot legs only**. The hole chart may reread
the latest cache but never spends on unrelated whole-hole gaps. Hole generations
stay independent: a cache read cannot restore the original shot after a newer
user shot. Provider, budget and storage failures do not qualify for automatic
release retries. A commit
captures the latest GPS/tee fallback origin; its profile labels retain that
snapshot rather than adopting later fixes. Refresh is explicit, cache-first,
and captures the latest origin; it does not force a paid overwrite of saved data.
There is no initial paid hole/shot chain. A failed paid origin→target load
suppresses the target→flag follow-up; cache-only chains can read both legs even
when the first is missing. The current-shot mode is selected immediately on a
target commit. Paid paths are only origin→clicked target and clicked target→flag
when distinct, each independently cache-first and budgeted; only uncovered
intervals are acquired. Explicit confirmed Retry/Refresh can acquire these shot
legs using the latest origin (flag is the target if none was selected), never
the unrelated whole hole. Hole/current-shot modes share the existing gap-aware
chart renderer in details; the map shows only a compact delta row. Sheet
inspection only updates the map inspection mark.

### HTTP 400 diagnosis (documentation checked 2026-10-05)

The user reported GPXZ's exact reason: **“Samples argument should be a positive
integer.”**, with **5 previous local calls** to retain. The
[GPXZ points/sample reference](https://www.gpxz.io/docs/api-reference-points)
explicitly supports `/sample` POST using the same form or JSON encoding as
`/points`. The previous typed JSON integer was correct in source; this evidence
supports a **wire/server interoperability correction**, not a proven Swift
JSON library boolean/integer bug. The client now uses the documented form POST
with an explicit decimal `samples` string. The valid 2…512 bounds, coordinate
order, path normalization, and exact returned-result validation are unchanged;
no speculative lower cap was introduced.

All existing cached points/responses, old failure fingerprints/reasons and the
ledger's historical counts remain intact. This change neither resets nor refunds
the reported 5 calls. Offline regression **source** checks the form body,
percent encoding, count boundaries, both clicked legs, cache-only opens, and old
JSON locks with a five-call fixture. The fixture does not read or modify the real
user ledger. Tests have not been executed. No provider response, live request,
account usage, app launch or secrets were inspected. Compilation alone cannot
establish that the provider will accept the corrected wire format.

Runtime GPXZ sampling sends course/shot coordinates, potentially the golfer's
captured GPS location, to GPXZ. Weather (Open-Meteo), course providers and Apple
Maps remain independent and unchanged. This README/UI disclosure is not a
substitute for reviewing the release privacy policy and App Store declarations.

## On-course club recommendation

After releasing a selected map target, a compact card above the terrain panel
shows the best modeled full-swing club and up to two closest alternatives, with
predicted carry and signed short/long error against the horizontal origin→target
distance. Tap for alternatives, existing Trajectory results/physics charts with
target markers, captured conditions and endpoint terrain provenance. GPS is used
when the existing on-hole origin resolver permits it; otherwise details explicitly
label the tee fallback. No recommendation is shown for an unselected flag alone.

Practice and Course share `ClubRecommendationEngine`: the same effective club
launch profiles, Physics V1.1 integration, bundled HGB residual models, and absolute
corrected-carry-error ranking. Evaluation uses immutable launch snapshots on a
background actor and never prepares/selects a club or writes Practice conditions,
results, units or profile state. Missing model outputs do not fall back to stock
yardages. Setup and a nonempty bag are required. Simple mode explicitly labels its
handicap-based defaults; Medium/Advanced without any applicable calibration anchor
offer the existing Practice/Profile configuration sheet instead of predictions.

Complete captured course temperature, relative humidity, **surface** pressure and
wind plus matching finite origin/target terrain endpoints are required. No flat,
calm, sea-level-pressure or phone-altitude fallback is invented. Weather wind is
already m/s; meteorological FROM direction is rotated relative to the true shot
bearing: tailwind = −speed·cos(FROM−bearing), right-crosswind = −speed·sin(FROM−bearing).
Weather wind is displayed in m/s (any km/h conversion in shot details is display-only). Pressure remains hPa; the existing
atmosphere routine converts it to Pa exactly once. Absolute GPXZ heights are shown
as provenance; target-minus-origin height alone sets the landing plane. Direct
surface pressure is **not** compensated again for terrain altitude.

The shared top-down physics chart is viewed from the golfer toward the target:
forward is up, positive lateral (physical right) is screen-right, and the target
is at zero lateral/selected downrange. Previously it plotted downrange horizontally
and lateral vertically (positive right upward), a different viewpoint from the map.
Course details now show a blowing-TO arrow from the **captured** tail/right wind
components in these same chart axes, true shot/right cardinal bearings, and the
selected club's modeled spin axis. The map arrow still correctly converts FROM
to TO and subtracts the actual camera heading, initially tee→green; that heading
can differ from the captured origin→target bearing. Physics, FROM conversion,
Practice wind controls and recommendation ranking are unchanged. Spin-induced
curvature can oppose wind; no claim is made that it caused the reported shot.
New offline regression source covers northward shots with east/west FROM wind,
shared-engine wind signs, zero-spin physical lateral signs, top-down coordinates,
target placement and arrow rotations. This fix is validated with an **app-only**
build; these new tests are neither compiled nor executed in that validation.

Dragging clears obsolete recommendations; only committed targets are evaluated.
Weather/profile changes recompute locally, with cancellation, captured-input
identity and publication guards. Incoming GPS fixes do **not** recommit shots,
read terrain cache, or invalidate captured-origin advice or an ongoing acquisition.
The card explicitly describes advice at the committed GPS/tee fallback position,
not live GPS. Releasing a target or confirming Refresh terrain captures the latest
origin using the existing cache-first acquisition/permission flow. Practice also
invalidates pending results on Reset, target/condition edits and profile/bag changes;
only the matching request generation and complete captured input may publish or
finish its calculating state. The recommender contains no GPXZ, Golf API or weather
requests and does not trigger weather refresh. Existing weather refresh/cache
behavior is unchanged; a read-only weather-location association guard prevents
old-location weather from being relabelled during a geometry change. Details always identify the provider observation time,
which can be cached; forecast surface pressure and 10 m wind are course-level,
not measurements at the golfer. Gusts and altitude-based pressure relocation are
not modeled.

Carry includes the existing ML correction; charts and lateral/downrange outcomes
remain uncorrected physics paths and are labelled accordingly. Ranking is closest
carry (the existing horizontal landing distance including lateral drift, not
downrange alone), not a guaranteed target hit or crosswind-optimized aim. The landing surface
is a horizontal plane at the target elevation, not the intervening terrain profile:
obstacles, hazards, roll, partial swings, GPS error and shot dispersion are not
simulated. Short/unreachable physics flights are disclosed in details. Offline
regression source covers wind rotation, pressure/height separation, missing inputs,
stale endpoint rejection, shared-engine equivalence and Practice-state preservation;
it is compiled only, **not executed**.

## Legacy work and validation policy

The offline Hills preparer, its requirements, acquisition status and preparation
document are explicitly archived and preserved. The acquisition-status resource
and all xcconfig files are excluded from the app's resource membership. No active
TerrainGrid raster engine remains.

This implementation is validated by compilation and `git diff --check` only.
No app launch, test execution, network/API call or credential inspection is
authorized for this migration. Offline mock/planner/ledger acceptance test source
is included for later separately authorized execution; successful compilation
does not establish live provider behavior or licence compliance.
