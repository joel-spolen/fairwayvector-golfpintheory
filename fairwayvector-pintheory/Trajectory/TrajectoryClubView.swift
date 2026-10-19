import Combine
import SwiftUI
import Charts
import UIKit

@MainActor
private final class ClubConditionsStore: ObservableObject {
    @Published var temperatureC = 20.0
    @Published var pressureInputMode: PressureInputMode = .elevation {
        didSet {
            if pressureInputMode == .elevation {
                syncPressureFromElevation()
            }
        }
    }
    @Published var pressureHpa = 1013.25 {
        didSet { syncElevationFromPressure() }
    }
    @Published var siteElevationM = 0.0 {
        didSet { syncPressureFromElevation() }
    }
    @Published var humidityPct = 50.0
    @Published var tailwindMps = 0.0
    @Published var crosswindMps = 0.0
    @Published var elevationDeltaM = 0.0

    var snapshot: ClubRecommendationConditions {
        ClubRecommendationConditions(
            temperatureC: temperatureC,
            pressureInputMode: pressureInputMode,
            pressureHpa: pressureHpa,
            siteElevationM: siteElevationM,
            humidityPct: humidityPct,
            tailwindMps: tailwindMps,
            crosswindMps: crosswindMps,
            elevationDeltaM: elevationDeltaM
        )
    }

    func reset() {
        temperatureC = 20.0
        pressureInputMode = .elevation
        siteElevationM = 0.0
        pressureHpa = 1013.25
        humidityPct = 50.0
        tailwindMps = 0.0
        crosswindMps = 0.0
        elevationDeltaM = 0.0
    }

    private var isSyncingAtmosphere = false

    private func syncPressureFromElevation() {
        guard !isSyncingAtmosphere else { return }
        if let derived = try? Atmosphere.standardPressureHpa(fromAltitudeM: siteElevationM) {
            isSyncingAtmosphere = true
            pressureHpa = derived
            isSyncingAtmosphere = false
        }
    }

    private func syncElevationFromPressure() {
        guard !isSyncingAtmosphere else { return }
        if let derived = try? Atmosphere.altitudeM(fromStandardPressureHpa: pressureHpa) {
            isSyncingAtmosphere = true
            siteElevationM = derived
            isSyncingAtmosphere = false
        }
    }
}

struct TrajectoryClubView: View {
    @ObservedObject var viewModel: TrajectoryCalculatorViewModel
    let onOpenTrajectory: () -> Void
    var onHome: () -> Void = {}
    @StateObject private var clubConditions = ClubConditionsStore()
    @State private var targetCarryMetersValue = Units.metersFromYards(150)
    @State private var recommendations: [ClubRecommendation] = []
    @State private var errorMessage: String?
    @State private var isCalculating = false
    @State private var recommendationGeneration = 0
    @State private var recommendationTask: Task<Void, Never>?
    @State private var showConditions = false
    private let recommendationAnchor = "recommended-club"

    private struct RecommendationInput: Equatable {
        let targetCarryM: Double
        let conditions: ClubRecommendationConditions
        let profile: TrajectoryPlayerProfile
    }

    private var recommendationInput: RecommendationInput {
        RecommendationInput(targetCarryM: targetCarryMetersValue,
                            conditions: clubConditions.snapshot,
                            profile: viewModel.playerProfileStore.profile)
    }

