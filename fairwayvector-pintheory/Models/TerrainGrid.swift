import Foundation

// Global GPXZ domain; legacy RH2000 raster packages are never imported.
nonisolated struct TerrainProvenance: Codable, Hashable, Sendable {
    let dataSource: String
    let resolutionMeters: Double
    let captureDateMin: String?
    let captureDateMax: String?
    let datasetVersion: String?
    let fetchedAt: Date
    let interpolation: String
    let verticalDatum: String
    let providerSampleIntervalMeters: Double
    var isSynthetic: Bool { dataSource == DevelopmentAPIConfiguration.syntheticSource }
}

nonisolated struct TerrainSample: Codable, Identifiable, Hashable, Sendable {
    let distanceMeters: Double
    let point: GeoPoint
    let elevationMeters: Double?
    var provenance: [TerrainProvenance] = []
    var locallyInterpolated = false
    var id: Double { distanceMeters }
}

nonisolated struct TerrainProfile: Sendable {
    let samples: [TerrainSample]
    let isStraightLine: Bool
    var distanceMeters: Double { samples.last?.distanceMeters ?? 0 }
    var elevationChangeMeters: Double? {
        guard let first = samples.first?.elevationMeters, let last = samples.last?.elevationMeters else { return nil }
        return last - first
    }
    var metadata: [TerrainProvenance] {
        Array(Set(samples.flatMap(\.provenance))).sorted { $0.dataSource < $1.dataSource }
    }
    var maximumSpacingMeters: Double {
        zip(samples, samples.dropFirst()).map { $1.distanceMeters - $0.distanceMeters }.max() ?? 0
    }
}

nonisolated struct TerrainRequest: Hashable, Sendable {
    let courseID: String
    let holeNumber: Int
    let path: [GeoPoint]
    let flag: GeoPoint?
    let origin: GeoPoint?
    let target: GeoPoint?
    let usesPointOnlyGeometry: Bool
    let usesGPS: Bool
    // Ephemeral request metadata, not persisted/Codable. Existing callers default to real sources.
    var isSimulatedOrigin: Bool = false

    var originLabel: String {
        isSimulatedOrigin ? "Simulated golfer · Development"
            : usesGPS ? "Captured GPS" : "Captured tee fallback"
    }
}

nonisolated struct TerrainSnapshot: Sendable {
    var holeProfile: TerrainProfile?
    var shotProfile: TerrainProfile?
    var targetToFlagProfile: TerrainProfile?
    var shotElevationChangeMeters: Double? { shotProfile?.elevationChangeMeters }
    var targetToFlagElevationChangeMeters: Double? { targetToFlagProfile?.elevationChangeMeters }
}

nonisolated enum TerrainError: Error, LocalizedError, Sendable {
    case invalidPath, invalidResponse, cacheUnavailable, ledgerUnavailable, exhausted, notConfigured, requestPaused
    case http(Int, reason: String? = nil), retryAfter(Date), transport, failedRequest(String)
    var errorDescription: String? {
        switch self {
        case .invalidPath: "Terrain path must contain valid WGS84 points (maximum 5,000)."
        case .invalidResponse: "GPXZ returned an invalid profile; nothing was saved."
        case .cacheUnavailable: "Terrain cache could not be read or saved. Paid requests are blocked; preserve the cache and resolve the storage issue."
        case .ledgerUnavailable: "The GPXZ quota ledger is unreadable. Paid requests are blocked; do not delete it to bypass the limit."
        case .exhausted: "The local 100-call UTC monthly limit is exhausted. Showing saved terrain only."
        case .notConfigured: "GPXZ is not configured. Set GPXZ_API_KEY in the optional GPXZ.local.xcconfig. Saved terrain remains available."
        case .requestPaused: "Terrain acquisition paused for target interaction. Release a target to request its missing shot terrain."
        case .http(let status, let reason):
            "GPXZ request failed (HTTP \(status)). \(reason ?? "Provider supplied no usable error detail.") No automatic retry."
        case .transport: "GPXZ could not complete the request. No automatic retry; the reservation is retained."
        case .failedRequest(let reason): "\(reason) Identical failed request blocked. Correct the cause, then confirm Retry terrain to try again."
        case .retryAfter(let date): "GPXZ requests are paused until \(date.formatted()). Retry explicitly afterwards."
        }
    }
}

nonisolated enum TerrainGeometry {
    static let radius = 6_371_000.0
    static let tolerance = 0.02
    static func valid(_ p: GeoPoint) -> Bool {
        p.lat.isFinite && p.lon.isFinite && (-90...90).contains(p.lat) && (-180...180).contains(p.lon)
    }
    static func longitudeDelta(_ a: Double, _ b: Double) -> Double {
        var d = b - a
        if d > 180 { d -= 360 }; if d < -180 { d += 360 }
        return d
    }
    static func vector(_ p: GeoPoint, from origin: GeoPoint) -> SIMD2<Double> {
        SIMD2(longitudeDelta(origin.lon, p.lon) * .pi / 180 * radius * cos(origin.lat * .pi / 180),
              (p.lat - origin.lat) * .pi / 180 * radius)
    }
    static func length(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.lat * .pi / 180, lat2 = b.lat * .pi / 180
        let x = sin((lat2 - lat1) / 2), y = sin(longitudeDelta(a.lon, b.lon) * .pi / 360)
        return 2 * radius * asin(min(1, sqrt(x * x + cos(lat1) * cos(lat2) * y * y)))
    }
    static func interpolate(_ a: GeoPoint, _ b: GeoPoint, _ fraction: Double) -> GeoPoint {
        var lon = a.lon + longitudeDelta(a.lon, b.lon) * fraction
        if lon > 180 { lon -= 360 }; if lon < -180 { lon += 360 }
        return GeoPoint(lat: a.lat + (b.lat - a.lat) * fraction, lon: lon)
    }
    static func clean(_ path: [GeoPoint]) throws -> [GeoPoint] {
        guard !path.isEmpty, path.count <= 5_000, path.allSatisfy(valid) else { throw TerrainError.invalidPath }
        return path.reduce(into: []) { result, p in
            if result.last.map({ length($0, p) > 0.0000001 }) ?? true { result.append(p) }
        }
    }
    static func chainages(_ path: [GeoPoint]) -> [Double] {
        var result = [0.0]
        for (a, b) in zip(path, path.dropFirst()) { result.append(result.last! + length(a, b)) }
        return result
    }
    static func point(_ path: [GeoPoint], at distance: Double) -> GeoPoint {
        let chain = chainages(path)
        for i in 0..<max(0, path.count - 1) where distance < chain[i + 1] {
            return interpolate(path[i], path[i + 1], max(0, (distance - chain[i]) / (chain[i + 1] - chain[i])))
        }
        return path.last!
    }
    static func slice(_ path: [GeoPoint], from lower: Double, to upper: Double) -> [GeoPoint] {
        let chain = chainages(path)
        var result = [point(path, at: lower)]
        for i in path.indices where chain[i] > lower && chain[i] < upper { result.append(path[i]) }
        result.append(point(path, at: upper))
        return result
    }
}