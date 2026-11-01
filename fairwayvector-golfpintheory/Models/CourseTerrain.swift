import CryptoKit
import Foundation

/// Server manifest for a course's elevation tiles (see golf-data `bundle`).
nonisolated struct CourseTerrainManifest: Codable, Sendable {
    struct Bounds: Codable, Sendable { let left, right, bottom, top: Double }
    struct Tile: Codable, Sendable {
        let status: String
        let id: String
        var code: String?
        var sha256: String?
        var width: Int?
        var height: Int?
        var bounds: Bounds?
        var resolutionMeters: Double?
        var sources: [String]?
        var captureDateMin: String?
        var captureDateMax: String?
        var datasetVersion: String?
        var fetchedAt: String?
    }
    let status: String
    var code: String?
    let tiles: [Tile]

    var isReady: Bool { status == "ready" && !tiles.isEmpty && tiles.allSatisfy { $0.status == "ready" } }
    /// Busy/pending outcomes are worth retrying on the next course open.
    var isTemporary: Bool {
        let temporary: Set<String> = ["request_pending", "daily_budget_exceeded", "rate_limit", "provider_cooldown",
                                      "service_unavailable", "storage_unavailable", "cache_write_rejected"]
        return status == "pending" || tiles.contains { $0.code.map(temporary.contains) == true }
    }
}

/// One PTTR v1 grid: north-up WGS84 rectangle, pixel-is-area, centimetre/decimetre UInt16 steps.
nonisolated struct CourseTerrainTile: Sendable {
    let width: Int
    let height: Int
    let left: Double, right: Double, bottom: Double, top: Double
    let base: Double
    let scale: Double
    let values: [UInt16]
    let provenance: TerrainProvenance

    init(packed data: Data, provenance: TerrainProvenance) throws {
        guard data.count > 64, data.prefix(4) == Data("PTTR".utf8) else { throw CourseTerrainError.invalidTile }
        func u16(_ at: Int) -> UInt16 { data.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt16.self)) } }
        func u32(_ at: Int) -> UInt32 { data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt32.self)) } }
        func f64(_ at: Int) -> Double {
            Double(bitPattern: data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt64.self)) })
        }
        width = Int(u32(8)); height = Int(u32(12))
        left = f64(16); right = f64(24); bottom = f64(32); top = f64(40)
        base = f64(48); scale = f64(56)
        guard u16(4) == 1, (1...10_000).contains(width), (1...10_000).contains(height),
              [left, right, bottom, top, base, scale].allSatisfy(\.isFinite), right > left, top > bottom, scale > 0,
              let body = try? (data.subdata(in: 64..<data.count) as NSData).decompressed(using: .zlib) as Data,
              body.count == width * height * 2 else { throw CourseTerrainError.invalidTile }
        var decoded = [UInt16](repeating: 0, count: width * height)
        let columns = width, rows = height
        body.withUnsafeBytes { raw in
            for y in 0..<rows {
                var value: UInt16 = 0
                for x in 0..<columns {
                    let i = y * columns + x
                    value &+= UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                    decoded[i] = value
                }
            }
        }
        values = decoded
        self.provenance = provenance
    }

    func elevation(at point: GeoPoint) -> Double? {
        guard point.lon >= left, point.lon <= right, point.lat >= bottom, point.lat <= top else { return nil }
        let fx = min(max((point.lon - left) / (right - left) * Double(width) - 0.5, 0), Double(width - 1))
        let fy = min(max((top - point.lat) / (top - bottom) * Double(height) - 0.5, 0), Double(height - 1))
        let x0 = Int(fx), y0 = Int(fy)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let tx = fx - Double(x0), ty = fy - Double(y0)
        func v(_ x: Int, _ y: Int) -> Double { Double(values[y * width + x]) }
        let north = v(x0, y0) + (v(x1, y0) - v(x0, y0)) * tx
        let south = v(x0, y1) + (v(x1, y1) - v(x0, y1)) * tx
        return base + scale * (north + (south - north) * ty)
    }
}

nonisolated enum CourseTerrainError: Error, Sendable {
    case invalidTile
    case unavailable(temporary: Bool)
}