    init(viewModel: TrajectoryCalculatorViewModel, onOpenTrajectory: @escaping () -> Void = {}, onHome: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onOpenTrajectory = onOpenTrajectory
        self.onHome = onHome
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        TrajectoryPageHeader(
                            title: "Find your club",
                            subtitle: "Set a target and conditions to see the best-matching club and flight.",
                            onReset: resetInputs
                        )
                        selectorCard
                        conditionsCard
                        suggestClubButton

                        if let recommendation = recommendations.first {
                            recommendationCard(recommendation)
                                .id(recommendationAnchor)
                        }

                        if recommendations.count > 1 {
                            alternativesCard
                        }

                        if !recommendations.isEmpty {
                            if let distanceWarning {
                                Label(distanceWarning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            trajectoryGraph
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
                .background(PureLineStyle.canvas)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .onChange(of: isCalculating) { wasCalculating, isCalculating in
                    guard wasCalculating, !isCalculating, !recommendations.isEmpty else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            scrollProxy.scrollTo(recommendationAnchor, anchor: .top)
                        }
                    }
                }
            }
        }
        .tint(PureLineStyle.accent)
        .navigationTitle("Club")
        .accessibilityIdentifier("club-screen")
        .onChange(of: recommendationInput) { _, _ in invalidateRecommendation() }
        .onDisappear { invalidateRecommendation() }
    }

    private var selectorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Distance To Target")
                    .font(.headline)
                    .foregroundStyle(PureLineStyle.ink)
                Spacer()
                Text(formattedWholeDistance(targetCarryMetersValue))
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(PureLineStyle.accent)
            }

            Slider(value: targetCarryBinding, in: targetDistanceRange, step: targetDistanceStep)
                .tint(PureLineStyle.accent)

            HStack {
                Text(formattedWholeDistance(targetDistanceRange.lowerBound))
                Spacer()
                Text(formattedWholeDistance(targetDistanceRange.upperBound))
            }
            .font(.caption)
            .foregroundStyle(PureLineStyle.muted)

            ClubElevationGraphic(
                elevationMeters: $clubConditions.elevationDeltaM,
                temperatureC: clubConditions.temperatureC,
                siteElevationM: clubConditions.siteElevationM,
                unitSystem: viewModel.unitPreferences.unitSystem(for: .distance)
            )
            .frame(height: 240)

            Text("Drag the fairway up or down to set the target elevation.")
                .font(.caption)
                .foregroundStyle(PureLineStyle.muted)

            ClubWindGraphic(
                tailwindMps: $clubConditions.tailwindMps,
                crosswindMps: $clubConditions.crosswindMps,
                unitSystem: viewModel.unitPreferences.unitSystem(for: .windSpeed)
            )
            .frame(height: 150)

            Text("Drag the wind arrow to set the combined headwind, tailwind, and crosswind.")
                .font(.caption)
                .foregroundStyle(PureLineStyle.muted)

        }
        .pureLineCard()
    }

    private var suggestClubButton: some View {
        Button {
            calculateRecommendation()
        } label: {
            Group {
                if isCalculating {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Calculating…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Suggest Club", systemImage: "figure.golf")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(PureLinePrimaryButtonStyle())
        .frame(height: 52)
        .disabled(isCalculating)
        .accessibilityIdentifier("suggest-club-button")
    }

    private var conditionsCard: some View {
        DisclosureGroup(isExpanded: $showConditions) {
            advancedConditions
                .padding(.top, 14)
        } label: {
            Label("Conditions", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(PureLineStyle.ink)
        }
        .pureLineCard()
    }

    private var advancedConditions: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrajectoryMeasurementField(
                title: "Temperature",
                explanation: "Air temperature at the location of the shot.",
                diagram: .temperature,
                metricValue: $clubConditions.temperatureC,
                kind: .temperature,
                unitSystem: viewModel.unitPreferences.unitSystem(for: .temperature),
                metricRange: -10...45,
                decimalPlaces: 0
            )
            ClubAtmosphereField(
                siteElevationM: $clubConditions.siteElevationM,
                pressureInputMode: $clubConditions.pressureInputMode,
                unitPreferences: viewModel.unitPreferences
            )
            TrajectoryMeasurementField(
                title: "Humidity",
                explanation: "Relative humidity of the air, expressed as a percentage.",
                diagram: .humidity,
                metricValue: $clubConditions.humidityPct,
                kind: .percent,
                unitSystem: viewModel.unitPreferences.globalDefault,
                metricRange: 0...100
            )
            TrajectoryMeasurementField(
                title: "Tailwind (headwind is negative)",
                explanation: "Wind along the target line. Positive pushes the ball toward the target; negative is a headwind.",
                diagram: .tailwind,
                metricValue: $clubConditions.tailwindMps,
                kind: .speed,
                unitSystem: viewModel.unitPreferences.unitSystem(for: .windSpeed),
                metricRange: Units.mpsFromMph(-30)...Units.mpsFromMph(30),
                decimalPlaces: 0
            )
            TrajectoryMeasurementField(
                title: "Crosswind (right is positive)",
                explanation: "Wind perpendicular to the target line. Positive blows toward the right.",
                diagram: .crosswind,
                metricValue: $clubConditions.crosswindMps,
                kind: .speed,
                unitSystem: viewModel.unitPreferences.unitSystem(for: .windSpeed),
                metricRange: Units.mpsFromMph(-30)...Units.mpsFromMph(30),
                decimalPlaces: 0
            )
        }
    }

    private func recommendationCard(_ recommendation: ClubRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommended Club")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PureLineStyle.muted)
            Text(recommendation.club.label)
                .font(.largeTitle.bold())
                .foregroundStyle(PureLineStyle.ink)
            Text("Estimated Carry Distance: \(formattedDistance(recommendation.estimatedCarryM))")
                .font(.headline)
                .foregroundStyle(PureLineStyle.accent)
            Text("Difference from target: \(formattedDistance(recommendation.differenceM))")
                .font(.subheadline)
                .foregroundStyle(PureLineStyle.muted)
            Label(aimAdvice(for: recommendation), systemImage: "scope")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PureLineStyle.ink)
            if let warning = elevationWarning(for: recommendation) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                let conditions = clubConditions.snapshot
                viewModel.prepareTrajectory(for: recommendation.club, conditions: conditions)
                viewModel.calculate(includeAdvancedConditions: true)
                onOpenTrajectory()
            } label: {
                Label("View Trajectory", systemImage: "chart.xyaxis.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PureLinePrimaryButtonStyle(minimumHeight: 48))
            .accessibilityIdentifier("view-recommended-trajectory-button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
        .accessibilityIdentifier("recommended-club-card")
    }

    private var trajectoryGraph: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Club Trajectories")
                .font(.headline)
                .foregroundStyle(PureLineStyle.ink)

            Text("Recommended and closest alternatives")
                .font(.subheadline)
                .foregroundStyle(PureLineStyle.muted)

            Chart {
                ForEach(trajectoryChartPoints) { point in
                    trajectoryMark(point)
                }

                RuleMark(x: .value("Target", targetCarryMeters))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .chartXAxisLabel("Carry (\(distanceUnit))")
            .chartYAxisLabel("Height (\(distanceUnit))")
            .frame(height: 250)
            .accessibilityLabel("Club trajectory comparison")
            .accessibilityHint("Shows the recommended club and closest alternatives with the target marked by a green line.")

            Text("Top-Down View")
                .font(.subheadline.bold())
                .foregroundStyle(PureLineStyle.ink)

            Chart {
                ForEach(lateralChartPoints) { point in
                    lateralTrajectoryMark(point)
                }
                RuleMark(y: .value("Target Line", 0))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .chartXAxisLabel("Downrange (\(distanceUnit))")
            .chartYAxisLabel("Lateral (\(distanceUnit))")
            .frame(height: 180)
            .accessibilityLabel("Top-down club trajectory comparison")
            .accessibilityHint("Shows club curvature relative to the target line.")

            ForEach(Array(recommendations.prefix(4))) { recommendation in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: recommendation))
                        .frame(width: 8, height: 8)
                    Text(recommendation.club.label)
                        .font(.caption)
                        .foregroundStyle(PureLineStyle.ink)
                }
            }
        }
        .pureLineCard()
    }

    private struct TrajectoryChartPoint: Identifiable {
        let id: String
        let clubLabel: String
        let distanceM: Double
        let heightM: Double
        let color: Color
        let isRecommended: Bool
        let isLastPoint: Bool
    }

    private struct LateralChartPoint: Identifiable {
        let id: String
        let clubLabel: String
        let distanceM: Double
        let lateralM: Double
        let color: Color
    }

    private var trajectoryChartPoints: [TrajectoryChartPoint] {
        Array(recommendations.prefix(4)).flatMap { recommendation in
            let points = zip(recommendation.trajectory.xM, recommendation.trajectory.zM).map { ($0, $1) }
            return points.enumerated().map { index, point in
                TrajectoryChartPoint(
                    id: "\(recommendation.club.rawValue)-\(index)",
                    clubLabel: recommendation.club.label,
                    distanceM: point.0,
                    heightM: point.1,
                    color: color(for: recommendation),
                    isRecommended: recommendation.id == recommendations.first?.id,
                    isLastPoint: index == points.count - 1
                )
            }
        }
    }

    private var lateralChartPoints: [LateralChartPoint] {
        Array(recommendations.prefix(4)).flatMap { recommendation in
            zip(recommendation.trajectory.xM, recommendation.trajectory.yM).enumerated().map { index, point in
                LateralChartPoint(
                    id: "lateral-\(recommendation.club.rawValue)-\(index)",
                    clubLabel: recommendation.club.label,
                    distanceM: point.0,
                    lateralM: point.1,
                    color: color(for: recommendation)
                )
            }
        }
    }

    @ChartContentBuilder
    private func trajectoryMark(_ point: TrajectoryChartPoint) -> some ChartContent {
        LineMark(
            x: .value("Distance", point.distanceM),
            y: .value("Height", point.heightM),
            series: .value("Club", point.clubLabel)
        )
        .interpolationMethod(.catmullRom)
        .foregroundStyle(point.color)

        if point.isLastPoint {
            PointMark(
                x: .value("Distance", point.distanceM),
                y: .value("Height", point.heightM)
            )
            .foregroundStyle(point.color)
        }
    }

    @ChartContentBuilder
    private func lateralTrajectoryMark(_ point: LateralChartPoint) -> some ChartContent {
        LineMark(
            x: .value("Distance", point.distanceM),
            y: .value("Lateral", point.lateralM),
            series: .value("Club", point.clubLabel)
        )
        .interpolationMethod(.catmullRom)
        .foregroundStyle(point.color)
    }

    private var targetCarryMeters: Double {
        targetCarryMetersValue
    }

    private var targetDistanceRange: ClosedRange<Double> {
        Units.metersFromYards(20)...300
    }

    private var targetDistanceStep: Double {
        viewModel.unitPreferences.unitSystem(for: .distance) == .imperial
            ? Units.metersFromYards(1)
            : 1
    }

    private var targetCarryBinding: Binding<Double> {
        Binding(
            get: { min(max(targetCarryMetersValue, targetDistanceRange.lowerBound), targetDistanceRange.upperBound) },
            set: { targetCarryMetersValue = $0 }
        )
    }

    private func color(for recommendation: ClubRecommendation) -> Color {
        switch recommendations.firstIndex(where: { $0.id == recommendation.id }) ?? 0 {
        case 0: return FairwayVectorColors.flightBlue
        case 1: return FairwayVectorColors.orange
        case 2: return FairwayVectorColors.gold
        default: return FairwayVectorColors.navy
        }
    }

    private var alternativesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Closest Alternatives")
                .font(.headline)
                .foregroundStyle(PureLineStyle.ink)
            ForEach(Array(recommendations.dropFirst().prefix(3))) { recommendation in
                HStack {
                    Text(recommendation.club.label)
                    Spacer()
                    Text(formattedDistance(recommendation.estimatedCarryM))
                        .foregroundStyle(PureLineStyle.ink)
                }
                .font(.subheadline)
                if let warning = elevationWarning(for: recommendation) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
    }

    private var distanceUnit: String {
        viewModel.unitPreferences.unitSystem(for: .distance) == .imperial ? "yd" : "m"
    }

    private func formattedWholeDistance(_ meters: Double) -> String {
        let system = viewModel.unitPreferences.unitSystem(for: .distance)
        let value = system == .imperial ? Units.yardsFromMeters(meters) : meters
        return String(format: "%.0f %@", value, system == .imperial ? "yd" : "m")
    }

    private func formattedDistance(_ meters: Double) -> String {
        Units.formattedDistance(meters: meters, system: viewModel.unitPreferences.unitSystem(for: .distance))
    }

    private func formattedHeight(_ meters: Double) -> String {
        Units.formattedHeight(meters: meters, system: viewModel.unitPreferences.unitSystem(for: .distance))
    }

    private var distanceWarning: String? {
          guard let closest = recommendations.first else { return nil }
        let carryToleranceM = Units.metersFromYards(10)
        let hasClubWithinPracticalRange = recommendations.contains {
            $0.estimatedCarryM + carryToleranceM >= targetCarryMeters
        }
        let hasFlightReachingTarget = recommendations.contains {
            ($0.trajectory.xM.last ?? 0) + 0.1 >= targetCarryMeters
        }
        guard !hasClubWithinPracticalRange, !hasFlightReachingTarget else { return nil }
        return "No modeled flight reaches the target distance. Closest estimate: \(formattedDistance(closest.estimatedCarryM)) for a \(formattedDistance(targetCarryMeters)) target."
    }

    private func elevationWarning(for recommendation: ClubRecommendation) -> String? {
        guard recommendation.targetElevationM > 0 else { return nil }
        guard let heightAtTarget = recommendation.heightAtTargetDistanceM else { return nil }
        guard heightAtTarget + 0.1 < recommendation.targetElevationM else { return nil }
        return "Below target elevation at target distance (\(formattedHeight(heightAtTarget)) vs \(formattedHeight(recommendation.targetElevationM)))"
    }

    private func aimAdvice(for recommendation: ClubRecommendation) -> String {
        guard let lateral = recommendation.lateralAtTargetDistanceM, abs(lateral) >= 0.5 else {
            return "Aim at target"
        }
        let aimDistance = formattedDistance(abs(lateral))
        return lateral > 0 ? "Aim \(aimDistance) left" : "Aim \(aimDistance) right"
    }

    private func invalidateRecommendation() {
        recommendationGeneration += 1
        recommendationTask?.cancel()
        recommendationTask = nil
        isCalculating = false
        recommendations = []
        errorMessage = nil
    }

    private func resetInputs() {
        invalidateRecommendation()
        targetCarryMetersValue = Units.metersFromYards(150)
        clubConditions.reset()
    }

    private func calculateRecommendation() {
        invalidateRecommendation()
        let captured = recommendationInput
        let generation = recommendationGeneration
        guard captured.targetCarryM.isFinite, captured.targetCarryM > 0 else {
            errorMessage = "Set a target carry distance greater than zero."
            return
        }
        isCalculating = true
        recommendationTask = Task { @MainActor in
            // Only the owning request may clear the spinner/task of a newer run.
            defer {
                if recommendationGeneration == generation {
                    isCalculating = false
                    recommendationTask = nil
                }
            }
            guard !Task.isCancelled, recommendationGeneration == generation,
                  recommendationInput == captured else { return }
            do {
                let calculated = try await viewModel.recommendClub(for: captured.targetCarryM,
                    conditions: captured.conditions, profile: captured.profile)
                guard !Task.isCancelled, recommendationGeneration == generation,
                      recommendationInput == captured else { return }
                recommendations = calculated
            } catch is CancellationError {
                // Reset/input edits/new requests own the screen now.
            } catch {
                guard !Task.isCancelled, recommendationGeneration == generation,
                      recommendationInput == captured else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ClubElevationGraphic: View {
    @Binding var elevationMeters: Double
    let temperatureC: Double
    let siteElevationM: Double
    let unitSystem: UnitSystem

    @State private var dragStartElevation: Double?
    private let maximumElevationMeters = Units.metersFromFeet(100)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let baseY = height * 0.72
            let travel = height * 0.30
            let greenY = baseY - CGFloat(elevationMeters / maximumElevationMeters) * travel
            let targetX = width * 0.82
            let cloudCount = siteElevationM >= 100 ? 8 : 0
            let cloudSlide = min(max((siteElevationM - 100) / 2900, 0), 1)

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color(red: 0.76, green: 0.87, blue: 0.94), Color(red: 0.90, green: 0.94, blue: 0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ClubFairwayShape(baseY: baseY, greenY: greenY, greenLeft: width * 0.45)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.30, green: 0.52, blue: 0.28), Color(red: 0.18, green: 0.36, blue: 0.20)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Path { path in
                    path.move(to: CGPoint(x: 8, y: baseY))
                    path.addLine(to: CGPoint(x: width - 8, y: baseY))
                }
                .stroke(PureLineStyle.ink.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.56, green: 0.76, blue: 0.44), Color(red: 0.40, green: 0.62, blue: 0.32)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Ellipse().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
                    .frame(width: width * 0.30, height: 28)
                    .position(x: width * 0.74, y: greenY)

                ZStack(alignment: .topLeading) {
                    ForEach(0..<8, id: \.self) { index in
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 18 + CGFloat(index % 4) * 3, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .position(
                                x: width * (0.06 + CGFloat(index) / 7 * 0.88),
                                y: 4 + CGFloat(cloudSlide) * height * 0.54 + CGFloat(index % 3) * 8
                            )
                            .opacity(index < cloudCount ? 1 : 0)
                    }
                }

                TemperatureSun(temperatureC: temperatureC)
                    .position(x: width * 0.84, y: height * 0.18)

                Image(systemName: "figure.golf")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(PureLineStyle.ink)
                    .position(x: width * 0.13, y: baseY - 18)

                ClubFixedFlag()
                    .position(x: targetX, y: greenY - 24)

                Text("Fairway")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .position(x: width * 0.30, y: baseY + 18)

                Text(formattedElevation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PureLineStyle.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.92), in: Capsule())
                    .position(x: width * 0.18, y: height * 0.16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(elevationGesture(travel: travel))
            .animation(.interactiveSpring(duration: 0.18), value: elevationMeters)
            .animation(.easeOut(duration: 0.45), value: siteElevationM)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fairway elevation profile")
        .accessibilityValue(formattedElevation)
        .accessibilityHint("Adjustable elevation. The target pin position is fixed.")
        .accessibilityAdjustableAction { direction in
            let step = unitSystem == .imperial ? Units.metersFromFeet(1) : 1
            elevationMeters = min(max(elevationMeters + (direction == .increment ? step : -step), -maximumElevationMeters), maximumElevationMeters)
        }
    }

    private var formattedElevation: String {
        let value = unitSystem == .imperial ? Units.feetFromMeters(elevationMeters) : elevationMeters
        let suffix = unitSystem == .imperial ? "ft" : "m"
        return String(format: "Elevation %+.0f %@", value, suffix)
    }

    private func elevationGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartElevation == nil { dragStartElevation = elevationMeters }
                let metersPerPoint = maximumElevationMeters / Double(max(travel, 1))
                let proposed = min(max((dragStartElevation ?? 0) - Double(value.translation.height) * metersPerPoint, -maximumElevationMeters), maximumElevationMeters)
                let step = unitSystem == .imperial ? Units.metersFromFeet(1) : 1
                elevationMeters = (proposed / step).rounded() * step
            }
            .onEnded { _ in dragStartElevation = nil }
    }
}

