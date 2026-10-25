import Foundation
import Testing
@testable import fairwayvector_golfpintheory

/// Offline acceptance source only. No test below may use a live URLSession.
@MainActor struct GPXZTerrainTests {
    private let identity = "golfapi:offline-course"
    private let a = GeoPoint(lat: 57, lon: 12)
    private func point(_ meters: Double, north: Double = 0) -> GeoPoint {
        GeoPoint(lat: a.lat + north / TerrainGeometry.radius * 180 / .pi,
                 lon: a.lon + meters / (TerrainGeometry.radius * cos(a.lat * .pi / 180)) * 180 / .pi)
    }
    private func record(_ path: [GeoPoint], count: Int = 3) -> TerrainResponseRecord {
        let length = TerrainGeometry.chainages(path).last!
        let source = TerrainProvenance(dataSource: "OFFLINE_FIXTURE", resolutionMeters: 30,
                                      captureDateMin: "2020-01-01", captureDateMax: "2021-01-01", datasetVersion: "fixture",
                                      fetchedAt: Date(timeIntervalSince1970: 100), interpolation: "bilinear", verticalDatum: "EGM2008",
                                      providerSampleIntervalMeters: length / Double(count - 1))
        return TerrainResponseRecord(path: path, samples: (0..<count).map { i in
            let d = Double(i) / Double(count - 1) * length
            return TerrainSample(distanceMeters: d, point: TerrainGeometry.point(path, at: d),
                                 elevationMeters: d / 10, provenance: [source])
        }, fetchedAt: source.fetchedAt)
    }
    private func cache(_ records: [TerrainResponseRecord]) -> TerrainCourseCache {
        var cache = TerrainCourseCache(courseID: identity)
        cache.responses = records
        return cache
    }

    @Test func shorterReverseSubsectionsAndExtension() throws {
        let saved = cache([record([a, point(200)])])
        for path in [[a, point(150)], [point(50), point(150)], [point(150), point(50)]] {
            let plan = try TerrainCoveragePlan(path: path, cache: saved)
            #expect(plan.uncovered.isEmpty)
            #expect(plan.profile(cache: saved, straight: true).samples.allSatisfy { $0.elevationMeters != nil })
        }
        let extended = try TerrainCoveragePlan(path: [a, point(300)], cache: saved)
        #expect(extended.uncovered.count == 1)
        #expect(abs(extended.uncovered[0].lowerBound - 200) < 0.01)
        #expect(abs(extended.uncovered[0].upperBound - 300) < 0.01)
    }

    @Test func gapsParallelLinesAndPointsNeverCreateCoverage() throws {
        let saved = cache([record([a, point(50)]), record([point(100), point(150)])])
        let plan = try TerrainCoveragePlan(path: [a, point(200)], cache: saved)
        #expect(plan.uncovered.count == 2)
        let profile = plan.profile(cache: saved, straight: true)
        #expect(profile.samples.contains { $0.elevationMeters == nil })
        let parallel = try TerrainCoveragePlan(path: [point(0, north: 0.03), point(150, north: 0.03)], cache: saved)
        #expect(parallel.uncovered.count == 1)
        #expect(abs(parallel.uncovered[0].lowerBound) < 0.000001)
        // Two individually known endpoints are not the sampled connecting diagonal.
        let disconnected = try TerrainCoveragePlan(path: [a, point(100, north: 100)], cache: saved)
        #expect(disconnected.uncovered.count == 1)
    }

    @Test func bendsUseOriginalChainageNotSampleChords() throws {
        let bend = point(100), end = point(100, north: 100)
        // Only endpoints sampled: the right-angle bend is deliberately NOT a provider sample.
        let saved = cache([record([a, bend, end], count: 2)])
        let plan = try TerrainCoveragePlan(path: [a, bend, end], cache: saved)
        #expect(plan.uncovered.isEmpty)
        let profile = plan.profile(cache: saved, straight: false)
        #expect(abs(profile.distanceMeters - 200) < 0.01)
        let atBend = try #require(profile.samples.first { TerrainGeometry.length($0.point, bend) < 0.000001 })
        #expect(atBend.locallyInterpolated)
        let bendHeight = try #require(atBend.elevationMeters)
        #expect(abs(bendHeight - 10) < 0.01)
        let chord = try TerrainCoveragePlan(path: [a, end], cache: saved)
        #expect(!chord.uncovered.isEmpty)
    }

