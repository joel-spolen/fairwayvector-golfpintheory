import SwiftUI

/// The provider reports where wind comes from; the arrow shows where it blows to.
struct CourseWindIndicator: View {
    let weather: CourseWeather
    let mapHeading: Double
    var compact = false

    private var isCalm: Bool {
        weather.windSpeedMps.map { $0 < 0.5 } ?? false
    }

    private var windToBearing: Double? {
        guard let direction = weather.windDirectionDegrees, direction.isFinite else { return nil }
        return (direction + 540).truncatingRemainder(dividingBy: 360)
    }

    private var destination: String {
        guard let bearing = windToBearing else { return "Unknown" }
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return points[Int((bearing / 45).rounded()) % points.count]
    }

    private var speedText: String {
        guard let speed = weather.windSpeedMps, speed.isFinite else { return "– m/s" }
        return String(format: "%.1f m/s", speed)
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(PureLineStyle.surface)
                if !isCalm, let bearing = windToBearing {
                    Image(systemName: "arrow.up")
                        .font(.caption.bold())
                        .foregroundStyle(PureLineStyle.accent)
                        // Up represents the camera heading, not geographic north.
                        .rotationEffect(.degrees(bearing - mapHeading))
                } else {
                    Image(systemName: isCalm ? "wind" : "questionmark")
                        .font(.caption)
                        .foregroundStyle(PureLineStyle.muted)
                }
            }
            .frame(width: 26, height: 26)
            if !compact {
                Text(isCalm ? "Calm" : "\(speedText) → \(destination)")
                    .font(.caption.monospacedDigit())
            }
        }
        .frame(minWidth: compact ? 26 : nil, minHeight: compact ? 26 : nil)
        .foregroundStyle(PureLineStyle.ink)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Course wind")
        .accessibilityValue(isCalm ? "Calm, \(speedText)" : "Blowing toward \(destination), \(speedText)")
    }
}