private struct ClubFairwayShape: Shape {
    let baseY: CGFloat
    let greenY: CGFloat
    let greenLeft: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let slopeStart = greenLeft - rect.width * 0.18
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: baseY))
        path.addLine(to: CGPoint(x: slopeStart, y: baseY))
        path.addCurve(
            to: CGPoint(x: greenLeft, y: greenY),
            control1: CGPoint(x: slopeStart + rect.width * 0.08, y: baseY),
            control2: CGPoint(x: greenLeft - rect.width * 0.06, y: greenY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: greenY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ClubFixedFlag: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "flag.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PureLineStyle.accent)
                .offset(x: 7)
            Rectangle()
                .fill(PureLineStyle.ink)
                .frame(width: 2, height: 22)
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(PureLineStyle.ink.opacity(0.35), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct TemperatureSun: View {
    let temperatureC: Double

    private var diameter: CGFloat {
        let normalized = min(max((temperatureC + 10) / 55, 0), 1)
        return 18 + CGFloat(normalized) * 32
    }

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 2, height: 7)
                    .offset(y: -(diameter * 0.5 + 6))
                    .rotationEffect(.degrees(Double(index) * 45))
            }

            Circle()
                .fill(Color.yellow)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(Color.orange.opacity(0.7), lineWidth: 1))
        }
        .frame(width: diameter + 16, height: diameter + 16)
        .accessibilityHidden(true)
    }
}

