import CoreLocation
import SwiftUI

struct DistanceCard: View {
    let hole: Hole
    let origin: DistanceOrigin?
    let unit: DistanceUnit
    var middleTitle = L("Center")
    var middlePoint: GeoPoint? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var featuredDistanceSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title2) private var distanceSize: CGFloat = 23

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let origin, let center = hole.greenCenter {
                let front = hole.greenFront.map { GolfGeometry.distance(origin.point, $0) }
                    ?? GolfGeometry.frontBack(from: origin.point, green: hole.green)?.front
                let back = hole.greenBack.map { GolfGeometry.distance(origin.point, $0) }
                    ?? GolfGeometry.frontBack(from: origin.point, green: hole.green)?.back
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    metric(L("Front"), front, color: PureLineStyle.ink)
                    metric(middleTitle, GolfGeometry.distance(origin.point, middlePoint ?? center), color: PureLineStyle.accent, prominent: true)
                    metric(L("Back"), back, color: PureLineStyle.ink)
                    Spacer(minLength: 0)
                }

            } else {
                Text("No green is mapped for this hole yet.")
                    .font(.subheadline)
                    .foregroundStyle(FairwayVectorColors.slate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, _ meters: Double?, color: Color, prominent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(PureLineStyle.muted)
            Text(meters.map { "\(unit.value($0))" } ?? "–")
                .font((prominent ? Font.system(size: featuredDistanceSize, weight: .semibold) : Font.system(size: distanceSize, weight: .medium)).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit.symbol)
                .font(.caption2)
                .foregroundStyle(PureLineStyle.muted)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(meters.map(unit.format) ?? "unavailable")")
    }

}

struct DistanceOrigin {
    enum Source {
        case gps(accuracy: Double)
        case simulated
        case teeNoFix
        case teeFarAway(distance: Double)
    }

    var point: GeoPoint
    var source: Source

    static let onHoleCorridor = 100.0

    var usesGPS: Bool {
        if case .gps = source { return true }
        return false
    }

    var isSimulated: Bool {
        if case .simulated = source { return true }
        return false
    }

    static func resolve(location: CLLocation?, hole: Hole) -> DistanceOrigin? {
        guard let tee = hole.tee else { return nil }
        guard let location, location.horizontalAccuracy >= 0 else {
            return DistanceOrigin(point: tee, source: .teeNoFix)
        }
        let player = GeoPoint(location.coordinate)
        let away = GolfGeometry.distance(player, toPath: hole.path) ?? .infinity
        if away > onHoleCorridor {
            return DistanceOrigin(point: tee, source: .teeFarAway(distance: away))
        }
        return DistanceOrigin(point: player, source: .gps(accuracy: location.horizontalAccuracy))
    }

}