/// Whole-course elevation available on the device; every profile is computed locally.
nonisolated struct CourseTerrain: Sendable {
    enum Source: Sendable {
        case tiles([CourseTerrainTile])
        case synthetic
    }
    let source: Source

    static let syntheticProvenance = TerrainProvenance(dataSource: DevelopmentAPIConfiguration.syntheticSource,
        resolutionMeters: 1, captureDateMin: nil, captureDateMax: nil, datasetVersion: "synthetic-development-v1",
        fetchedAt: Date(timeIntervalSince1970: 0), interpolation: "analytical synthetic surface",
        verticalDatum: "Synthetic (not surveyed)", providerSampleIntervalMeters: 1)

    /// Coordinate-based smooth surface for development builds without paid elevation.
    static func syntheticElevation(at point: GeoPoint) -> Double {
        let offset = TerrainGeometry.vector(point, from: GeoPoint(lat: 57.623, lon: 12.0))
        return 72 + 9 * sin(offset.x / 210) + 6 * cos(offset.y / 170) + 3 * sin((offset.x + offset.y) / 95)
    }

    func sample(at point: GeoPoint) -> (elevation: Double, provenance: TerrainProvenance)? {
        switch source {
        case .synthetic:
            return (Self.syntheticElevation(at: point), Self.syntheticProvenance)
        case .tiles(let tiles):
            for tile in tiles {
                if let elevation = tile.elevation(at: point) { return (elevation, tile.provenance) }
            }
            return nil
        }
    }

    /// About one sample per metre along the path, capped for very long holes.
    func profile(path raw: [GeoPoint], straight: Bool) -> TerrainProfile? {
        guard let path = try? TerrainGeometry.clean(raw), let first = path.first else { return nil }
        let length = TerrainGeometry.chainages(path).last ?? 0
        let count = length > 0 ? min(2_001, max(2, Int(length.rounded(.up)) + 1)) : 1
        let samples = (0..<count).map { i -> TerrainSample in
            let distance = count == 1 ? 0 : Double(i) / Double(count - 1) * length
            let point = i == 0 ? first : TerrainGeometry.point(path, at: distance)
            let value = sample(at: point)
            return TerrainSample(distanceMeters: distance, point: point, elevationMeters: value?.elevation,
                                 provenance: value.map { [$0.provenance] } ?? [])
        }
        return TerrainProfile(samples: samples, isStraightLine: straight)
    }
}

/// Saved course elevation lives beside the course geometry and is evicted with it.
nonisolated enum CourseTerrainStore {
    private static let manifestName = "terrain-manifest-v1.json"
    private static func tileName(_ sha256: String) -> String { "terrain-tile-v1-\(sha256).pttr" }

    static func read(directory: URL) -> CourseTerrain? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(manifestName)),
              let manifest = try? JSONDecoder().decode(CourseTerrainManifest.self, from: data), manifest.isReady else { return nil }
        var tiles: [CourseTerrainTile] = []
        for tile in manifest.tiles {
            guard let sha256 = tile.sha256,
                  let bytes = try? Data(contentsOf: directory.appendingPathComponent(tileName(sha256))),
                  hex(bytes) == sha256, let decoded = try? CourseTerrainTile(packed: bytes, provenance: provenance(tile)) else { return nil }
            tiles.append(decoded)
        }
        return CourseTerrain(source: .tiles(tiles))
    }

    /// Downloads every ready tile; saves the set only when the whole course is covered.
    static func download(_ manifest: CourseTerrainManifest, directory: URL,
                         fetch: (String) async throws -> Data) async throws -> CourseTerrain {
        var tiles: [CourseTerrainTile] = []
        for tile in manifest.tiles where tile.status == "ready" {
            guard let sha256 = tile.sha256 else { continue }
            let bytes = try await fetch(tile.id)
            guard hex(bytes) == sha256 else { throw CourseTerrainError.invalidTile }
            tiles.append(try CourseTerrainTile(packed: bytes, provenance: provenance(tile)))
            if manifest.isReady {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? bytes.write(to: directory.appendingPathComponent(tileName(sha256)), options: .atomic)
            }
        }
        guard !tiles.isEmpty else { throw CourseTerrainError.unavailable(temporary: manifest.isTemporary) }
        if manifest.isReady, let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: directory.appendingPathComponent(manifestName), options: .atomic)
        }
        return CourseTerrain(source: .tiles(tiles))
    }

    /// Per-shot GPXZ caches and the on-device monthly ledger are no longer used.
    static func removeLegacyFiles(directory: URL, accountRoot: URL) {
        for name in ["terrain-gpxz-v1.json", "terrain-gpxz-v1.json.pending", "terrain-synthetic-development-v1.json"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        try? FileManager.default.removeItem(at: accountRoot.deletingLastPathComponent().appendingPathComponent("GPXZ"))
    }

    private static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func provenance(_ tile: CourseTerrainManifest.Tile) -> TerrainProvenance {
        let resolution = tile.resolutionMeters ?? 1
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fetchedAt = tile.fetchedAt.flatMap { fractional.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        return TerrainProvenance(dataSource: (tile.sources ?? []).isEmpty ? "GPXZ" : (tile.sources ?? []).joined(separator: ", "),
            resolutionMeters: resolution, captureDateMin: tile.captureDateMin, captureDateMax: tile.captureDateMax,
            datasetVersion: tile.datasetVersion, fetchedAt: fetchedAt ?? .now,
            interpolation: "bilinear (on-device grid)", verticalDatum: "EGM2008", providerSampleIntervalMeters: resolution)
    }
}
