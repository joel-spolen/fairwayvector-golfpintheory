import SwiftUI

enum PracticeDestination: String, CaseIterable {
    case trajectory
    case wedge
}

struct PracticeView: View {
    @Binding var destination: PracticeDestination
    @ObservedObject var trajectoryModel: TrajectoryCalculatorViewModel
    var onHome: () -> Void = {}

    var body: some View {
        Group {
            if !ProStore.shared.isPro {
                VStack(spacing: 0) {
                    PureLineHomeButton(onHome: onHome)
                    switch destination {
                    case .trajectory:
                        ProToolPreview(
                            title: L("Trajectory"),
                            summary: L("Personalized club recommendations and realistic shot trajectories for your game."),
                            features: [
                                ("slider.horizontal.3", L("Choose a club profile or adjust ball speed, launch, spin, wind, and course conditions manually.")),
                                ("function", L("Golf PinTheory simulates the ball flight and fine-tunes it with real shot data.")),
                                ("chart.xyaxis.line", L("Review carry, apex, landing data, and the side and top-down flight paths.")),
                            ]
                        ) { TrajectoryExample() }
                    case .wedge:
                        ProToolPreview(
                            title: L("Wedge Matrix"),
                            summary: L("Your distances. Every swing."),
                            features: [
                                ("square.grid.3x3", L("Compare carry distances across swing lengths and trajectories.")),
                                ("flag", L("Set the distance, green elevation and pin position to find a club and swing.")),
                                ("scope", L("Inside your wedge range, suggests the wedge, trajectory and swing length for the shot.")),
                            ]
                        ) { WedgeMatrixExample() }
                    }
                }
                .background(PureLineStyle.canvas)
            } else {
                switch destination {
                case .trajectory:
                    TrajectoryRootView(viewModel: trajectoryModel, onHome: onHome)
                case .wedge:
                    WedgeMatrixView(onHome: onHome)
                }
            }
        }
        .tint(PureLineStyle.accent)
    }
}

/// A simulated mid-iron shot so free users see real output from the flight model.
private struct TrajectoryExample: View {
    private static let shot = FlightSimulator.simulateShot(
        ShotInputs(ballSpeedMps: 49, launchAngleDeg: 18, launchDirectionDeg: 0, spinRateRpm: 6_500, spinAxisDeg: 0))
    @StateObject private var units = UnitPreferences()

    var body: some View {
        let system = units.unitSystem(for: .distance)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                stat(L("Carry distance"), Units.formattedDistance(meters: Self.shot.levelGroundCarryM ?? 0, system: system))
                Spacer()
                stat(L("Apex"), Units.formattedHeight(meters: Self.shot.apexHeightM, system: system))
                Spacer()
                stat(L("Landing angle"), String(format: "%.0f°", Self.shot.landingAngleDeg ?? 0))
            }
            LiveFlightPreview(trajectory: Self.shot.trajectory)
                .frame(height: 150)
        }
        .pureLineCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Example flight path"))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(PureLineStyle.muted)
            Text(value).font(.headline).foregroundStyle(PureLineStyle.ink).monospacedDigit()
        }
    }
}

private struct WedgeMatrixExample: View {
    @AppStorage("wedgeMatrix.distanceUnit", store: .standard) private var unit = WedgeDistanceUnit.yards.rawValue

    var body: some View {
        WedgeMatrixCard(wedges: Wedge.defaults.filter(\.isInBag), trajectory: .stock,
                        unit: WedgeDistanceUnit(rawValue: unit) ?? .yards)
    }
}
