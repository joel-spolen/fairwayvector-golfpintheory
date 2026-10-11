import SwiftUI

struct CourseWeatherCard: View {
    let location: GeoPoint
    let store: CourseWeatherStore
    var mapHeading: Double = 0
    var compact = false
    @State private var isShowingDetails = false

    var body: some View {
        Button { isShowingDetails = true } label: {
            labelContent
            .font(.caption)
            .padding(compact ? 6 : 10)
            .frame(maxWidth: compact ? nil : .infinity)
            .frame(width: compact ? 78 : nil)
            .frame(minHeight: compact ? 64 : 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(PureLineStyle.ink)
        .background(PureLineStyle.canvas.opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
        // This is the sole automatic load. The detail sheet has no task/onAppear fetch.
        .task(id: locationKey) {
            await store.load(for: location)
        }
        .accessibilityLabel("Course weather details")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Opens all conditions, source time, cached status, provider errors and manual refresh")
        .accessibilityIdentifier("course-weather-summary")
        .sheet(isPresented: $isShowingDetails) {
            CourseWeatherDetail(location: location, store: store)
        }
    }

    @ViewBuilder
    private var labelContent: some View {
        if compact {
            compactLabel
        } else {
            expandedLabel
        }
    }

    private var compactLabel: some View {
        VStack(spacing: 3) {
            Image(systemName: "cloud.sun")
                .font(.body.weight(.medium))
                .foregroundStyle(PureLineStyle.accent)
            if let weather = store.weather(for: location) {
                Text(compactTemperature(weather))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PureLineStyle.ink)
                Text(compactWindSpeed(weather))
                    .font(.caption2)
                    .foregroundStyle(PureLineStyle.muted)
            } else {
                Text(store.isLoading ? "Loading" : "Weather")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(PureLineStyle.ink)
            }
            if store.isLoading { ProgressView().controlSize(.mini) }
        }
    }

    private var expandedLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "cloud.sun").foregroundStyle(PureLineStyle.accent)
            if let weather = store.weather(for: location) {
                Text(weather.temperatureC.map { String(format: "%.0f°C", $0) } ?? "–°C").fontWeight(.semibold)
                Spacer(minLength: 0)
                CourseWindIndicator(weather: weather, mapHeading: mapHeading)
                if store.errorMessage != nil || store.isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .accessibilityLabel("Cached weather; see details")
                }
            } else {
                Text(store.isLoading ? "Loading weather…" : "Weather unavailable · tap to retry")
                Spacer(minLength: 0)
            }
            if store.isLoading { ProgressView().controlSize(.mini) }
            Image(systemName: "chevron.right").font(.caption2)
        }
    }

    private var locationKey: String {
        String(format: "%.3f,%.3f", location.lat, location.lon)
    }

    private func compactTemperature(_ weather: CourseWeather) -> String {
        guard let temperature = weather.temperatureC else { return "–°" }
        return String(format: "%.0f°", temperature)
    }

    private func compactWindSpeed(_ weather: CourseWeather) -> String {
        guard let speed = weather.windSpeedMps else { return "Wind" }
        return String(format: "%.0f m/s", speed)
    }

    private var accessibilitySummary: String {
        guard let weather = store.weather(for: location) else {
            return store.isLoading ? "Loading weather" : "Weather unavailable"
        }
        let temperature = weather.temperatureC.map { String(format: "%.0f degrees Celsius", $0) } ?? "Temperature unavailable"
        let wind = weather.windSpeedMps.map { String(format: "%.1f metres per second", $0) } ?? "unavailable"
        let direction = weather.windDirectionDegrees.map { String(format: "from %.0f degrees true north", $0) } ?? "direction unavailable"
        return "\(temperature), wind \(wind), \(direction). \(store.isStale || store.errorMessage != nil ? "Cached conditions; review details." : "")"
    }
}

private struct CourseWeatherDetail: View {
    let location: GeoPoint
    let store: CourseWeatherStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Current course conditions") {
                    if let weather = store.weather(for: location) {
                        metric("Temperature", weather.temperatureC, "°C")
                        metric("Relative humidity", weather.relativeHumidityPercent, "%")
                        metric("Course weather elevation", weather.elevationMeters, "m")
                        metric("Surface pressure", weather.surfacePressureHpa, "hPa")
                        metric("Sea-level pressure", weather.seaLevelPressureHpa, "hPa")
                        metric("Wind speed (10 m)", weather.windSpeedMps, "m/s")
                        metric("Wind FROM (true north)", weather.windDirectionDegrees, "°")
                        metric("Wind gusts", weather.windGustsMps, "m/s")
                    } else {
                        Text("Weather unavailable. Refresh manually to try again.")
                    }
                }
                Section("Source & snapshot") {
                    Text("Open-Meteo · course-level forecast conditions, not measurements at the ball.")
                    if let weather = store.weather(for: location) {
                        LabeledContent("Observed at", value: weather.observedAt)
                        LabeledContent("Timezone", value: weather.timezone ?? "Provider local time")
                        if let fetchedAt = store.fetchedAt { LabeledContent("Fetched / cached", value: fetchedAt.formatted()) }
                        Text(store.isStale ? "Cached snapshot is over 30 minutes old." : "Snapshot is within the 30-minute cache window.")
                    }
                    Text(String(format: "Course location: %.5f, %.5f", location.lat, location.lon))
                    Text("The map arrow points where wind blows TO, rotated with map heading. Recommendations use surface pressure directly; weather elevation is not terrain height, and gusts are not used.")
                }
                Section("Loading & refresh") {
                    if store.isLoading { ProgressView("Loading current conditions…") }
                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                        Text("Any displayed cached conditions are retained; no automatic retry.")
                    }
                    Button(store.errorMessage == nil ? "Refresh course weather" : "Retry course weather", systemImage: "arrow.clockwise") {
                        Task { await store.load(for: location, forceRefresh: true) }
                    }
                    .disabled(store.isLoading)
                }
            }
            .navigationTitle("Course weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(FairwayVectorColors.navy)
    }

    private func metric(_ title: String, _ value: Double?, _ unit: String) -> some View {
        LabeledContent(title, value: value.map { String(format: "%.1f %@", $0, unit) } ?? "Not supplied")
    }
}