    @Test func exactPointsAndZeroLengthRemainHonest() throws {
        let saved = cache([record([a, point(200)])])
        let known = try TerrainCoveragePlan(path: [a, a], cache: saved).profile(cache: saved, straight: true)
        #expect(known.elevationChangeMeters == 0)
        let unknown = try TerrainCoveragePlan(path: [point(10, north: 10), point(10, north: 10)], cache: saved)
        #expect(unknown.uncovered.isEmpty)
        #expect(unknown.profile(cache: saved, straight: true).elevationChangeMeters == nil)
        let data = try JSONEncoder().encode(saved)
        let restored = try JSONDecoder().decode(TerrainCourseCache.self, from: data)
        try restored.validate(expectedID: identity)
        #expect(restored.responses[0].samples == saved.responses[0].samples)
        #expect(restored.responses[0].samples[0].provenance[0].resolutionMeters == 30)
    }

    @Test func strictResponseValidationAndHonestLongSpacing() throws {
        let path = [a, point(600)]
        let client = GPXZElevationClient(session: mockSession(), projectURL: URL(string: "https://edge.example.test"), mode: .live)
        let (request, count) = try client.request(path: path)
        #expect(count == 512)
        let body = try #require(request.httpBody)
        let form = try GPXZOfflineForm.decode(request)
        #expect(form["samples"] == "512")
        #expect(form["bathymetry"] == "false")
        #expect(form["interpolation"] == "bilinear")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(form["latlons"] == path.map { "\($0.lat),\($0.lon)" }.joined(separator: "|"))
        let wire = try #require(String(data: body, encoding: .utf8))
        #expect(wire.contains("&samples=512&")) // Plain ASCII integer, not JSON, bool, or decimal.
        #expect(wire.contains("%7C"))
        #expect(!wire.contains("|") && !wire.contains("+"))
        #expect(try client.request(path: path).0.httpBody == body)
        let invalid = Data(#"{"status":"OK","results":[]}"#.utf8)
        #expect(throws: TerrainError.self) {
            try GPXZElevationClient.validate(data: invalid, path: path, count: count, datasetVersion: nil, fetchedAt: .now)
        }
        #expect(!GPXZElevationClient(session: mockSession(), projectURL: URL(string: "http://edge.example.test"), mode: .live).configured)
    }

    @Test func formSampleCountAndCoordinatesRoundTripAtBounds() throws {
        let client = GPXZElevationClient(session: mockSession(), projectURL: URL(string: "https://edge.example.test"), mode: .live)
        for length in [0.1, 1.1, 100, 510, 511, 600] {
            let path = [a, point(length)]
            let (request, count) = try client.request(path: path)
            let form = try GPXZOfflineForm.decode(request)
            #expect((2...512).contains(count))
            #expect(form["samples"] == String(count))
            #expect(form["latlons"] == path.map { "\($0.lat),\($0.lon)" }.joined(separator: "|"))
        }
        let scientific = [GeoPoint(lat: -0.000001, lon: -82.22), GeoPoint(lat: 0.000001, lon: -82.27)]
        let form = try GPXZOfflineForm.decode(client.request(path: scientific).0)
        #expect(form["latlons"] == scientific.map { "\($0.lat),\($0.lon)" }.joined(separator: "|"))
        let courseForm = try GPXZOfflineForm.decode(client.request(path: scientific, courseID: "golfapi:course-123").0)
        #expect(courseForm["courseID"] == "course-123")
        #expect(try GPXZOfflineForm.decode(client.request(path: scientific, courseID: "osm:123").0)["courseID"] == nil)
        #expect(throws: TerrainError.self) { try client.request(path: [a, a]) }
        #expect(throws: TerrainError.self) { try client.request(path: [a, GeoPoint(lat: .nan, lon: 12)]) }
    }

