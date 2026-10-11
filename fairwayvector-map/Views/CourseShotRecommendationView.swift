import SwiftUI

/// No acquisition in this view. It reads committed terrain and the existing weather store.
struct CourseShotRecommendationView: View {
    let terrainStore: TerrainElevationStore
    let weatherStore: CourseWeatherStore
    let weatherLocation: GeoPoint?
    let selectedTarget: GeoPoint?
    let unit: DistanceUnit
    @ObservedObject var model: TrajectoryCalculatorViewModel
    var compact = false
    @State private var engine = ClubRecommendationEngine()
    @State private var scoringEngine = ScoringRecommendationEngine()
    @AppStorage("wedgeMatrix.wedges") private var storedWedges = ""
    @State private var result: CourseShotRecommendationResult?
    @State private var failedInput: CourseShotRecommendationInput?
    @State private var errorMessage: String?
    @State private var isShowingDetails = false
    @State private var isShowingProfile = false
    @State private var isShowingWedges = false

    private var wedges: [Wedge] {
        guard let data = storedWedges.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Wedge].self, from: data) else { return [] }
        return decoded // Never substitute Wedge.defaults as personal calibration.
    }

    private var scoringPlan: ScoringShotPlan {
        ScoringShotPlan.make(profile: model.playerProfileStore.profile, wedges: wedges)
    }

    private var capturedWeather: CourseWeather? {
        guard let weatherLocation else { return nil }
        return weatherStore.weather(for: weatherLocation)
    }

    private var input: CourseShotRecommendationInput? {
        guard !terrainStore.shotPending else { return nil }
        return .capture(request: terrainStore.committedRequest, selectedTarget: selectedTarget,
                        weather: capturedWeather, weatherLocation: weatherStore.weatherLocation,
                        shotProfile: terrainStore.snapshot.shotProfile, profile: model.playerProfileStore.profile, wedges: wedges)
    }

    private var currentResult: CourseShotRecommendationResult? {
        guard let input, result?.input == input else { return nil }
        return result
    }

    private var compactAccessibilityValue: String {
        guard let choice = currentResult?.recommendations.first else { return compactStatus }
        return "\(choice.title), \(unit.format(choice.recommendation.estimatedCarryM)) carry"
    }

    var body: some View {
        Button { isShowingDetails = true } label: {
            Group {
                if compact {
                    compactSummary
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("YOUR NEXT SHOT")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(PureLineStyle.muted)
                    Spacer(minLength: 0)
                    if currentResult?.input.isScoring == true {
                        Text("Scoring")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(PureLineStyle.accent)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(PureLineStyle.surface, in: Capsule())
                    }
                }
                if let currentResult, let best = currentResult.recommendations.first {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(best.title)
                                .font(.title2.weight(.semibold)).tracking(-0.5)
                                .foregroundStyle(PureLineStyle.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            recommendationRow(best, target: currentResult.input.distanceM)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.body.weight(.medium)).foregroundStyle(PureLineStyle.accent)
                    }
                    let alternatives = currentResult.recommendations.dropFirst().prefix(2).map {
                        "\($0.title) \(CourseShotRecommendationDetail.errorText($0.recommendation, target: currentResult.input.distanceM, unit: unit))"
                    }
                    if !alternatives.isEmpty {
                        Text(alternatives.joined(separator: "  /  "))
                            .font(.caption)
                            .foregroundStyle(PureLineStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Nearest alternatives: " + alternatives.joined(separator: ", "))
                    }
                } else {
                    HStack(spacing: 12) {
                        Text(compactStatus)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if input != nil, failedInput != input { ProgressView().controlSize(.mini) }
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(PureLineStyle.accent)
                    }
                }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(PureLineStyle.ink)
        .padding(.horizontal, compact ? 0 : 24)
        .padding(.top, compact ? 0 : 20)
        .padding(.bottom, compact ? 0 : 16)
        .background(PureLineStyle.canvas.opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("course-club-recommendation")
        .accessibilityHint("Opens trajectory, captured conditions, alternatives, errors and club calibration, even before advice is available")
        .task(id: input) {
            result = nil
            failedInput = nil
            errorMessage = nil
            guard let captured = input else { return }
            do {
                // Coalesce committed-target/weather/profile changes, never live GPS.
                try await Task.sleep(for: .milliseconds(200))
                let recommendations: [CourseClubRecommendation]
                let unavailable: [UnavailableScoringShot]
                if captured.isScoring {
                    // Weather shot supplies only captured conditions; its club launch
                    // is NOT reused as the scoring launch or written to Practice.
                    let conditions = ShotInputs(ballSpeedMps: 1, launchAngleDeg: 1,
                        launchDirectionDeg: 0, spinRateRpm: 0, spinAxisDeg: 0,
                        temperatureC: captured.conditions.temperatureC,
                        pressureHpa: try captured.conditions.effectivePressureHpa(),
                        relativeHumidityPct: captured.conditions.humidityPct,
                        windXMps: captured.conditions.tailwindMps, windYMps: captured.conditions.crosswindMps,
                        targetElevationDeltaM: captured.conditions.elevationDeltaM)
                    let evaluation = try await scoringEngine.recommend(targetM: captured.distanceM,
                        specs: captured.scoringPlan.shots, conditions: conditions)
                    recommendations = evaluation.recommendations
                    unavailable = evaluation.unavailable
                } else {
                    unavailable = []
                    let launches = try ClubRecommendationEngine.launches(profile: captured.profile, conditions: captured.conditions)
                    recommendations = try await engine.recommend(for: captured.distanceM, launches: launches).map {
                        CourseClubRecommendation(id: $0.club.rawValue, title: $0.club.label,
                            recommendation: $0, scoringShot: nil, calibratedLaunch: nil)
                    }
                }
                try Task.checkCancellation()
                guard input == captured else { return }
                if recommendations.isEmpty {
                    failedInput = captured
                    errorMessage = captured.isScoring
                        ? "No scoring combination is available at this elevation/calibration. Review details; full-bag advice is not substituted inside scoring range."
                        : "No club prediction is available. Default club profiles are used until your bag is configured."
                }
                result = CourseShotRecommendationResult(input: captured, recommendations: recommendations,
                    unavailableScoringShots: unavailable)
            } catch is CancellationError {
                // A newer target or conditions own publication.
            } catch {
                guard !Task.isCancelled, input == captured else { return }
                failedInput = captured
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isShowingDetails) {
            recommendationDetails
                .sheet(isPresented: $isShowingWedges) { wedgeSetup }
                .sheet(isPresented: $isShowingProfile) { profileSetup }
        }
    }

    private var compactSummary: some View {
        VStack(spacing: 3) {
            Image(systemName: "scope")
                .font(.body.weight(.medium))
                .foregroundStyle(PureLineStyle.accent)
            if let currentResult, let best = currentResult.recommendations.first {
                Text(best.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(PureLineStyle.ink)
                Text(unit.format(best.recommendation.estimatedCarryM))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(PureLineStyle.muted)
            } else {
                Text(compactStatus)
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PureLineStyle.ink)
                if input != nil, failedInput != input {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .padding(6)
        .frame(width: 78)
        .frame(minHeight: 64)
        .background(PureLineStyle.canvas.opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your next shot")
        .accessibilityValue(compactAccessibilityValue)
        .accessibilityHint("Opens the full shot recommendation, conditions and flight details")
    }

    @ViewBuilder private var recommendationDetails: some View {
            if let currentResult {
                CourseShotRecommendationDetail(result: currentResult, unit: unit,
                    unitPreferences: model.unitPreferences,
                    onConfigureWedges: { isShowingWedges = true }, onConfigureProfile: { isShowingProfile = true })
            } else {
                NavigationStack {
                    Form {
                        Section("Recommendation status") {
                            Text(status)
                            if let message = errorMessage { Text(message) }
                            if let message = terrainStore.shotMessage { Text(message) }
                            if let message = weatherStore.errorMessage { Text("Weather: \(message)") }
                            Text("Advice requires a selected target, complete course-associated weather and matching committed terrain endpoints. Unconfigured or incomplete profiles use Simple club defaults; the map never assumes calm wind or flat ground. Tap weather or terrain on the map for full provider status and manual retry.")
                        }
                        Section("Clubs & calibration") {
                            calibrationButtons
                            if !scoringPlan.guidance.isEmpty { Text(scoringPlan.guidance) }
                        }
                    }
                        .navigationTitle("Shot recommendation")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingDetails = false } } }
                }
            }
    }

    private var calibrationButtons: some View {
        Group {
            Button("Wedge calibration & matrix") { isShowingWedges = true }
            Button("Configure Practice / Profile") { isShowingProfile = true }
        }
    }

    private var wedgeSetup: some View {
            NavigationStack {
                WedgeMatrixView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingWedges = false } } }
            }
    }

    @ViewBuilder private var profileSetup: some View {
            if model.playerProfileStore.needsSetup {
                TrajectoryProfileSetupWizardView(profileStore: model.playerProfileStore,
                    unitPreferences: model.unitPreferences, onClose: { isShowingProfile = false })
            } else {
                NavigationStack {
                    TrajectoryProfileSettingsView(profileStore: model.playerProfileStore, unitPreferences: model.unitPreferences,
                                                  settingsViewModel: model)
                        .navigationTitle("Clubs & launch profile")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingProfile = false } } }
                }
            }
    }

    private var compactStatus: String {
        if selectedTarget == nil { return "Tap map to select target" }
        if terrainStore.shotPending { return "Release target to calculate" }
        if capturedWeather.map({ CourseShotRecommendationInput.valid($0) }) != true { return "Weather unavailable · tap for details" }
        if input == nil { return terrainStore.isShotLoading ? "Loading terrain…" : "Terrain unavailable" }
        if failedInput == input { return "Advice unavailable · tap for details" }
        return "Comparing shots…"
    }

    private var status: String {
        if selectedTarget == nil { return "Release a point on the map to choose a shot target." }
        if terrainStore.shotPending { return "Target moving · release to calculate." }
        if capturedWeather.map({ CourseShotRecommendationInput.valid($0) }) != true {
            return "Waiting for complete course weather: temperature, surface pressure, humidity and wind. No flat/calm fallback."
        }
        if input == nil {
            return terrainStore.isShotLoading ? "Waiting for matching origin/target terrain…"
                : "Matching origin/target terrain unavailable. Release the target or confirm Retry terrain; no flat-ground assumption."
        }
        if failedInput == input { return errorMessage ?? "Club predictions unavailable." }
        return input?.isScoring == true ? "Comparing Low/Mid/High × 50/75/100% for your calibrated wedges…"
            : "Calculating with your Practice bag, captured weather and terrain…"
    }

    private func recommendationRow(_ choice: CourseClubRecommendation, target: Double) -> some View {
        let recommendation = choice.recommendation
        return Text("\(unit.format(recommendation.estimatedCarryM)) carry · \(CourseShotRecommendationDetail.errorText(recommendation, target: target, unit: unit))")
            .font(.caption).foregroundStyle(PureLineStyle.muted)
    }
}

