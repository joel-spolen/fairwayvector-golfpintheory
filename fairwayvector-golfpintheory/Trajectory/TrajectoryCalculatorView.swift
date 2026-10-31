import SwiftUI

struct TrajectoryCalculatorView: View {
    private enum TrajectoryInputMode: String, CaseIterable, Identifiable {
        case simple
        case advanced

        var id: String { rawValue }

        var label: String {
            switch self {
            case .simple: return L("Simple")
            case .advanced: return L("Advanced")
            }
        }
    }

    private enum LaunchConditionSource: String, CaseIterable, Identifiable {
        case club
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .club: return L("Club")
            case .custom: return L("Custom")
            }
        }
    }

    @ObservedObject var viewModel: TrajectoryCalculatorViewModel
    var onHome: () -> Void = {}
    @AppStorage("trajectory.calculator.inputMode", store: .standard) private var inputModeRawValue = TrajectoryInputMode.simple.rawValue
    @State private var launchSource: LaunchConditionSource = .club
    @State private var showConditions = false
    private let resultsAnchor = "trajectory-results"

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 20) {
                        TrajectoryPageHeader(
                            title: L("Plan your shot"),
                            subtitle: L("Enter launch conditions and course factors to estimate carry and flight."),
                            onReset: { viewModel.resetInputs() }
                        )
                        launchConditionsCard
                        environmentCard
                        calculateButton

                        if let errorMessage = viewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let prediction = viewModel.prediction {
                            resultsContent(prediction: prediction)
                                .id(resultsAnchor)
                                .onAppear {
                                    scrollToResults(using: scrollProxy)
                                }
                        } else if viewModel.errorMessage == nil {
                            Label("Enter shot conditions to estimate carry distance and trajectory.", systemImage: "figure.golf")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
                .background(PureLineStyle.canvas)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .onChange(of: viewModel.isCalculating) { wasCalculating, isCalculating in
                    guard wasCalculating, !isCalculating, viewModel.prediction != nil else { return }
                    scrollToResults(using: scrollProxy)
                }
            }
        }
        .tint(PureLineStyle.accent)
        .onAppear {
            ensureActiveClubIsAvailable()
        }
        .accessibilityIdentifier("calculator-screen")
    }

    private func ensureActiveClubIsAvailable() {
        guard !viewModel.playerProfileStore.profile.availableClubs.contains(viewModel.activeClub),
              let highestAvailableClub = ownedClubs.first else { return }
        viewModel.activeClub = highestAvailableClub
    }

    private func resultsContent(prediction: HybridPrediction) -> some View {
        VStack(spacing: 20) {
            TrajectoryResultsView(prediction: prediction, unitPreferences: viewModel.unitPreferences)
            TrajectoryChartView(trajectory: prediction.physics.trajectory, unitPreferences: viewModel.unitPreferences)
            Color.clear
                .frame(height: 360)
        }
    }

    private func scrollToResults(using scrollProxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.35)) {
                scrollProxy.scrollTo(resultsAnchor, anchor: .top)
            }
        }
    }

    private var launchConditionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Launch Conditions")
                .font(.headline)
                .foregroundStyle(PureLineStyle.ink)

            Picker("Launch Source", selection: $launchSource) {
                ForEach(LaunchConditionSource.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: launchSource) { _, source in
                if source == .club {
                    viewModel.applyActiveClubProfile()
                }
            }

            if launchSource == .club && viewModel.playerProfileStore.profile.isSetupComplete {
                NavigationLink {
                    ClubCarouselView(selection: $viewModel.activeClub, clubs: ownedClubs)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.golf")
                            .font(.title3)
                            .foregroundStyle(PureLineStyle.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Club")
                                .font(.caption)
                                .foregroundStyle(PureLineStyle.muted)
                            Text(viewModel.activeClub.label)
                                .font(.headline)
                                .foregroundStyle(PureLineStyle.ink)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PureLineStyle.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .pureLineCard(padding: 14)
            } else if launchSource == .club {
                Label("Set up a profile to use club defaults.", systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.muted)
            }

            if launchSource == .custom {
                customLaunchFields
            }
        }
        .pureLineCard()
    }

    private var customLaunchFields: some View {
        Group {
            TrajectoryMeasurementField(
                title: L("Ball Speed"),
                explanation: L("Speed of the ball immediately after impact."),
                diagram: .ballSpeed,
                metricValue: $viewModel.ballSpeedMps,
                kind: .speed,
                unitSystem: viewModel.unitPreferences.unitSystem(for: .ballSpeed),
                metricRange: Units.mpsFromMph(40)...Units.mpsFromMph(220),
                decimalPlaces: 1
            )
            TrajectoryMeasurementField(
                title: L("Launch Angle"),
                explanation: L("The ball's initial upward angle."),
                diagram: .launchAngle,
                metricValue: $viewModel.launchAngleDeg,
                kind: .angle,
                unitSystem: viewModel.unitPreferences.globalDefault,
                metricRange: 0...45,
                decimalPlaces: 1
            )
            TrajectoryMeasurementField(
                title: L("Launch Direction"),
                explanation: L("Horizontal angle relative to the target line. Negative is left and positive is right."),
                diagram: .launchDirection,
                metricValue: $viewModel.launchDirectionDeg,
                kind: .angle,
                unitSystem: viewModel.unitPreferences.globalDefault,
                metricRange: -30...30,
                decimalPlaces: 1
            )
            TrajectoryMeasurementField(
                title: L("Spin Rate"),
                explanation: L("Backspin rate in revolutions per minute."),
                diagram: .spinRate,
                metricValue: $viewModel.spinRateRpm,
                kind: .spin,
                unitSystem: viewModel.unitPreferences.globalDefault,
                metricRange: 500...10000
            )
            TrajectoryMeasurementField(
                title: L("Spin Axis"),
                explanation: L("Tilt of the spin axis. Zero is pure backspin; positive values curve right."),
                diagram: .spinAxis,
                metricValue: $viewModel.spinAxisDeg,
                kind: .angle,
                unitSystem: viewModel.unitPreferences.globalDefault,
                metricRange: -45...45,
                decimalPlaces: 1
            )
        }
    }

    private var ownedClubs: [TrajectoryGolfClub] {
        let clubs = TrajectoryGolfClub.allCases.filter {
            viewModel.playerProfileStore.isAvailable(for: $0)
        }
        return clubs.isEmpty ? [viewModel.activeClub] : clubs
    }

    private var environmentCard: some View {
        DisclosureGroup(isExpanded: $showConditions) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Condition Detail", selection: inputModeBinding) {
                    ForEach(TrajectoryInputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if inputMode == .simple {
                    VStack(alignment: .leading, spacing: 16) {
                        simpleConditionFields
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        advancedConditionFields
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.top, 14)
        } label: {
            Label("Conditions", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(PureLineStyle.ink)
        }
        .pureLineCard()
    }

    private var inputMode: TrajectoryInputMode {
        TrajectoryInputMode(rawValue: inputModeRawValue) ?? .simple
    }

    private var inputModeBinding: Binding<TrajectoryInputMode> {
        Binding(
            get: { inputMode },
            set: { inputModeRawValue = $0.rawValue }
        )
    }

    private var simpleConditionFields: some View {
        Group {
            TrajectoryMeasurementField(
                title: L("Tailwind (headwind is negative)"),
                explanation: L("Wind along the target line. Positive pushes the ball toward the target; negative is a headwind."),
                diagram: .tailwind,
                metricValue: $viewModel.tailwindMps,
                kind: .speed,
                unitSystem: viewModel.unitPreferences.unitSystem(for: .windSpeed),
                metricRange: Units.mpsFromMph(-30)...Units.mpsFromMph(30),
                decimalPlaces: 0
            )
            TrajectoryMeasurementField(
                title: L("Elevation Change"),
                explanation: L("Height difference between the launch point and the landing surface. This is separate from site elevation."),
                diagram: .elevationChange,
                metricValue: $viewModel.elevationDeltaM,
                kind: .distance,
                unitSystem: viewModel.unitPreferences.unitSystem(for: .distance),
                metricRange: Units.metersFromFeet(-100)...Units.metersFromFeet(100)
            )
        }
    }

    private var advancedConditionFields: some View {
        Group {
                    TrajectoryMeasurementField(
                        title: L("Temperature"),
                        explanation: L("Air temperature at the location of the shot."),
                        diagram: .temperature,
                        metricValue: $viewModel.temperatureC,
                        kind: .temperature,
                        unitSystem: viewModel.unitPreferences.unitSystem(for: .temperature),
                        metricRange: -10...45,
                        decimalPlaces: 0
                    )

                    AtmosphereField(
                        siteElevationM: $viewModel.siteElevationM,
                        pressureInputMode: $viewModel.pressureInputMode,
                        unitPreferences: viewModel.unitPreferences
                    )

                    TrajectoryMeasurementField(
                        title: L("Humidity"),
                        explanation: L("Relative humidity of the air, expressed as a percentage."),
                        diagram: .humidity,
                        metricValue: $viewModel.humidityPct,
                        kind: .percent,
                        unitSystem: viewModel.unitPreferences.globalDefault,
                        metricRange: 0...100
                    )
                    TrajectoryMeasurementField(
                        title: L("Tailwind (headwind is negative)"),
                        explanation: L("Wind along the target line. Positive pushes the ball toward the target; negative is a headwind."),
                        diagram: .tailwind,
                        metricValue: $viewModel.tailwindMps,
                        kind: .speed,
                        unitSystem: viewModel.unitPreferences.unitSystem(for: .windSpeed),
                        metricRange: Units.mpsFromMph(-30)...Units.mpsFromMph(30),
                        decimalPlaces: 0
                    )
                    TrajectoryMeasurementField(
                        title: L("Crosswind (right is positive)"),
                        explanation: L("Wind perpendicular to the target line. Positive blows toward the right side of the target line."),
                        diagram: .crosswind,
                        metricValue: $viewModel.crosswindMps,
                        kind: .speed,
                        unitSystem: viewModel.unitPreferences.unitSystem(for: .windSpeed),
                        metricRange: Units.mpsFromMph(-30)...Units.mpsFromMph(30),
                        decimalPlaces: 0
                    )
                    TrajectoryMeasurementField(
                        title: L("Elevation Change"),
                        explanation: L("Height difference between the launch point and the landing surface. This is separate from site elevation."),
                        diagram: .elevationChange,
                        metricValue: $viewModel.elevationDeltaM,
                        kind: .distance,
                        unitSystem: viewModel.unitPreferences.unitSystem(for: .distance),
                        metricRange: Units.metersFromFeet(-100)...Units.metersFromFeet(100)
                    )
        }
    }

    private var calculateButton: some View {
        Button {
            viewModel.calculate(includeAdvancedConditions: inputMode == .advanced)
        } label: {
            Group {
                if viewModel.isCalculating {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Calculating…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Calculate Trajectory", systemImage: "arrow.up.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(PureLinePrimaryButtonStyle())
        .frame(height: 52)
        .disabled(viewModel.isCalculating)
        .accessibilityIdentifier("calculate-trajectory-button")
        .accessibilityHint("Calculates the golf ball's trajectory")
    }
}

struct ClubCarouselView: View {
    @Binding var selection: TrajectoryGolfClub
    let clubs: [TrajectoryGolfClub]
    @Environment(\.dismiss) private var dismiss
    @State private var centeredIndex: Int?
    @State private var dragTranslation: CGFloat = 0

    private let cycleCount = 101

    private var carouselClubs: [TrajectoryGolfClub] {
        Array(repeating: clubs, count: cycleCount).flatMap { $0 }
    }

    var body: some View {
        Group {
            VStack(spacing: 18) {
                Text("Choose the club to use for launch conditions.")
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                GeometryReader { geometry in
                    let itemWidth = geometry.size.width * 0.5
                    let itemStep = itemWidth + 8
                    let initialIndex = cycleCount / 2 * clubs.count + (clubs.firstIndex(of: selection) ?? 0)
                    let activeIndex = centeredIndex ?? initialIndex
                    let firstVisibleIndex = max(0, activeIndex - 4)
                    let lastVisibleIndex = min(carouselClubs.count - 1, activeIndex + 4)
                    let leadingOffset = geometry.size.width * 0.5 - itemWidth * 0.5
                    let contentOffset = leadingOffset - CGFloat(activeIndex - firstVisibleIndex) * itemStep
                    let dragProgress = Double(dragTranslation / itemStep)

                    HStack(spacing: 8) {
                        ForEach(firstVisibleIndex...lastVisibleIndex, id: \.self) { index in
                            let club = carouselClubs[index]
                            let distance = Double(index - activeIndex) + dragProgress
                            ClubCarouselCard(club: club, distance: distance, cardWidth: itemWidth)
                                .frame(width: itemWidth, height: 460)
                                .offset(x: dragTranslation)
                                .zIndex(abs(distance) < 0.5 ? 2 : 0)
                                .accessibilityAddTraits(index == activeIndex ? .isSelected : [])
                        }
                    }
                    .offset(x: contentOffset)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                dragTranslation = value.translation.width
                            }
                            .onEnded { value in
                                let step = value.translation.width < -24 ? 1 : (value.translation.width > 24 ? -1 : 0)
                                let targetIndex = max(1, min(activeIndex + step, carouselClubs.count - 2))
                                withAnimation(.easeOut(duration: 0.25)) {
                                    centeredIndex = targetIndex
                                    dragTranslation = 0
                                }
                            }
                    )
                    .onAppear {
                        centeredIndex = initialIndex
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }

                Text(centeredClubLabel)
                    .font(.title2.bold())
                    .foregroundStyle(PureLineStyle.ink)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(PureLineStyle.canvas.ignoresSafeArea())
            .navigationTitle("Club Selector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(PureLineStyle.accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        if let centeredIndex, carouselClubs.indices.contains(centeredIndex) {
                            selection = carouselClubs[centeredIndex]
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private var centeredClubLabel: String {
        guard let centeredIndex, carouselClubs.indices.contains(centeredIndex) else {
            return selection.label
        }
        return carouselClubs[centeredIndex].label
    }
}

private struct ClubCarouselCard: View {
    let club: TrajectoryGolfClub
    let distance: Double
    let cardWidth: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 410)
        }
        .scaleEffect(distance == 0 ? 1.16 : 0.96 - min(abs(distance), 1) * 0.20)
                .offset(x: shaftOffsetRatio * cardWidth * max(0, 1 - min(abs(distance), 1)))
        .offset(y: min(abs(distance), 1) * -72)
        .opacity(distance == 0 ? 1 : 0.9)
    }

    private var imageName: String {
        switch club {
        case .driver: return "driver"
        case .threeWood, .fourWood, .fiveWood, .sixWood, .sevenWood, .eightWood, .nineWood: return "fairwaywood"
        case .threeHybrid, .fourHybrid, .fiveHybrid: return "hybrid"
        case .twoIron, .threeIron, .fourIron, .fiveIron, .sixIron, .sevenIron, .eightIron, .nineIron: return "iron"
        case .pitchingWedge, .approachWedge, .gapWedge, .fiftyTwoWedge, .sandWedge, .fiftySixWedge, .fiftyEightWedge, .lobWedge: return "wedge"
        }
    }

    private var shaftOffsetRatio: CGFloat {
        switch imageName {
        case "driver": return -0.06
        case "fairwaywood": return 0.04
        case "hybrid": return 0.10
        case "iron", "wedge": return -0.31
        default: return 0
        }
    }
}

#Preview {
    TrajectoryCalculatorView(viewModel: TrajectoryCalculatorViewModel())
}

private struct AtmosphereField: View {
    @Binding var siteElevationM: Double
    @Binding var pressureInputMode: PressureInputMode
    let unitPreferences: UnitPreferences
    @State private var showExplanation = false

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
                Text(pressureInputMode == .elevation ? L("Site Elevation") : L("Pressure"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showExplanation = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("About pressure and site elevation")
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
                .accessibilityLabel("Atmosphere value")
                .accessibilityValue(displayValue)
                .accessibilityHint("Adjusts site elevation from minus 100 meters to 3000 meters. Pressure is calculated from the same slider position.")
        }
        .sheet(isPresented: $showExplanation) {
            NavigationStack {
                InfoImagePanel(
                    imageName: "pressure",
                    explanation: L("Pressure is the weight of the air around the ball. Site elevation is the height of the course above sea level. Air pressure generally decreases as site elevation increases.")
                )
                    .padding()
                    .background(PureLineStyle.canvas.ignoresSafeArea())
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExplanation = false }
                        }
                    }
                    .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.light, for: .navigationBar)
                    .tint(PureLineStyle.accent)
            }
            .presentationDetents([.height(420)])
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
                return L("Unavailable")
            }
            return Units.formattedPressure(hpa: pressure, system: pressureSystem)
        }
    }
}