    @Test func cacheOnlyOpenDoesNotInspectCredentialsOrInitializeLedger() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ledger.json")
        let repo = GPXZTerrainRepository(root: root,
            client: GPXZElevationClient(session: mockSession(), projectURL: URL(string: "http://edge.example.test"), mode: .live), ledgerURL: url)
        let store = TerrainElevationStore(repository: repo)
        let request = TerrainRequest(courseID: identity, holeNumber: 1, path: [a, point(200)],
            flag: point(200), origin: point(20), target: point(100), usesPointOnlyGeometry: true, usesGPS: true)
        store.open(request)
        for _ in 0..<10_000 {
            if !store.isHoleLoading && !store.isShotLoading { break }
            await Task.yield()
        }
        #expect(!store.isHoleLoading && !store.isShotLoading)
        #expect(store.plannedCalls == 0)
        #expect(store.holeMessage?.contains("Tap the course map") == true)
        #expect(store.shotMessage != TerrainError.notConfigured.localizedDescription)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("initialized").path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let corrupt = Data("preserve damaged ledger".utf8)
        try corrupt.write(to: url)
        let saved = await repo.profile(courseID: identity, path: request.path, straight: true, allowPaid: false)
        #expect(saved.message?.contains("Tap the course map") == true)
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test func providerErrorsExposeOnlySanitizedDocumentedDetail() throws {
        let detail = Data(#"{"error":{"code":"invalid_request","message":"Request rejected."}}"#.utf8)
        #expect(GPXZElevationClient.edgeErrorMessage(data: detail) == "Request rejected.")
        let unsafe = Data(#"{"error":{"code":"invalid_request","message":"x-api-key: secret https://example.invalid/private"}}"#.utf8)
        #expect(GPXZElevationClient.edgeErrorMessage(data: unsafe) == nil)
        #expect(GPXZElevationClient.edgeErrorMessage(data: Data("<html>not JSON</html>".utf8)) == nil)
        #expect(GPXZElevationClient.edgeErrorMessage(data: Data(repeating: 32, count: 65_537)) == nil)
    }

    @Test func ledgerPersistsUncertainReservationsAndFailsClosed() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.json")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let ledger = GPXZBudgetLedger(url: url)
        for _ in 0..<100 { try await ledger.reserve(now: date) }
        #expect(try await ledger.quota(now: date).remaining == 0)
        let reopened = GPXZBudgetLedger(url: url)
        #expect(try await reopened.quota(now: date).used == 100)
        do { try await reopened.reserve(now: date); Issue.record("Exhausted budget must block") }
        catch { #expect(error as? TerrainError != nil) }
        try Data("corrupt".utf8).write(to: url, options: .atomic)
        do { _ = try await GPXZBudgetLedger(url: url).quota(now: date); Issue.record("Corrupt ledger must fail closed") }
        catch { #expect(error as? TerrainError != nil) }
    }

    @Test func repositoryOverlapAndRelaunchNeverUseNetwork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = CourseDataStore.directory(courseID: identity, root: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(cache([record([a, point(200)])])).write(to: directory.appendingPathComponent("terrain-gpxz-v1.json"), options: .atomic)
        let client = GPXZElevationClient(session: mockSession(), projectURL: URL(string: "http://edge.example.test"), mode: .live)
        for _ in 0..<2 {
            let repository = GPXZTerrainRepository(root: root, client: client, ledgerURL: root.appendingPathComponent("ledger.json"))
            let result = await repository.profile(courseID: identity, path: [point(150), point(50)], straight: true)
            #expect(result.message == nil)
            #expect(result.plannedCalls == 0)
            #expect(result.quota?.used == 0)
            #expect(result.profile?.samples.allSatisfy { $0.elevationMeters != nil } == true)
            let missing = await repository.profile(courseID: identity, path: [a, point(300)], straight: true)
            #expect(missing.message == TerrainError.notConfigured.localizedDescription)
            #expect(missing.quota?.used == 0)
        }
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GPXZForbiddenNetworkProtocol.self]
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 8080]
        return URLSession(configuration: configuration)
    }
}

/// All test sessions route here; any dispatch fails offline instead of reaching a server.
nonisolated final class GPXZForbiddenNetworkProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}