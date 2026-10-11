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
        .accessibilityHint("Opens the suggested club and modeled flight details")
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
        .accessibilityHint("Opens the suggested club and flight details")
    }

    @ViewBuilder private var recommendationDetails: some View {
            if let currentResult {
                CourseShotRecommendationDetail(result: currentResult, unit: unit,
                    unitPreferences: model.unitPreferences)
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Recommendation status", systemImage: "scope")
                                    .font(.headline)
                                    .foregroundStyle(PureLineStyle.ink)
                            Text(status)
                                .font(.subheadline)
                                .foregroundStyle(PureLineStyle.muted)
                                if let message = errorMessage { Text(message).font(.footnote).foregroundStyle(.red) }
                                if let message = terrainStore.shotMessage { Text(message).font(.footnote).foregroundStyle(PureLineStyle.muted) }
                                if let message = weatherStore.errorMessage { Text("Weather: \(message)").font(.footnote).foregroundStyle(PureLineStyle.muted) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pureLineCard()
                        }
                        .padding(18)
                    }
                    .background(PureLineStyle.canvas)
                    .navigationTitle("Shot recommendation")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingDetails = false } } }
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
    @Environment(\.dismiss) private var dismiss

    private var input: CourseShotRecommendationInput { result.input }
    private var suggested: CourseClubRecommendation? { result.recommendations.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let choice = suggested {
                        let recommendation = choice.recommendation
                        suggestionCard(choice)
                        if input.isScoring, let range = input.scoringPlan.maxFullCarryM {
                            Label("Scoring range · ≤ \(unit.format(range))", systemImage: "scope")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PureLineStyle.accent)
                        }
                        if let spec = choice.scoringShot, let shot = choice.calibratedLaunch {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Shot estimate")
                                    .font(.headline)
                                    .foregroundStyle(PureLineStyle.ink)
                                Text("\(spec.title) · reference carry \(unit.format(spec.nominalCarryM))")
                                    .font(.subheadline)
                                    .foregroundStyle(PureLineStyle.muted)
                                Text(String(format: "Fitted speed %.1f m/s · assumed launch %.1f°", shot.ballSpeedMps, shot.launchAngleDeg))
                                    .font(.caption)
                                    .foregroundStyle(PureLineStyle.muted)
                            }
                            .pureLineCard()
                        }
                        TrajectoryResultsView(prediction: recommendation.prediction, unitPreferences: unitPreferences,
                                              showsEstimationInfo: false)
                        TrajectoryChartView(trajectory: recommendation.trajectory, unitPreferences: unitPreferences,
                                            targetDistanceM: input.distanceM, targetElevationM: input.conditions.elevationDeltaM,
                                            capturedWind: (tail: input.conditions.tailwindMps, right: input.conditions.crosswindMps),
                                            shotBearingDeg: input.bearingDeg)
                    } else {
                        ContentUnavailableView("No recommendation", systemImage: "figure.golf",
                                               description: Text(input.scoringPlan.guidance.isEmpty ? "No club recommendation is available for this shot." : input.scoringPlan.guidance))
                            .foregroundStyle(PureLineStyle.muted)
                    }
                }
                .padding(18)
            }
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .navigationTitle("Shot recommendation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(PureLineStyle.accent)
    }

    private func suggestionCard(_ choice: CourseClubRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested club")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PureLineStyle.muted)
            Text(choice.title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(PureLineStyle.ink)
            Text("\(unit.format(choice.recommendation.estimatedCarryM)) carry · \(Self.errorText(choice.recommendation, target: input.distanceM, unit: unit))")
                .font(.headline)
                .foregroundStyle(PureLineStyle.accent)
            Text("Target: \(unit.format(input.distanceM)) · \(input.request.originLabel)")
                .font(.caption)
                .foregroundStyle(PureLineStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
    }

    static func errorText(_ recommendation: ClubRecommendation, target: Double, unit: DistanceUnit) -> String {
        let error = recommendation.estimatedCarryM - target
        if abs(error) < 0.05 { return "on target (estimate)" }
        let value = unit == .meters ? abs(error) : abs(error) / 0.9144
        return String(format: "%.1f %@ %@", value, unit.symbol, error < 0 ? "short" : "long")
    }
}