import SwiftUI

enum InputInfoDiagramKind: Equatable {
    case ballSpeed
    case launchAngle
    case launchDirection
    case spinRate
    case spinAxis
    case temperature
    case humidity
    case pressure
    case tailwind
    case crosswind
    case elevationChange
    case atmosphere
}

/// The physical quantity a `TrajectoryMeasurementField` edits, controlling unit conversion and formatting.
enum MeasurementKind {
    case speed
    case angle
    case spin
    case temperature
    case pressure
    case distance
    case percent

    func displayValue(metric: Double, system: UnitSystem) -> Double {
        switch self {
        case .speed: return system == .imperial ? Units.mphFromMps(metric) : metric
        case .temperature: return system == .imperial ? Units.fahrenheitFromCelsius(metric) : metric
        case .pressure: return system == .imperial ? Units.inHgFromHpa(metric) : metric
        case .distance: return system == .imperial ? Units.feetFromMeters(metric) : metric
        case .angle, .spin, .percent: return metric
        }
    }

    func metricValue(display: Double, system: UnitSystem) -> Double {
        switch self {
        case .speed: return system == .imperial ? Units.mpsFromMph(display) : display
        case .temperature: return system == .imperial ? Units.celsiusFromFahrenheit(display) : display
        case .pressure: return system == .imperial ? Units.hpaFromInHg(display) : display
        case .distance: return system == .imperial ? Units.metersFromFeet(display) : display
        case .angle, .spin, .percent: return display
        }
    }

    func unitSuffix(system: UnitSystem) -> String {
        switch self {
        case .speed: return system == .imperial ? "mph" : "m/s"
        case .angle: return "\u{00B0}"
        case .spin: return "rpm"
        case .temperature: return system == .imperial ? "\u{00B0}F" : "\u{00B0}C"
        case .pressure: return system == .imperial ? "inHg" : "hPa"
        case .distance: return system == .imperial ? "ft" : "m"
        case .percent: return "%"
        }
    }
}

/// A labeled slider + numeric readout for one shot-input field, unit-aware.
struct TrajectoryMeasurementField: View {
    let title: String
    let explanation: String
    let diagram: InputInfoDiagramKind
    @Binding var metricValue: Double
    let kind: MeasurementKind
    let unitSystem: UnitSystem
    let metricRange: ClosedRange<Double>
    var decimalPlaces: Int = 0
    @State private var isEditingValue = false
    @State private var showExplanation = false
    @State private var draftValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.muted)
                Button {
                    showExplanation = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(PureLineStyle.muted)
                .accessibilityLabel("About \(title)")
                .accessibilityHint("Shows an explanation of this input")
                Spacer()
                Button(formattedValue) {
                    draftValue = numericString
                    isEditingValue = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(PureLineStyle.ink)
                    .font(.subheadline.monospacedDigit().bold())
                        .accessibilityHint("Double-tap to type a value")
            }
            Slider(value: displayBinding, in: displayRange)
                .tint(PureLineStyle.accent)
                .accessibilityLabel(title)
                .accessibilityValue(formattedValue)
                .accessibilityHint(explanation)
        }
        .sheet(isPresented: $isEditingValue) {
            editSheet
        }
        .sheet(isPresented: $showExplanation) {
            if diagram == .ballSpeed {
                ballSpeedExplanationSheet
            } else if diagram == .launchAngle {
                launchAngleExplanationSheet
            } else if diagram == .launchDirection {
                launchDirectionExplanationSheet
            } else if diagram == .spinRate {
                spinRateExplanationSheet
            } else if diagram == .spinAxis {
                spinAxisExplanationSheet
            } else if diagram == .temperature {
                temperatureExplanationSheet
            } else if diagram == .humidity {
                humidityExplanationSheet
            } else if diagram == .tailwind || diagram == .crosswind {
                windExplanationSheet
            } else if diagram == .elevationChange {
                elevationExplanationSheet
            } else {
                explanationSheet
            }
        }
    }

    private var formattedValue: String {
        let display = kind.displayValue(metric: metricValue, system: unitSystem)
        return String(format: "%.\(decimalPlaces)f %@", display, kind.unitSuffix(system: unitSystem))
    }

    private var numericString: String {
        let display = kind.displayValue(metric: metricValue, system: unitSystem)
        return String(format: "%.\(decimalPlaces)f", display)
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section(title) {
                    TextField(kind.unitSuffix(system: unitSystem), text: $draftValue)
                        .keyboardType(.decimalPad)
                }
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .navigationTitle("Edit \(title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditingValue = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commitDraft()
                        isEditingValue = false
                    }
                }
            }
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(PureLineStyle.accent)
        }
        .presentationDetents([.height(220)])
    }

    private var explanationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if diagram == .ballSpeed {
                    Image("ballspeed")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 155)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
                Text(explanation)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showExplanation = false }
                }
            }
        }
        .presentationDetents([.height(300)])
    }

    private var ballSpeedExplanationSheet: some View {
        imageExplanationSheet(imageName: "ballspeed", sheetHeight: 420)
    }

    private var launchAngleExplanationSheet: some View {
        imageExplanationSheet(imageName: "launchangle", sheetHeight: 420)
    }

    private var launchDirectionExplanationSheet: some View {
        imageExplanationSheet(imageName: "launchdirection", sheetHeight: 420)
    }

    private var spinRateExplanationSheet: some View {
        imageExplanationSheet(imageName: "spinrate", sheetHeight: 380)
    }

    private var spinAxisExplanationSheet: some View {
        imageExplanationSheet(imageName: "spinaxis", sheetHeight: 380)
    }

    private var temperatureExplanationSheet: some View {
        imageExplanationSheet(imageName: "temperature", sheetHeight: 380)
    }

    private var humidityExplanationSheet: some View {
        imageExplanationSheet(imageName: "humidity", sheetHeight: 380)
    }

    private var windExplanationSheet: some View {
        imageExplanationSheet(imageName: "wind", sheetHeight: 380)
    }

    private var elevationExplanationSheet: some View {
        imageExplanationSheet(imageName: "elevation", sheetHeight: 380)
    }

    private func imageExplanationSheet(imageName: String, sheetHeight: CGFloat) -> some View {
        NavigationStack {
            ZStack {
                PureLineStyle.canvas
                    .ignoresSafeArea()

                InfoImagePanel(imageName: imageName, explanation: explanation)
                    .padding()
            }
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
        .presentationDetents([.height(sheetHeight)])
    }

    private func commitDraft() {
        guard let displayValue = Double(draftValue), displayRange.contains(displayValue) else { return }
        metricValue = kind.metricValue(display: displayValue, system: unitSystem)
    }

    private var displayRange: ClosedRange<Double> {
        let lower = kind.displayValue(metric: metricRange.lowerBound, system: unitSystem)
        let upper = kind.displayValue(metric: metricRange.upperBound, system: unitSystem)
        return lower < upper ? lower...upper : upper...lower
    }

    private var displayBinding: Binding<Double> {
        Binding(
            get: { kind.displayValue(metric: metricValue, system: unitSystem) },
            set: { metricValue = kind.metricValue(display: $0, system: unitSystem) }
        )
    }
}

struct InfoImagePanel: View {
    let imageName: String
    let explanation: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipped()
                .accessibilityHidden(true)

            Text(explanation)
                .font(.body)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.black.opacity(0.62))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
