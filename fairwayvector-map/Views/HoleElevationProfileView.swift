import SwiftUI
import Charts

/// Inspection is local-only. The parent owns committed acquisition and map selection.
struct HoleElevationProfileView: View {
    let store: TerrainElevationStore
    let holeNumber: Int
    let unit: DistanceUnit
    let usesGPS: Bool
    @Binding var inspectionPoint: GeoPoint?
    var retryMessage: String = "Saved terrain is reused. Uncovered paths may spend calls; reservations and provider backoff are retained."
    var onRetry: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDistance: Double?
    @State private var isConfirmingRetry = false

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
        mode == .hole ? "Tee" : (store.committedRequest?.originLabel ?? "Captured position")
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
                        if store.isLoading { ProgressView("Loading uncovered terrain…") }
                        if let message = store.statusMessage {
                            Label(message, systemImage: "info.circle").font(.footnote).foregroundStyle(PureLineStyle.muted)
                        }
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

                    if store.shotPending { Text("Target is being moved. Release to commit its terrain.").font(.footnote) }
                    // Show both pipelines' errors even when inspecting the other chart.
                    if let message = store.holeMessage { Label("Hole: \(message)", systemImage: "info.circle").font(.footnote) }
                    if let message = store.shotMessage { Label("Shot: \(message)", systemImage: "info.circle").font(.footnote) }
                    if DevelopmentAPIConfiguration.current.gpxz == .live, let quota = store.quota {
                        Text("GPXZ local budget: \(quota.used)/100 used · \(quota.remaining) remaining · \(store.plannedCalls) uncovered spans planned · \(quota.month) UTC.").font(.footnote)
                    }
                    if onRetry != nil {
                        Button("Retry / refresh terrain", systemImage: "arrow.clockwise") { isConfirmingRetry = true }
                            .disabled(store.isHoleLoading || store.isShotLoading || store.shotPending)
                            .accessibilityHint("Asks for confirmation; never resets used calls or provider backoff")
                    }
                    sourceDetails(store.metadata, sourceProfile: profile,
                                  title: mode == .hole ? "Hole terrain source" : "Origin → target terrain source")
                    if mode == .shot, let nextProfile = store.snapshot.targetToFlagProfile {
                        sourceDetails(nextProfile.metadata, sourceProfile: nextProfile,
                                      title: "Target → flag terrain source")
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
        .confirmationDialog("Retry terrain requests?", isPresented: $isConfirmingRetry, titleVisibility: .visible) {
            Button("Retry terrain") { onRetry?() }
            Button("Cancel", role: .cancel) {}
        } message: { Text(retryMessage) }
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

            if mode == .shot && store.committedRequest?.isSimulatedOrigin == true {
                Text("This profile begins at a simulated position rather than device GPS.")
                    .font(.footnote).foregroundStyle(PureLineStyle.muted)
            } else if mode == .shot && !usesGPS {
                Text("The committed shot starts at the captured tee fallback, not your live GPS position. Its endpoint is the selected target.")
                    .font(.footnote).foregroundStyle(PureLineStyle.muted)
            } else if mode == .shot {
                Text("The committed shot runs from your captured GPS position to the selected target, not necessarily the flag. Incoming GPS fixes do not update this origin.")
                    .font(.footnote).foregroundStyle(PureLineStyle.muted)
            }
            if profile.isStraightLine {
                Text("Straight-line terrain cross-section; this does not represent a mapped dogleg or the ball’s flight.")
                    .font(.footnote).foregroundStyle(PureLineStyle.muted)
            }
            if profile.samples.contains(where: { validElevation($0) == nil }) {
                Text("Gaps indicate unavailable terrain. Missing heights are not interpolated or connected.")
                    .font(.footnote).foregroundStyle(PureLineStyle.muted)
            }
            Text("Vertical scale is fitted independently of horizontal distance. Terrain relief may be vertically exaggerated; this is not a true-scale slope diagram.")
                .font(.footnote).foregroundStyle(PureLineStyle.muted)
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

    private func sourceDetails(_ records: [TerrainProvenance], sourceProfile: TerrainProfile?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if !records.contains(where: \.isSynthetic) && DevelopmentAPIConfiguration.current.gpxz == .live {
                Link("Elevation profiles by GPXZ", destination: URL(string: "https://www.gpxz.io/")!)
                LabeledContent("Coordinates / heights", value: "WGS84 / EGM2008")
                if let profile = sourceProfile {
                    LabeledContent("Displayed maximum sample interval", value: "\(profile.maximumSpacingMeters.formatted(.number.precision(.fractionLength(2)))) m")
                    if profile.samples.contains(where: \.locallyInterpolated) {
                        Text("Subpath boundaries and bends may be interpolated locally along the original provider path. Bracketing source provenance is retained.")
                    }
                }
                if let low = records.map(\.resolutionMeters).min(), let high = records.map(\.resolutionMeters).max() {
                    LabeledContent("Actual source resolution", value: "\(low.formatted())–\(high.formatted()) m")
                }
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Returned source: \(record.dataSource)").fontWeight(.semibold)
                        Link("GPXZ catalogue — look up this source’s credits and licence", destination: URL(string: "https://api.gpxz.io/v1/elevation/sources")!)
                        Text("Captured: \(record.captureDateMin ?? "not supplied") – \(record.captureDateMax ?? "not supplied")")
                        Text("Dataset: \(record.datasetVersion ?? "not supplied") · Saved \(record.fetchedAt.formatted())")
                        Text("Provider interpolation: \(record.interpolation) · Resolution \(record.resolutionMeters.formatted()) m")
                        Text("Original provider sample interval: \(record.providerSampleIntervalMeters.formatted(.number.precision(.fractionLength(2)))) m (separate from source resolution)")
                    }
                }
                Text("Only source identifiers and sampling provenance are stored here. Source-specific attribution records and full licence texts have not been downloaded or bundled. These links open GPXZ’s public catalogue; review the matching entry before redistributing data.")
                if let quota = store.quota { Text("Local budget: \(quota.used)/100 used; \(quota.remaining) remaining for \(quota.month) UTC. This is not cross-device account authority.") }
                Text("Sampling spacing is not source resolution or guaranteed accuracy. Profiles may use coarser source data. GPS error and capture dates affect the result; these are terrain heights, not phone altitude, green-reading data, or plays-like advice.")
                Text("A committed profile may send its path coordinates, including your captured GPS origin, to GPXZ. Saved profiles have no expiry or automatic retry. Refresh is cache-first.")
                    .foregroundStyle(PureLineStyle.muted)
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
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