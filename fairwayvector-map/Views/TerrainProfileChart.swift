import SwiftUI
import Charts

/// Same gap-aware renderer for the on-map preview and expandable inspection sheet.
struct TerrainProfileChart: View {
    let profile: TerrainProfile
    let unit: DistanceUnit
    @Binding var selectedDistance: Double?
    var height: CGFloat = 260

    private var runs: [[TerrainSample]] {
        var result: [[TerrainSample]] = [], run: [TerrainSample] = []
        for sample in profile.samples {
            if let h = sample.elevationMeters, h.isFinite { run.append(sample) }
            else if !run.isEmpty { result.append(run); run = [] }
        }
        if !run.isEmpty { result.append(run) }
        return result
    }
    private func value(_ m: Double) -> Double { unit == .meters ? m : m / 0.9144 }
    private var domain: ClosedRange<Double> {
        let heights = profile.samples.compactMap(\.elevationMeters).map(value)
        let low = heights.min() ?? 0, high = heights.max() ?? value(1)
        let pad = max(value(1), (high - low) * 0.1)
        return (low - pad)...(high + pad)
    }
    var body: some View {
        Chart {
            ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                ForEach(run) { sample in
                    if let elevation = sample.elevationMeters {
                        AreaMark(x: .value("Distance", value(sample.distanceMeters)),
                                 yStart: .value("Baseline", domain.lowerBound),
                                 yEnd: .value("Elevation", value(elevation)), series: .value("Run", index))
                            .foregroundStyle(PureLineStyle.accent.opacity(0.12))
                            .interpolationMethod(.linear)
                        LineMark(x: .value("Distance", value(sample.distanceMeters)),
                                 y: .value("Elevation", value(elevation)), series: .value("Run", index))
                            .foregroundStyle(PureLineStyle.accent)
                            .interpolationMethod(.linear)
                        if run.count == 1 {
                            PointMark(x: .value("Distance", value(sample.distanceMeters)), y: .value("Elevation", value(elevation)))
                                .foregroundStyle(PureLineStyle.accent)
                        }
                    }
                }
            }
            if let selectedDistance {
                RuleMark(x: .value("Inspection", selectedDistance))
                    .foregroundStyle(PureLineStyle.ink)
            }
        }
        .chartXScale(domain: 0...max(value(profile.distanceMeters), value(1)))
        .chartYScale(domain: domain)
        .chartLegend(.hidden)
        .chartXAxisLabel(height > 100 ? "Horizontal distance (\(unit.symbol))" : "")
        .chartYAxisLabel(height > 100 ? "Terrain elevation (\(unit.symbol))" : "")
        .chartXSelection(value: $selectedDistance)
        .frame(height: height)
        .accessibilityLabel("Terrain profile; independently fitted vertical scale, gaps are unavailable heights")
        .accessibilityValue("\(unit.format(profile.distanceMeters)) horizontal distance")
    }
}