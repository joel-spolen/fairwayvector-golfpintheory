import SwiftUI

/// Displays the final hybrid (Physics V1.1 + ML residual) scalar outputs for a shot.
struct TrajectoryResultsView: View {
    let prediction: HybridPrediction
    let unitPreferences: UnitPreferences
    var showsEstimationInfo = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Results")
                .font(.headline)
                .foregroundStyle(PureLineStyle.ink)

            ResultCard(
                title: L("Carry Distance"),
                value: Units.formattedDistance(meters: prediction.hybrid["carry_m"] ?? 0, system: unitPreferences.unitSystem(for: .distance)),
                prominence: .primary
            )
            .accessibilityLabel("Carry distance")

            ResultCard(
                title: L("Apex"),
                value: Units.formattedHeight(meters: prediction.hybrid["apex_m"] ?? 0, system: unitPreferences.unitSystem(for: .distance)),
                prominence: .secondary
            )
            .accessibilityLabel("Apex height")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ResultCard(title: L("Flight Time"), value: String(format: "%.2f s", prediction.hybrid["flight_time_s"] ?? 0), prominence: .compact)
                ResultCard(title: L("Landing Angle"), value: String(format: "%.1f\u{00B0}", prediction.hybrid["landing_angle_deg"] ?? 0), prominence: .compact)
                ResultCard(title: L("Landing Speed"), value: Units.formattedSpeed(mps: prediction.hybrid["landing_speed_mps"] ?? 0, system: unitPreferences.unitSystem(for: .landingSpeed)), prominence: .compact)
            }

            if showsEstimationInfo {
                Label(
                    L("Headline values are estimated using the flight model and calibration corrections. They may differ from real-world flight because conditions and measurements can vary."),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .pureLineCard()
        .accessibilityIdentifier("trajectory-results-card")
    }
}

private struct ResultCard: View {
    let title: String
    let value: String
    let prominence: Prominence

    enum Prominence {
        case primary
        case secondary
        case compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(prominence == .primary ? .largeTitle.bold() : prominence == .secondary ? .title2.bold() : .subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(prominence == .compact ? 10 : 14)
        .background(
            prominence == .primary
                ? PureLineStyle.accent.opacity(0.10)
                : prominence == .secondary
                    ? PureLineStyle.line.opacity(0.55)
                    : PureLineStyle.canvas,
            in: RoundedRectangle(cornerRadius: 16)
        )
        .foregroundStyle(PureLineStyle.ink)
        .accessibilityElement(children: .combine)
        .accessibilityValue(value)
    }
}
