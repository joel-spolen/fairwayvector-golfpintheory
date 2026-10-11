import SwiftUI
import Charts

/// Inspection is local-only. The parent owns committed acquisition and map selection.
struct HoleElevationProfileView: View {
    let store: TerrainElevationStore
    let holeNumber: Int
    let unit: DistanceUnit
    let usesGPS: Bool
    @Binding var inspectionPoint: GeoPoint?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDistance: Double?

    private var mode: TerrainProfileMode { store.mode }

    private struct ValidRun: Identifiable {
        let id: Int
        let samples: [TerrainSample]
    }

    private var profile: TerrainProfile? {
        switch mode {
        case .hole: store.snapshot.holeProfile
        case .shot: store.snapshot.shotProfile
        }
    }

    private var startLabel: String {
        mode == .hole ? "Tee" : "Position"
    }

    private var endLabel: String {
        mode == .hole ? "Hole endpoint" : "Target"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Profile", selection: Binding(get: { store.mode }, set: { store.mode = $0 })) {
                        ForEach(TerrainProfileMode.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(PureLineStyle.accent)

                    if let profile, !validRuns(profile).isEmpty {
                        profileContent(profile)
                    } else if store.isLoading {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView("Loading terrain profile…")
                            if let message = store.statusMessage {
                                Text(message).font(.subheadline).foregroundStyle(PureLineStyle.muted)
                            }
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Terrain unavailable", systemImage: "mountain.2")
                        } description: {
                            Text(store.statusMessage ?? "No terrain elevations are available for this \(mode.rawValue.lowercased()) profile.")
                        }
                    }

                }
                .padding()
            }
            .background(PureLineStyle.canvas)
            .navigationTitle("Hole \(holeNumber) elevation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        resetInspection()
                        dismiss()
                    }
                }
            }
        }
        .tint(PureLineStyle.accent)
        .onChange(of: selectedDistance) { _, _ in
            inspectionPoint = inspectedSample?.point
        }
        .onChange(of: mode) { _, _ in resetInspection() }
        .onChange(of: profile?.samples) { _, _ in resetInspection() }
        .onChange(of: holeNumber) { _, _ in resetInspection() }
        .onChange(of: unit) { _, _ in resetInspection() }
        .onChange(of: usesGPS) { _, _ in resetInspection() }
        .onChange(of: store.isLoading) { _, loading in
            if loading { resetInspection() }
        }
        .onAppear { resetInspection() }
        .onDisappear { resetInspection() }
    }

    private func profileContent(_ profile: TerrainProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(startLabel) → \(endLabel)").font(.headline)
                Text("\(unit.format(profile.distanceMeters)) horizontal distance")
                    .font(.subheadline).foregroundStyle(PureLineStyle.muted)
            }

            TerrainProfileChart(profile: profile, unit: unit, selectedDistance: $selectedDistance)

            if let sample = inspectedSample {
                VStack(alignment: .leading, spacing: 4) {
                    Text("At \(unit.format(sample.distanceMeters))").font(.subheadline.bold())
                    Text("Terrain elevation: \(heightText(sample.elevationMeters))")
                        .font(.subheadline).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Touch and drag the chart to inspect terrain and show its position on the map.")
                    .font(.footnote).foregroundStyle(PureLineStyle.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                endpointRow(startLabel, sample: profile.samples.first)
                endpointRow(endLabel, sample: profile.samples.last)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Elevation change")
                    Spacer()
                    Text(deltaText(profile.elevationChangeMeters))
                        .fontWeight(.semibold).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            .font(.subheadline)
        }
    }

    private func endpointRow(_ title: String, sample: TerrainSample?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(heightText(sample?.elevationMeters)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// Keep the actual sample distance as a Double; DistanceUnit.value rounds to Int.
    private func displayValue(_ meters: Double) -> Double {
        unit == .meters ? meters : meters / 0.9144
    }

    private func validElevation(_ sample: TerrainSample) -> Double? {
        guard let elevation = sample.elevationMeters, elevation.isFinite,
              sample.distanceMeters.isFinite else { return nil }
        return elevation
    }

    private func validRuns(_ profile: TerrainProfile) -> [ValidRun] {
        var runs: [ValidRun] = []
        var current: [TerrainSample] = []
        for sample in profile.samples {
            if validElevation(sample) != nil {
                current.append(sample)
            } else if !current.isEmpty {
                runs.append(ValidRun(id: runs.count, samples: current))
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty { runs.append(ValidRun(id: runs.count, samples: current)) }
        return runs
    }

    private func elevationDomain(_ runs: [ValidRun]) -> ClosedRange<Double> {
        let heights = runs.flatMap(\.samples).compactMap { validElevation($0).map(displayValue) }
        guard let low = heights.min(), let high = heights.max() else { return 0...displayValue(1) }
        let padding = max((high - low) * 0.1, displayValue(1))
        return (low - padding)...(high + padding)
    }

    /// Binary search includes missing-height samples so inspection never hides a gap.
    private var inspectedSample: TerrainSample? {
        guard let selectedDistance, selectedDistance.isFinite,
              let samples = profile?.samples, !samples.isEmpty else { return nil }
        let meters = unit == .meters ? selectedDistance : selectedDistance * 0.9144
        var low = 0
        var high = samples.count
        while low < high {
            let middle = low + (high - low) / 2
            if samples[middle].distanceMeters < meters { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return samples[0] }
        if low == samples.count { return samples[samples.count - 1] }
        let previous = samples[low - 1]
        let next = samples[low]
        return meters - previous.distanceMeters <= next.distanceMeters - meters ? previous : next
    }

    private func heightText(_ meters: Double?) -> String {
        guard let meters, meters.isFinite else { return "Unavailable" }
        return "\(displayValue(meters).formatted(.number.precision(.fractionLength(1)))) \(unit.symbol)"
    }

    private func deltaText(_ meters: Double?) -> String {
        guard let meters, meters.isFinite else { return "Unavailable" }
        let direction = meters > 0 ? "uphill" : (meters < 0 ? "downhill" : "level")
        let sign = meters > 0 ? "+" : (meters < 0 ? "−" : "")
        return "\(sign)\(heightText(abs(meters))) · \(direction)"
    }

    private func chartSummary(_ profile: TerrainProfile) -> String {
        let available = profile.samples.filter { validElevation($0) != nil }.count
        return "Horizontal distance \(unit.format(profile.distanceMeters)). \(startLabel) elevation \(heightText(profile.samples.first?.elevationMeters)). \(endLabel) elevation \(heightText(profile.samples.last?.elevationMeters)). Elevation change \(deltaText(profile.elevationChangeMeters)). \(available) of \(profile.samples.count) samples available. Missing terrain is shown as gaps. Vertical and horizontal scales differ."
    }

    private func resetInspection() {
        selectedDistance = nil
        inspectionPoint = nil
    }
}