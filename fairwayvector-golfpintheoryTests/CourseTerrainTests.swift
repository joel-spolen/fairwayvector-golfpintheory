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
        #expect(store.shotMessage == L("No elevation data for this spot."))
        store.setTerrain(nil, unavailableMessage: "Unavailable")
        store.open(request)
        #expect(store.holeMessage == "Unavailable" && store.snapshot.holeProfile == nil)
    }

    @Test func chartDecimationKeepsGapsEndpointsAndExtremesWithinBudget() {
        let point = GeoPoint(lat: 57.62, lon: 12.0)
        // 2001 samples: a gap at 900…949 m, a spike at 300 m and a dip at 1500 m.
        let samples = (0...2000).map { i -> TerrainSample in
            let d = Double(i)
            let height: Double? = (900..<950).contains(i) ? nil
                : i == 300 ? 150 : i == 1500 ? 20 : 60 + sin(d / 40) * 5
            return TerrainSample(distanceMeters: d, point: point, elevationMeters: height)
        }
        let runs = TerrainProfileChart.displayRuns(samples, buckets: 200)
        #expect(runs.count == 2)
        #expect(runs[0].first?.distanceMeters == 0 && runs[0].last?.distanceMeters == 899)
        #expect(runs[1].first?.distanceMeters == 950 && runs[1].last?.distanceMeters == 2000)
        let kept = runs.flatMap { $0 }
        #expect(kept.count <= 2 * 200 + 2 * runs.count)
        #expect(kept.contains { $0.distanceMeters == 300 && $0.elevationMeters == 150 })
        #expect(kept.contains { $0.distanceMeters == 1500 && $0.elevationMeters == 20 })
        #expect(zip(kept, kept.dropFirst()).allSatisfy { $0.distanceMeters < $1.distanceMeters })

        let single = [TerrainSample(distanceMeters: 0, point: point, elevationMeters: 10),
                      TerrainSample(distanceMeters: 1, point: point, elevationMeters: nil),
                      TerrainSample(distanceMeters: 2, point: point, elevationMeters: 12)]
        #expect(TerrainProfileChart.displayRuns(single).map(\.count) == [1, 1])
    }

    @Test func greenSlopeFindsATiltedPlaneAndItsDownhillDirection() throws {
        // About 1 m pixels; elevation rises 2 cm per metre toward the east (a 2 % slope falling west).
        let metresPerDegreeLat = 111_320.0, metresPerDegreeLon = 111_320.0 * cos(57.0 * .pi / 180)
        let bytes = try Self.packed(width: 60, height: 60,
            bounds: (12, 12 + 60 / metresPerDegreeLon, 57, 57 + 60 / metresPerDegreeLat)) { x, _ in UInt16(x * 2) }
        let tile = try CourseTerrainTile(packed: bytes, provenance: provenance)
        let point = { (east: Double, north: Double) in
            GeoPoint(lat: 57 + north / metresPerDegreeLat, lon: 12 + east / metresPerDegreeLon)
        }
        let hole = Hole(number: 1, par: 4, path: [point(30, 0), point(30, 30)], green: [],
                        greenFront: point(30, 15), greenBack: point(30, 45))
        let map = try #require(GreenSlopeMap.make(terrain: CourseTerrain(source: .tiles([tile])), hole: hole))
        let slopes = map.cells.map(\.slopePercent).sorted()
        #expect(map.cells.count > 50)
        #expect(abs(slopes[slopes.count / 2] - 2) < 0.2)
        #expect(map.cells.allSatisfy { $0.downhill.x < -0.95 })

        let coarse = try CourseTerrainTile(packed: bytes, provenance: TerrainProvenance(dataSource: "gpxz_terrain_30m",
            resolutionMeters: 1, captureDateMin: nil, captureDateMax: nil, datasetVersion: nil, fetchedAt: .now,
            interpolation: "bilinear", verticalDatum: "EGM2008", providerSampleIntervalMeters: 1))
        #expect(GreenSlopeMap.make(terrain: CourseTerrain(source: .tiles([coarse])), hole: hole) == nil)

        let square = { (east: Double, north: Double) in
            [point(east - 10, north - 10), point(east + 10, north - 10), point(east + 10, north + 10), point(east - 10, north + 10)]
        }
        var outlined = hole
        outlined.greenOutline = try #require(GreenSlopeMap.outline(for: hole, among: [square(5, 5), square(30, 30)]))
        #expect(outlined.greenOutline == square(30, 30))
        let mapped = try #require(GreenSlopeMap.make(terrain: CourseTerrain(source: .tiles([tile])), hole: outlined))
        #expect(mapped.usesMappedOutline && mapped.region == square(30, 30))
        #expect(!map.usesMappedOutline)
    }

    @Test func unmappedGreenOutlineIsFoundFromTheElevationModel() throws {
        // A raised green 24 m wide and 32 m deep; the front/back oval would be 28 m wide.
        let metresPerDegreeLat = 111_320.0, metresPerDegreeLon = 111_320.0 * cos(57.0 * .pi / 180)
        let bytes = try Self.packed(width: 100, height: 100,
            bounds: (12, 12 + 100 / metresPerDegreeLon, 57, 57 + 100 / metresPerDegreeLat)) { x, y in
            let dx = (Double(x) + 0.5 - 50) / 12, dy = (Double(y) + 0.5 - 50) / 16
            return dx * dx + dy * dy <= 1 ? 600 + UInt16(x) : 500
        }
        let tile = try CourseTerrainTile(packed: bytes, provenance: provenance)
        let point = { (east: Double, north: Double) in
            GeoPoint(lat: 57 + north / metresPerDegreeLat, lon: 12 + east / metresPerDegreeLon)
        }
        let hole = Hole(number: 1, par: 4, path: [point(50, 0), point(50, 34)], green: [],
                        greenFront: point(50, 34), greenBack: point(50, 66))
        let terrain = CourseTerrain(source: .tiles([tile]))
        let outline = try #require(GreenSlopeMap.detectedOutline(terrain: terrain, hole: hole))
        let reach = outline.map { GolfGeometry.distance($0, point(50, 50)) }
        // A sharp-edged plateau reads up to ~3 m small; real greens with gradual edges lose less.
        #expect((8.5...13).contains(reach[0]))   // east
        #expect((12.5...17).contains(reach[18])) // north
        #expect(reach[0] < reach[18] - 2)

        let map = try #require(GreenSlopeMap.make(terrain: terrain, hole: hole))
        #expect(map.region == outline && !map.usesMappedOutline)
        #expect(GreenSlopeMap.detectedOutline(terrain: CourseTerrain(source: .tiles([tile])),
            hole: Hole(number: 2, par: 4, path: [], green: [], greenFront: point(20, 20), greenBack: point(20, 44))) == nil)
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
