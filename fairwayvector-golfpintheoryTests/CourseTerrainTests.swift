import Foundation
import Testing
@testable import fairwayvector_golfpintheory

@MainActor struct CourseTerrainTests {
    /// Builds a PTTR v1 tile the same way the golf-data Edge function packs one.
    static func packed(width: Int, height: Int, bounds: (Double, Double, Double, Double),
                       base: Double = 100, scale: Double = 0.01, value: (Int, Int) -> UInt16) throws -> Data {
        var body = Data()
        for y in 0..<height {
            var previous: UInt16 = 0
            for x in 0..<width {
                let current = value(x, y)
                withUnsafeBytes(of: (current &- previous).littleEndian) { body.append(contentsOf: $0) }
                previous = current
            }
        }
        var data = Data("PTTR".utf8)
        withUnsafeBytes(of: UInt16(1).littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0, 0])
        withUnsafeBytes(of: UInt32(width).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(height).littleEndian) { data.append(contentsOf: $0) }
        for number in [bounds.0, bounds.1, bounds.2, bounds.3, base, scale] {
            withUnsafeBytes(of: number.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(try (body as NSData).compressed(using: .zlib) as Data)
        return data
    }

    private let provenance = CourseTerrain.syntheticProvenance

    @Test func decodesDeltaRowsAndInterpolatesBilinearlyBetweenPixelCentres() throws {
        // 4 × 2 pixels over 0.004° × 0.002°: centres at x 0.0005…0.0035, y 0.0015/0.0005.
        let tile = try CourseTerrainTile(packed: Self.packed(width: 4, height: 2, bounds: (12, 12.004, 57, 57.002)) { x, y in
            UInt16(x * 100 + y * 1000)
        }, provenance: provenance)
        #expect(tile.width == 4 && tile.height == 2 && tile.values == [0, 100, 200, 300, 1000, 1100, 1200, 1300])
        let northWest = try #require(tile.elevation(at: GeoPoint(lat: 57.0015, lon: 12.0005)))
        #expect(abs(northWest - 100) < 1e-9)
        let middle = try #require(tile.elevation(at: GeoPoint(lat: 57.001, lon: 12.001)))
        #expect(abs(middle - (100 + 0.01 * 550)) < 1e-6)
        let clampedEdge = try #require(tile.elevation(at: GeoPoint(lat: 57.002, lon: 12.0)))
        #expect(abs(clampedEdge - 100) < 1e-9)
        #expect(tile.elevation(at: GeoPoint(lat: 57.0021, lon: 12.001)) == nil)
    }

    @Test func rejectsCorruptTiles() throws {
        var bytes = try Self.packed(width: 2, height: 2, bounds: (12, 12.001, 57, 57.001)) { _, _ in 0 }
        #expect(throws: (any Error).self) { try CourseTerrainTile(packed: bytes.prefix(60), provenance: provenance) }
        bytes[0] = 0x58
        #expect(throws: (any Error).self) { try CourseTerrainTile(packed: bytes, provenance: provenance) }
    }

    @Test func profilesSampleAboutEveryMetreAndKeepExactEndpoints() throws {
        let terrain = CourseTerrain(source: .synthetic)
        let origin = GeoPoint(lat: 57.623, lon: 12.0), target = GeoPoint(lat: 57.6239, lon: 12.0)
        let profile = try #require(terrain.profile(path: [origin, target], straight: true))
        #expect(profile.samples.first?.point == origin && profile.samples.last?.point == target)
        #expect(profile.samples.count == Int(TerrainGeometry.length(origin, target).rounded(.up)) + 1)
        #expect(profile.samples.allSatisfy { $0.elevationMeters?.isFinite == true })
        #expect(profile.maximumSpacingMeters <= 1.0001)
        let reverse = try #require(terrain.profile(path: [target, origin], straight: true))
        #expect(reverse.elevationChangeMeters == profile.elevationChangeMeters.map { -$0 })
    }

    @Test func storeUsesDownloadedTerrainAndExplainsMissingCoverage() throws {
        let tile = try CourseTerrainTile(packed: Self.packed(width: 20, height: 20, bounds: (12, 12.002, 57, 57.002)) { x, _ in
            UInt16(x * 10)
        }, provenance: provenance)
        let store = TerrainElevationStore()
        store.setTerrain(CourseTerrain(source: .tiles([tile])), unavailableMessage: nil)
        let tee = GeoPoint(lat: 57.001, lon: 12.0002), green = GeoPoint(lat: 57.001, lon: 12.0018)
        let request = TerrainRequest(courseID: "golfapi:A", holeNumber: 1, path: [tee, green], flag: green,
            origin: tee, target: GeoPoint(lat: 57.001, lon: 12.001), usesPointOnlyGeometry: true, usesGPS: false)
        store.open(request)
        #expect(store.snapshot.holeProfile?.elevationChangeMeters.map { $0 > 0 } == true)
        #expect(store.holeMessage == nil && store.mode == .hole)
        store.commitShot(request)
        #expect(store.mode == .shot && store.shotMessage == nil)
        #expect(store.snapshot.shotProfile != nil && store.snapshot.targetToFlagProfile != nil)
        store.beginTargetInteraction()
        #expect(store.shotPending && store.snapshot.shotProfile == nil)
        let outside = TerrainRequest(courseID: "golfapi:A", holeNumber: 1, path: [tee, green], flag: green,
            origin: GeoPoint(lat: 57.01, lon: 12.0), target: green, usesPointOnlyGeometry: true, usesGPS: true)
        store.commitShot(outside)
        #expect(store.shotMessage == L("This position is outside the downloaded course elevation."))
        store.setTerrain(nil, unavailableMessage: "Unavailable")
        store.open(request)
        #expect(store.holeMessage == "Unavailable" && store.snapshot.holeProfile == nil)
    }
}

/// All test sessions route here; any dispatch fails offline instead of reaching a server.
nonisolated final class ForbiddenNetworkProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
