import SwiftUI
import Charts

/// Same gap-aware renderer for the on-map preview and expandable inspection sheet.
struct TerrainProfileChart: View {
    let profile: TerrainProfile
    let unit: DistanceUnit
    @Binding var selectedDistance: Double?
    var height: CGFloat = 260
    // Built once per profile so drag-driven redraws don't rescan every sample.
    private let runs: [[TerrainSample]]
    private let domain: ClosedRange<Double>

    init(profile: TerrainProfile, unit: DistanceUnit, selectedDistance: Binding<Double?>, height: CGFloat = 260) {
        self.profile = profile
        self.unit = unit
        _selectedDistance = selectedDistance
        self.height = height
        runs = Self.displayRuns(profile.samples)
        let toUnit: (Double) -> Double = { unit == .meters ? $0 : $0 / 0.9144 }
        let heights = profile.samples.compactMap(\.elevationMeters).filter(\.isFinite).map(toUnit)
        let low = heights.min() ?? 0, high = heights.max() ?? toUnit(1)
        let pad = max(toUnit(1), (high - low) * 0.1)
        domain = (low - pad)...(high + pad)
    }

    /// Splits at missing heights, then keeps each bucket's lowest and highest sample (display only).
    static func displayRuns(_ samples: [TerrainSample], buckets: Int = 200) -> [[TerrainSample]] {
        var runs: [[TerrainSample]] = [], run: [TerrainSample] = []
        for sample in samples {
            if let h = sample.elevationMeters, h.isFinite { run.append(sample) }
            else if !run.isEmpty { runs.append(run); run = [] }
        }
        if !run.isEmpty { runs.append(run) }
        guard let first = samples.first?.distanceMeters, let last = samples.last?.distanceMeters,
              last > first, buckets > 0 else { return runs }
        let width = (last - first) / Double(buckets)
        return runs.map { decimated($0, origin: first, bucketWidth: width) }
    }

    private static func decimated(_ run: [TerrainSample], origin: Double, bucketWidth: Double) -> [TerrainSample] {
        guard run.count > 2, let head = run.first, let tail = run.last else { return run }
        var result = [head]
        var bucket = Int.min
        var low = head, high = head
        func flush() {
            guard bucket != Int.min else { return }
            for sample in low.distanceMeters <= high.distanceMeters ? [low, high] : [high, low]
            where sample.distanceMeters != result.last?.distanceMeters {
                result.append(sample)
            }
        }
        for sample in run.dropFirst().dropLast() {
            let index = Int((sample.distanceMeters - origin) / bucketWidth)
            if index != bucket {
                flush()
                bucket = index; low = sample; high = sample
            } else if let h = sample.elevationMeters {
                if h < low.elevationMeters ?? h { low = sample }
                if h > high.elevationMeters ?? h { high = sample }
            }
        }
        flush()
        if result.last?.distanceMeters != tail.distanceMeters { result.append(tail) }
        return result
    }

    private func value(_ m: Double) -> Double { unit == .meters ? m : m / 0.9144 }
    var body: some View {
        Chart {
            ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                ForEach(run) { sample in
                    if let elevation = sample.elevationMeters {
                        AreaMark(x: .value(L("Distance"), value(sample.distanceMeters)),
                                 yStart: .value(L("Baseline"), domain.lowerBound),
                                 yEnd: .value(L("Elevation"), value(elevation)), series: .value(L("Run"), index))
                            .foregroundStyle(PureLineStyle.accent.opacity(0.12))
                            .interpolationMethod(.linear)
                        LineMark(x: .value(L("Distance"), value(sample.distanceMeters)),
                                 y: .value(L("Elevation"), value(elevation)), series: .value(L("Run"), index))
                            .foregroundStyle(PureLineStyle.accent)
                            .interpolationMethod(.linear)
                        if run.count == 1 {
                            PointMark(x: .value(L("Distance"), value(sample.distanceMeters)), y: .value(L("Elevation"), value(elevation)))
                                .foregroundStyle(PureLineStyle.accent)
                        }
                    }
                }
            }
            if let selectedDistance {
                RuleMark(x: .value(L("Inspection"), selectedDistance))
                    .foregroundStyle(PureLineStyle.ink)
            }
        }
        .chartXScale(domain: 0...max(value(profile.distanceMeters), value(1)))
        .chartYScale(domain: domain)
        .chartLegend(.hidden)
        .chartXAxisLabel(height > 100 ? L("Horizontal distance (%@)", "\(unit.symbol)") : "")
        .chartYAxisLabel(height > 100 ? L("Terrain elevation (%@)", "\(unit.symbol)") : "")
        .chartXSelection(value: $selectedDistance)
        .frame(height: height)
        .accessibilityLabel("Terrain profile; independently fitted vertical scale, gaps are unavailable heights")
        .accessibilityValue("\(unit.format(profile.distanceMeters)) horizontal distance")
    }
}