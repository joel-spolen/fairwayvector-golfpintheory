import SwiftUI
import Charts

/// Chart coordinates increase right/up. Physics x is forward, y is golfer's right.
nonisolated enum TrajectoryChartGeometry {
    static func topDown(downrange: Double, lateral: Double) -> (x: Double, y: Double) {
        (x: lateral, y: downrange)
    }

    /// Clockwise screen rotation from an upward arrow; inputs are blowing TO.
    static func windRotation(tail: Double, right: Double) -> Double {
        atan2(right, tail) * 180 / .pi
    }
}

/// Side-view (downrange vs height) and top-down (downrange vs lateral) flight charts.
struct TrajectoryChartView: View {
    let trajectory: GolfTrajectory
    let unitPreferences: UnitPreferences
    var targetDistanceM: Double? = nil
    var targetElevationM: Double? = nil
    var capturedWind: (tail: Double, right: Double)? = nil
    var shotBearingDeg: Double? = nil

    private var unitSystem: UnitSystem { unitPreferences.unitSystem(for: .distance) }

    private struct Point: Identifiable {
        let id: Int
        let downrange: Double
        let value: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Modeled Physics Flight Path")
                    .font(.headline)
                Text("The chart shows the modeled path. Values above include calibration corrections.")
                    .font(.caption)
                    .foregroundStyle(PureLineStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            chartSection(title: "Side View (Height)", points: sideViewPoints, valueLabel: "Height")
            topDownSection
        }
        .pureLineCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Golf ball trajectory charts")
        .accessibilityHint("The side view shows height and the top-down view shows lateral curvature. \(chartSummary)")
    }

    private var sideViewPoints: [Point] {
        zip(trajectory.xM, trajectory.zM).enumerated().map { index, pair in
            Point(id: index, downrange: displayDistance(pair.0), value: displayDistance(pair.1))
        }
    }

    private var topDownPoints: [Point] {
        zip(trajectory.xM, trajectory.yM).enumerated().map { index, pair in
            Point(id: index, downrange: displayDistance(pair.0), value: displayDistance(pair.1))
        }
    }

    private func displayDistance(_ meters: Double) -> Double {
        unitSystem == .imperial ? Units.yardsFromMeters(meters) : meters
    }

    private var distanceUnitLabel: String {
        unitSystem == .imperial ? "yd" : "m"
    }

    private var topDownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top-Down View (Curvature)").font(.subheadline.bold())
            if let capturedWind {
                let speed = hypot(capturedWind.tail, capturedWind.right)
                HStack(spacing: 10) {
                    Image(systemName: speed < 1e-10 ? "wind" : "arrow.up")
                        .rotationEffect(.degrees(speed < 1e-10 ? 0 : TrajectoryChartGeometry.windRotation(
                            tail: capturedWind.tail, right: capturedWind.right)))
                        .font(.title3.bold())
                        .foregroundStyle(PureLineStyle.accent)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    Text(String(format: "Blowing direction · captured wind %.1f m/s", speed))
                        .font(.caption.weight(.semibold))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Captured wind blowing direction")
                .accessibilityValue(String(format: "%.1f m/s; %.1f toward target, %+.1f toward right", speed, capturedWind.tail, capturedWind.right))
            }
            let points = topDownPoints
            Chart {
                RuleMark(x: .value("Target line", 0))
                    .foregroundStyle(FairwayVectorColors.slate.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                ForEach(points) { point in
                    let position = TrajectoryChartGeometry.topDown(downrange: point.downrange, lateral: point.value)
                    LineMark(x: .value("Lateral", position.x), y: .value("Downrange", position.y))
                        .foregroundStyle(FairwayVectorColors.flightBlue)
                    if point.id == points.last?.id {
                        PointMark(x: .value("Lateral", position.x), y: .value("Downrange", position.y))
                            .foregroundStyle(FairwayVectorColors.orange)
                    }
                }
                if let targetDistanceM {
                    let target = TrajectoryChartGeometry.topDown(downrange: displayDistance(targetDistanceM), lateral: 0)
                    RuleMark(y: .value("Target distance", target.y))
                        .foregroundStyle(FairwayVectorColors.gold)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    PointMark(x: .value("Lateral", target.x), y: .value("Downrange", target.y))
                        .foregroundStyle(FairwayVectorColors.gold)
                        .annotation(position: .top) { Text("Target").font(.caption2) }
                }
            }
            // Ascending domains: physical right is screen-right; forward is up.
            // Symmetric lateral limits keep the golfer/target line centered.
            .chartXScale(domain: -lateralLimit...lateralLimit)
            .chartYScale(domain: downrangeDomain)
            .chartXAxisLabel("Lateral · − left / + right (\(distanceUnitLabel))")
            .chartYAxisLabel("Downrange (\(distanceUnitLabel))")
            .frame(height: 240)
            .accessibilityLabel("Top-down view, forward up and golfer's right to the right")
            .accessibilityValue(topDownSummary)
            Text("Curvature includes wind and launch spin.")
                .font(.caption).foregroundStyle(PureLineStyle.muted)
        }
    }