private struct ClubWindGraphic: View {
    @Binding var tailwindMps: Double
    @Binding var crosswindMps: Double
    let unitSystem: UnitSystem

    @State private var arrowEndpoint: CGPoint?
    private let maximumWindMps = Units.mpsFromMph(30)
    private let visualScaleWindMps = 14.0

    var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let windMagnitude = sqrt(tailwindMps * tailwindMps + crosswindMps * crosswindMps)
                let directionX = tailwindMps / max(windMagnitude, 0.001)
                let directionY = -crosswindMps / max(windMagnitude, 0.001)
                let arrowOpacity = min(max(windMagnitude / maximumWindMps, 0.25), 1)

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.84, green: 0.92, blue: 0.97), Color(red: 0.70, green: 0.84, blue: 0.92)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Path { path in
                        path.move(to: CGPoint(x: width * 0.12, y: height * 0.5))
                        path.addLine(to: CGPoint(x: width * 0.88, y: height * 0.5))
                        path.move(to: CGPoint(x: width * 0.5, y: height * 0.18))
                        path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.82))
                    }
                    .stroke(PureLineStyle.ink.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.56, green: 0.76, blue: 0.44), Color(red: 0.40, green: 0.62, blue: 0.32)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(Ellipse().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                        .frame(width: width * 0.24, height: height * 0.58)
                        .position(x: width * 0.78, y: height * 0.5)

                    ClubFixedFlag()
                        .scaleEffect(0.72)
                        .position(x: width * 0.78, y: height * 0.5)

                    Image(systemName: "figure.golf")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(PureLineStyle.ink)
                        .position(x: width * 0.16, y: height * 0.5)

                    let arrowStart = CGPoint(x: width * 0.5, y: height * 0.5)
                    let defaultArrowLength = max(12, min(CGFloat(windMagnitude / visualScaleWindMps), 1) * width * 0.46)
                    let defaultArrowEnd = CGPoint(
                        x: arrowStart.x + directionX * defaultArrowLength,
                        y: arrowStart.y + directionY * defaultArrowLength
                    )
                    let arrowEnd = arrowEndpoint ?? defaultArrowEnd
                    let arrowDeltaX = arrowEnd.x - arrowStart.x
                    let arrowDeltaY = arrowEnd.y - arrowStart.y
                    let renderedArrowLength = max(12, hypot(arrowDeltaX, arrowDeltaY))
                    let renderedDirection = Angle(radians: atan2(arrowDeltaY, arrowDeltaX))

                    Capsule()
                        .fill(PureLineStyle.accent.opacity(arrowOpacity))
                        .frame(width: renderedArrowLength, height: 5)
                        .rotationEffect(renderedDirection)
                        .position(
                            x: arrowStart.x + arrowDeltaX * 0.5,
                            y: arrowStart.y + arrowDeltaY * 0.5
                        )

                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PureLineStyle.accent.opacity(arrowOpacity))
                        .rotationEffect(renderedDirection)
                        .position(arrowEnd)

                    Text(windSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PureLineStyle.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.92), in: Capsule())
                        .position(x: width * 0.22, y: height * 0.18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .gesture(windGesture(size: geometry.size))
                .animation(.interactiveSpring(duration: 0.18), value: tailwindMps)
                .animation(.interactiveSpring(duration: 0.18), value: crosswindMps)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wind direction")
            .accessibilityValue(windSummary)
            .accessibilityHint("Drag horizontally for headwind or tailwind and vertically for crosswind.")
        }

        private var windSummary: String {
            let magnitude = sqrt(tailwindMps * tailwindMps + crosswindMps * crosswindMps)
            return "Wind \(displaySpeed(magnitude))"
        }

        private func displaySpeed(_ metersPerSecond: Double) -> String {
            let value = unitSystem == .imperial ? Units.mphFromMps(metersPerSecond) : metersPerSecond
            let suffix = unitSystem == .imperial ? "mph" : "m/s"
            return String(format: "%.0f %@", value, suffix)
        }

        private func windGesture(size: CGSize) -> some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                    arrowEndpoint = value.location
                    let horizontalScale = maximumWindMps / Double(max(size.width * 0.46, 1))
                    let verticalScale = maximumWindMps / Double(max(size.height * 0.46, 1))
                    tailwindMps = min(max(Double(value.location.x - center.x) * horizontalScale, -maximumWindMps), maximumWindMps)
                    crosswindMps = min(max(-Double(value.location.y - center.y) * verticalScale, -maximumWindMps), maximumWindMps)
                }
        }
    }

