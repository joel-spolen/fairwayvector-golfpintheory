import CoreLocation

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