    private var lateralLimit: Double {
        max(displayDistance(5), (topDownPoints.map { abs($0.value) }.max() ?? 0) * 1.15)
    }

    private var downrangeDomain: ClosedRange<Double> {
        let minimum = min(0, topDownPoints.map(\.downrange).min() ?? 0)
        let maximum = max(displayDistance(1), topDownPoints.map(\.downrange).max() ?? 0,
                          displayDistance(targetDistanceM ?? 0))
        return minimum...(maximum * 1.1)
    }

    private func bearingLabel(_ degrees: Double) -> String {
        let bearing = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return String(format: "%@ %.1f°", points[Int((bearing / 45).rounded()) % points.count], bearing)
    }

    @ViewBuilder
    private func chartSection(title: String, points: [Point], valueLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
            Chart(points) { point in
                LineMark(
                    x: .value("Downrange", point.downrange),
                    y: .value(valueLabel, point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(FairwayVectorColors.flightBlue)
                if point.id == points.last?.id {
                    PointMark(
                        x: .value("Downrange", point.downrange),
                        y: .value(valueLabel, point.value)
                    )
                    .foregroundStyle(FairwayVectorColors.orange)
                }
                if point.id == points.first?.id, let targetDistanceM {
                    RuleMark(x: .value("Target distance", displayDistance(targetDistanceM)))
                        .foregroundStyle(FairwayVectorColors.gold)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    if valueLabel == "Height", let targetElevationM {
                        PointMark(x: .value("Target distance", displayDistance(targetDistanceM)),
                                  y: .value("Target elevation", displayDistance(targetElevationM)))
                            .foregroundStyle(FairwayVectorColors.gold)
                    }
                }
            }
            .chartXAxisLabel("Downrange (\(distanceUnitLabel))")
            .chartYAxisLabel("\(valueLabel) (\(distanceUnitLabel))")
            .frame(height: 160)
            .accessibilityLabel(title)
            .accessibilityValue(valueLabel == "Height" ? sideViewSummary : topDownSummary)
        }
    }

    private var chartSummary: String {
        "Estimated carry is \(formattedDistance(lastDownrange)) with an apex of \(formattedDistance(apexHeight)). \(lateralSummary)"
    }

    private var sideViewSummary: String {
        "Modeled physics path. Estimated carry is \(formattedDistance(lastDownrange)) and apex is \(formattedDistance(apexHeight))."
    }

    private var topDownSummary: String {
        "Modeled physics path. At landing, the ball finishes \(formattedDistance(abs(lastLateral))) \(lastLateralDirection) of the target line."
    }

    private var lastDownrange: Double {
        trajectory.xM.last ?? 0
    }

    private var apexHeight: Double {
        trajectory.zM.max() ?? 0
    }

    private var lastLateral: Double {
        trajectory.yM.last ?? 0
    }

    private var lastLateralDirection: String {
        if abs(lastLateral) < 0.01 {
            return "on the target line"
        }
        return lastLateral > 0 ? "right" : "left"
    }

    private var lateralSummary: String {
        if abs(lastLateral) < 0.01 {
            return "The ball finishes on the target line."
        }
        return "At landing, the ball finishes \(formattedDistance(abs(lastLateral))) \(lastLateralDirection) of the target line."
    }

    private func formattedDistance(_ meters: Double) -> String {
        Units.formattedDistance(meters: meters, system: unitSystem)
    }
}