private struct CourseShotRecommendationDetail: View {
    let result: CourseShotRecommendationResult
    let unit: DistanceUnit
    @ObservedObject var unitPreferences: UnitPreferences
    let onConfigureWedges: () -> Void
    let onConfigureProfile: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?

    private var input: CourseShotRecommendationInput { result.input }
    private var selected: CourseClubRecommendation? {
        result.recommendations.first { $0.id == selectedID } ?? result.recommendations.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button("Wedge calibration & matrix", action: onConfigureWedges)
                        Spacer(minLength: 0)
                        Button("Practice / Profile", action: onConfigureProfile)
                    }
                    .font(.subheadline)
                    Text("\(unit.format(input.distanceM)) horizontal target · \(input.request.originLabel)")
                        .font(.headline)
                    Text("Advice uses the committed origin, not your live GPS position. Release a map target or confirm Refresh terrain to capture a new origin.")
                        .font(.caption).foregroundStyle(.secondary)
                    if input.isScoring, let range = input.scoringPlan.maxFullCarryM {
                        Label("Scoring mode · ≤ \(unit.format(range)) personal full wedge range", systemImage: "scope").font(.headline)
                        Text("Inclusive horizontal-distance threshold, unchanged by weather. \(input.request.isSimulatedOrigin ? "Simulated origin, not device GPS or a claim of golfer proximity." : input.request.usesGPS ? "Captured GPS origin." : "Tee-fallback preview allowed for testing, not a claim of golfer proximity.")")
                            .font(.caption)
                    }
                    if !input.scoringPlan.guidance.isEmpty { Text(input.scoringPlan.guidance).font(.caption) }
                    Text(input.isScoring
                        ? "Ranked by absolute corrected carry error: nine Low/Mid/High × 50/75/100% shots per calibrated wedge, using Physics V1.1 + HGB with captured weather and elevation. Full means 100% stock full carry, not maximum effort. 50/75% are swing-length labels, not carry or ball-speed percentages."
                        : "Ranked by absolute corrected carry error, using the same full-swing club profiles and Physics V1.1 + HGB residual models as Practice. Not roll, a guaranteed hit, or obstacle clearance.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Corrected carry is horizontal landing distance (including lateral drift), not downrange alone. A closest-carry ranking can still miss the point sideways.")
                        .font(.caption).foregroundStyle(.secondary)
                    if input.profile.detailLevel == .easy {
                        Text("Simple profile: launch values are handicap-based defaults, not measured club calibration.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Profile: \(input.profile.detailLevel.label). Unentered fields use Practice’s existing calibrated/interpolated defaults.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("All ranked combinations (\(result.recommendations.count))").font(.headline)
                    if !result.unavailableScoringShots.isEmpty {
                        Text("\(result.unavailableScoringShots.count) of \(input.scoringPlan.shots.count) combinations are unavailable; each reason is listed below. They are not silently replaced by stock yardages or full-bag clubs.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVStack(spacing: 8) {
                    ForEach(Array(result.recommendations.enumerated()), id: \.element.id) { index, choice in
                        let recommendation = choice.recommendation
                        Button { selectedID = choice.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(index + 1). \(choice.title)").bold()
                                    Text("\(unit.format(recommendation.estimatedCarryM)) carry · \(Self.errorText(recommendation, target: input.distanceM, unit: unit))")
                                }
                                Spacer(minLength: 0)
                                Image(systemName: selected?.id == choice.id ? "checkmark.circle.fill" : "circle")
                            }
                            .font(.subheadline).padding(12)
                            .background(FairwayVectorColors.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    }
                    if !result.unavailableScoringShots.isEmpty {
                        DisclosureGroup("Unavailable combinations (\(result.unavailableScoringShots.count))") {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(result.unavailableScoringShots) { unavailable in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(unavailable.spec.title).bold()
                                        Text(unavailable.reason)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                    if let choice = selected {
                        let selected = choice.recommendation
                        Text(choice.title).font(.title2.bold())
                        if let spec = choice.scoringShot, let shot = choice.calibratedLaunch {
                            Text(spec.source).font(.caption).foregroundStyle(.secondary)
                            Text("Reference carry \(unit.format(spec.nominalCarryM)); speed inversely fitted to calm/level 20°C, 1013.25 hPa, 50% RH hybrid carry (≤0.5 m numerical fit, NOT real-world accuracy). Launch shape/spin assumptions are not validated partial-shot measurements; HGB training coverage is not guaranteed.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "Fitted speed %.1f m/s · assumed launch %.1f° · retained spin %.0f rpm", shot.ballSpeedMps, shot.launchAngleDeg, shot.spinRateRpm))
                                .font(.caption)
                        }
                        outcome(selected)
                        TrajectoryResultsView(prediction: selected.prediction, unitPreferences: unitPreferences)
                        let launch = ClubProfileDefaults.effectiveProfile(for: selected.club, playerProfile: input.profile)
                        Text(String(format: "Modeled spin axis: %+.1f° (+ curves right, − curves left). Wind and spin both contribute to the path.", choice.calibratedLaunch?.spinAxisDeg ?? launch.spinAxisDeg.value))
                            .font(.caption).foregroundStyle(.secondary)
                        TrajectoryChartView(trajectory: selected.trajectory, unitPreferences: unitPreferences,
                                            targetDistanceM: input.distanceM, targetElevationM: input.conditions.elevationDeltaM,
                                            capturedWind: (tail: input.conditions.tailwindMps, right: input.conditions.crosswindMps),
                                            shotBearingDeg: input.bearingDeg)
                    }
                    conditions
                }
                .padding()
            }
            .background(FairwayVectorColors.background)
            .foregroundStyle(FairwayVectorColors.navy)
            .navigationTitle("Shot recommendation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(FairwayVectorColors.navy)
    }

    private func outcome(_ recommendation: ClubRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let downrange = recommendation.trajectory.xM.last ?? 0
            let lateral = recommendation.trajectory.yM.last ?? 0
            Text("Physics landing: \(unit.format(downrange)) downrange; \(unit.format(abs(lateral))) \(lateral >= 0 ? "right" : "left") of target line.")
            if let height = recommendation.heightAtTargetDistanceM {
                Text("Physics height at target distance: \(height.formatted(.number.precision(.fractionLength(1)))) m above origin (target: \(input.conditions.elevationDeltaM.formatted(.number.precision(.fractionLength(1)))) m).")
            } else {
                Label("Physics flight ends before the target distance, even if corrected carry is closer.", systemImage: "exclamationmark.triangle")
            }
            if recommendation.estimatedCarryM < input.distanceM {
                Text("This club’s corrected carry estimate is short of the target.")
            }
            Text("The model lands on a horizontal plane at the target elevation; intermediate terrain, trees, hazards and roll are not simulated. Crosswind/spin drift is shown, not compensated by an optimized aim.")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Captured conditions & sources").font(.headline)
            LabeledContent("Shot bearing (true)", value: String(format: "%.1f°", input.bearingDeg))
            LabeledContent("Temperature / humidity", value: String(format: "%.1f °C / %.0f%%", input.conditions.temperatureC, input.conditions.humidityPct))
            LabeledContent("Surface pressure", value: String(format: "%.1f hPa", input.conditions.pressureHpa))
            LabeledContent("Wind (meteorological FROM)", value: String(format: "%.1f m/s (%.1f km/h) from %.0f°", input.weather.windSpeedMps!, input.weather.windSpeedMps! * 3.6, input.weather.windDirectionDegrees!))
            LabeledContent(input.conditions.tailwindMps >= 0 ? "Tailwind" : "Headwind", value: String(format: "%.1f m/s", abs(input.conditions.tailwindMps)))
            LabeledContent("Crosswind toward \(input.conditions.crosswindMps >= 0 ? "right" : "left")", value: String(format: "%.1f m/s", abs(input.conditions.crosswindMps)))
            LabeledContent("Terrain origin / target", value: String(format: "%.1f / %.1f m", input.originSample.elevationMeters!, input.targetSample.elevationMeters!))
            LabeledContent("Target minus origin", value: String(format: "%+.1f m", input.conditions.elevationDeltaM))
            Text("Open-Meteo course weather snapshot: \(input.weather.observedAt) (\(input.weather.timezone ?? "provider local time")). This may be cached; course-level surface pressure and 10 m wind are used unchanged, not measured at the ball. Absolute terrain height is provenance only: pressure is supplied directly, not altitude-compensated again. Gusts are not used.")
            Text(String(format: "Weather location: %.5f, %.5f · origin: %.5f, %.5f · target: %.5f, %.5f", input.weatherLocation.lat, input.weatherLocation.lon, input.originSample.point.lat, input.originSample.point.lon, input.targetSample.point.lat, input.targetSample.point.lon))
            ForEach(Array(Set(input.originSample.provenance + input.targetSample.provenance)).sorted { $0.dataSource < $1.dataSource }, id: \.self) { record in
                if !record.isSynthetic {
                    Text("GPXZ · \(record.dataSource) · source resolution \(record.resolutionMeters.formatted()) m · captured \(record.captureDateMin ?? "unknown")–\(record.captureDateMax ?? "unknown") · dataset \(record.datasetVersion ?? "unknown") · saved \(record.fetchedAt.formatted())")
                }
            }
            if input.originSample.locallyInterpolated || input.targetSample.locallyInterpolated {
                Text("Endpoint heights include local interpolation along saved provider coverage.")
            }
            Text("Terrain source spacing is not accuracy. GPS error, forecast age, source resolution and your launch-profile quality affect these estimates. Practice inputs and selected club have not been changed.")
        }
        .font(.caption).padding()
        .background(FairwayVectorColors.conditionsSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    static func errorText(_ recommendation: ClubRecommendation, target: Double, unit: DistanceUnit) -> String {
        let error = recommendation.estimatedCarryM - target
        if abs(error) < 0.05 { return "on target (estimate)" }
        let value = unit == .meters ? abs(error) : abs(error) / 0.9144
        return String(format: "%.1f %@ %@", value, unit.symbol, error < 0 ? "short" : "long")
    }
}