private struct ClubDoneAccessoryNumberField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.placeholder = placeholder
        textField.keyboardType = .decimalPad
        textField.textAlignment = .center
        textField.font = UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.delegate = context.coordinator
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Done", style: .prominent, target: textField, action: #selector(UITextField.resignFirstResponder))
        ]
        textField.inputAccessoryView = toolbar
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        textField.placeholder = placeholder
        if textField.text != text {
            textField.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if let endPosition = textField.endOfDocument as UITextPosition? {
                textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
            }
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            text = textField.text ?? ""
        }
    }
}

private struct ClubAtmosphereField: View {
    @Binding var siteElevationM: Double
    @Binding var pressureInputMode: PressureInputMode
    let unitPreferences: UnitPreferences

    private let minimumElevationM = -100.0
    private let maximumElevationM = 3000.0

    private var distanceSystem: UnitSystem {
        unitPreferences.unitSystem(for: .distance)
    }

    private var pressureSystem: UnitSystem {
        unitPreferences.unitSystem(for: .pressure)
    }

    private var sliderPosition: Binding<Double> {
        Binding(
            get: {
                min(max((siteElevationM - minimumElevationM) / (maximumElevationM - minimumElevationM), 0.0), 1.0)
            },
            set: { position in
                siteElevationM = minimumElevationM + position * (maximumElevationM - minimumElevationM)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pressureInputMode == .elevation ? "Site Elevation" : "Pressure")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(displayValue)
                    .font(.subheadline.monospacedDigit().bold())
            }

            Picker("Atmosphere representation", selection: $pressureInputMode) {
                ForEach(PressureInputMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Slider(value: sliderPosition, in: 0...1)
        }
    }

    private var displayValue: String {
        switch pressureInputMode {
        case .elevation:
            let value = distanceSystem == .imperial ? Units.feetFromMeters(siteElevationM) : siteElevationM
            let suffix = distanceSystem == .imperial ? "ft" : "m"
            return String(format: "%.0f %@", value, suffix)
        case .pressure:
            guard let pressure = try? Atmosphere.standardPressureHpa(fromAltitudeM: siteElevationM) else {
                return "Unavailable"
            }
            return Units.formattedPressure(hpa: pressure, system: pressureSystem)
        }
    }
}

#Preview {
    TrajectoryClubView(viewModel: TrajectoryCalculatorViewModel())
}