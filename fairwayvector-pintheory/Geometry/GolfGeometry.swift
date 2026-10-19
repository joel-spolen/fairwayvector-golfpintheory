import CoreLocation

enum GolfGeometry {
    private static let earthRadius = 6_371_000.0

    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        CLLocation(latitude: a.lat, longitude: a.lon)
            .distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
    }

    static func distance(_ point: GeoPoint, toPath path: [GeoPoint]) -> Double? {
        guard path.count >= 2 else { return nil }
        let projected = path.map { project($0, origin: point) }
        var closest = Double.infinity
        for index in 0..<(projected.count - 1) {
            let start = projected[index]
            let segment = projected[index + 1] - start
            let lengthSquared = (segment * segment).sum()
            let fraction = lengthSquared == 0
                ? 0
                : max(0, min(1, -(start * segment).sum() / lengthSquared))
            let nearest = start + segment * fraction
            closest = min(closest, (nearest * nearest).sum().squareRoot())
        }
        return closest.isFinite ? closest : nil
    }

    static func corridorBoundary(for path: [GeoPoint], halfWidth: Double = 28) -> [GeoPoint] {
        guard path.count >= 2, let origin = path.first else { return [] }
        let points = path.map { project($0, origin: origin) }
        var left: [SIMD2<Double>] = []
        var right: [SIMD2<Double>] = []

        for index in points.indices {
            let previous = points[max(0, index - 1)]
            let next = points[min(points.count - 1, index + 1)]
            let direction = next - previous
            let length = (direction * direction).sum().squareRoot()
            guard length > 0 else { continue }
            let normal = SIMD2(-direction.y / length, direction.x / length)
            left.append(points[index] + normal * halfWidth)
            right.append(points[index] - normal * halfWidth)
        }

        return (left + right.reversed()).map { unproject($0, origin: origin) }
    }

    static func nearestPoint(onPath path: [GeoPoint], to point: GeoPoint) -> GeoPoint? {
        guard path.count >= 2 else { return path.first }
        let projected = path.map { project($0, origin: point) }
        var nearestDistance = Double.infinity
        var nearestPoint: SIMD2<Double>?
        for index in 0..<(projected.count - 1) {
            let start = projected[index]
            let segment = projected[index + 1] - start
            let lengthSquared = (segment * segment).sum()
            let fraction = lengthSquared == 0
                ? 0
                : max(0, min(1, -(start * segment).sum() / lengthSquared))
            let candidate = start + segment * fraction
            let distance = (candidate * candidate).sum()
            if distance < nearestDistance {
                nearestDistance = distance
                nearestPoint = candidate
            }
        }
        return nearestPoint.map { unproject($0, origin: point) }
    }

    static func smoothConnectorBoundary(from start: GeoPoint, to end: GeoPoint, radius: Double) -> [GeoPoint] {
        let endVector = project(end, origin: start)
        let length = (endVector * endVector).sum().squareRoot()
        guard length > 0.5 else { return [] }

        let heading = atan2(endVector.y, endVector.x)
        let steps = 16
        var boundary: [SIMD2<Double>] = []

        for step in 0...steps {
            let angle = heading - .pi / 2 + .pi * Double(step) / Double(steps)
            boundary.append(endVector + SIMD2(cos(angle), sin(angle)) * radius)
        }
        for step in 0...steps {
            let angle = heading + .pi / 2 + .pi * Double(step) / Double(steps)
            boundary.append(SIMD2(cos(angle), sin(angle)) * radius)
        }
        return boundary.map { unproject($0, origin: start) }
    }

    static func convexHull(of polygons: [[GeoPoint]]) -> [GeoPoint] {
        guard let origin = polygons.lazy.flatMap({ $0 }).first else { return [] }
        var points: [SIMD2<Double>] = []
        for polygon in polygons {
            for point in polygon {
                points.append(project(point, origin: origin))
            }
        }
        points.sort {
            if $0.x == $1.x { return $0.y < $1.y }
            return $0.x < $1.x
        }
        guard points.count > 2 else { return points.map { unproject($0, origin: origin) } }

        func cross(_ origin: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
        }

        var lower: [SIMD2<Double>] = []
        for point in points {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [SIMD2<Double>] = []
        for point in points.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        lower.removeLast()
        upper.removeLast()
        return (lower + upper).map { unproject($0, origin: origin) }
    }

    /// Initial bearing in degrees clockwise from north.
    static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    #if DEBUG
    /// Spherical forward geodesic, with longitude normalized across the dateline.
    static func destination(from start: GeoPoint, distanceM: Double, bearingDeg: Double) -> GeoPoint {
        let lat = start.lat * .pi / 180, lon = start.lon * .pi / 180
        let angle = distanceM / earthRadius, bearing = bearingDeg * .pi / 180
        let nextLat = asin(max(-1, min(1, sin(lat) * cos(angle) + cos(lat) * sin(angle) * cos(bearing))))
        let nextLon = lon + atan2(sin(bearing) * sin(angle) * cos(lat), cos(angle) - sin(lat) * sin(nextLat))
        let degrees = nextLon * 180 / .pi
        let normalized = (degrees + 540).truncatingRemainder(dividingBy: 360) - 180
        return GeoPoint(lat: nextLat * 180 / .pi, lon: normalized)
    }
    #endif

    static func interpolate(_ a: GeoPoint, _ b: GeoPoint, fraction: Double) -> GeoPoint {
        GeoPoint(lat: a.lat + (b.lat - a.lat) * fraction, lon: a.lon + (b.lon - a.lon) * fraction)
    }

    /// Local east/north metres around `origin`; accurate enough at golf-hole scale.
    static func project(_ point: GeoPoint, origin: GeoPoint) -> SIMD2<Double> {
        let x = (point.lon - origin.lon) * .pi / 180 * earthRadius * cos(origin.lat * .pi / 180)
        let y = (point.lat - origin.lat) * .pi / 180 * earthRadius
        return SIMD2(x, y)
    }

    static func unproject(_ v: SIMD2<Double>, origin: GeoPoint) -> GeoPoint {
        let lat = origin.lat + v.y / earthRadius * 180 / .pi
        let lon = origin.lon + v.x / (earthRadius * cos(origin.lat * .pi / 180)) * 180 / .pi
        return GeoPoint(lat: lat, lon: lon)
    }

    static func centroid(of polygon: [GeoPoint]) -> GeoPoint? {
        guard let origin = polygon.first else { return nil }
        let pts = polygon.map { project($0, origin: origin) }
        var area = 0.0
        var c = SIMD2<Double>(0, 0)
        for i in pts.indices {
            let p = pts[i]
            let q = pts[(i + 1) % pts.count]
            let cross = p.x * q.y - q.x * p.y
            area += cross
            c += (p + q) * cross
        }
        if abs(area) < 1e-9 {
            let mean = pts.reduce(SIMD2<Double>(0, 0), +) / Double(pts.count)
            return unproject(mean, origin: origin)
        }
        return unproject(c / (3 * area), origin: origin)
    }

    static func contains(_ point: GeoPoint, in polygon: [GeoPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        let pts = polygon.map { project($0, origin: point) }
        var inside = false
        var j = pts.count - 1
        for i in pts.indices {
            let a = pts[i]
            let b = pts[j]
            if (a.y > 0) != (b.y > 0), 0 < (b.x - a.x) * (0 - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Front/back of the green along the line from the player through the green centre.
    static func frontBack(from player: GeoPoint, green: [GeoPoint]) -> (front: Double, back: Double)? {
        guard green.count >= 3, let center = centroid(of: green) else { return nil }
        let target = project(center, origin: player)
        let length = (target * target).sum().squareRoot()
        let pts = green.map { project($0, origin: player) }

        if length > 0.5 {
            let dir = target / length
            var hits: [Double] = []
            for i in pts.indices {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                let edge = b - a
                let denom = dir.x * edge.y - dir.y * edge.x
                guard abs(denom) > 1e-12 else { continue }
                let t = (a.x * edge.y - a.y * edge.x) / denom
                let s = (a.x * dir.y - a.y * dir.x) / denom
                if t >= 0, s >= 0, s <= 1 { hits.append(t) }
            }
            if hits.count >= 2, let front = hits.min(), let back = hits.max() {
                return (front, back)
            }
        }

        let distances = pts.map { ($0 * $0).sum().squareRoot() }
        guard let front = distances.min(), let back = distances.max() else { return nil }
        return (front, back)
    }
}
