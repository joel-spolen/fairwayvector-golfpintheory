import Foundation
import CryptoKit
import Testing
@testable import fairwayvector_golfpintheory

/// These acceptance tests intercept EVERY URLSession request. Compile only until authorized.
@MainActor struct GPXZOfflineAcquisitionTests {
    private func point(_ meters: Double) -> GeoPoint {
        GeoPoint(lat: 0, lon: meters / TerrainGeometry.radius * 180 / .pi)
    }
    private func repository(root: URL, recorder: GPXZOfflineRecorder) -> GPXZTerrainRepository {
        let id = UUID().uuidString
        GPXZOfflineProtocol.registry.register(recorder, id: id)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GPXZOfflineProtocol.self]
        config.httpAdditionalHeaders = ["X-Offline-Test": id]
        return GPXZTerrainRepository(root: root,
            client: GPXZElevationClient(key: "OFFLINE_FIXTURE_NOT_A_KEY", session: URLSession(configuration: config), mode: .live),
            ledgerURL: root.appendingPathComponent("ledger.json"))
    }

    @Test func overlappingPendingPathsExtensionAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = GPXZOfflineRecorder(mode: .valid)
        let repo = repository(root: root, recorder: recorder)
        let id = "golfapi:mock"
        async let first = repo.profile(courseID: id, path: [point(0), point(200)], straight: true)
        async let duplicate = repo.profile(courseID: id, path: [point(0), point(200)], straight: true)
        let (a, b) = await (first, duplicate)
        #expect(a.message == nil && b.message == nil)
        #expect(recorder.paths.count == 1)
        _ = await repo.profile(courseID: id, path: [point(150), point(50)], straight: true)
        #expect(recorder.paths.count == 1)
        let extended = await repo.profile(courseID: id, path: [point(0), point(300)], straight: true)
        #expect(extended.message == nil)
        #expect(recorder.paths.count == 2)
        let queried = try #require(recorder.paths.last)
        #expect(abs(TerrainGeometry.length(point(0), queried[0]) - 200) < 0.01)
        #expect(abs(TerrainGeometry.length(queried[0], queried.last!) - 100) < 0.01)
        #expect(extended.quota?.used == 2)
        let sidecar = CourseDataStore.directory(courseID: id, root: root).appendingPathComponent("terrain-gpxz-v1.json")
        let saved = try JSONDecoder().decode(TerrainCourseCache.self, from: Data(contentsOf: sidecar))
        try saved.validate(expectedID: id)
        #expect(saved.responses.count == 2)
        #expect(saved.responses.allSatisfy { $0.samples.count >= 2 && $0.samples.allSatisfy { !$0.locallyInterpolated } })
        let reopened = repository(root: root, recorder: recorder)
        let reverse = await reopened.profile(courseID: id, path: [point(300), point(0)], straight: true)
        #expect(reverse.message == nil)
        #expect(reverse.quota?.used == 2)
        #expect(recorder.paths.count == 2)
    }

    @Test func invalidOrFailedAttemptsCountButNeverPersistResponse() async throws {
        for mode in [GPXZOfflineRecorder.Mode.invalid, .httpFailure] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let recorder = GPXZOfflineRecorder(mode: mode)
            let repo = repository(root: root, recorder: recorder)
            let id = "osm:mock"
            let failed = await repo.profile(courseID: id, path: [point(0), point(100)], straight: true)
            #expect(failed.message != nil)
            #expect(failed.quota?.used == 1)
            #expect(recorder.paths.count == 1) // no automatic retry
            let sidecar = CourseDataStore.directory(courseID: id, root: root).appendingPathComponent("terrain-gpxz-v1.json")
            let saved = try JSONDecoder().decode(TerrainCourseCache.self, from: Data(contentsOf: sidecar))
            #expect(saved.responses.isEmpty)
        }
    }

    @Test func badRequestLocksSurviveRestartAndExplicitRetryNeverRefunds() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = GPXZOfflineRecorder(mode: .badRequest)
        let repo = repository(root: root, recorder: recorder)
        let path = [point(0), point(600)]
        let first = await repo.profile(courseID: "osm:400", path: path, straight: true)
        #expect(first.message?.contains("HTTP 400") == true)
        #expect(first.message?.contains("OFFLINE: samples rejected") == true)
        #expect(first.quota?.used == 1)
        let restarted = repository(root: root, recorder: recorder)
        let repeated = await restarted.profile(courseID: "osm:400", path: path, straight: true)
        #expect(repeated.message?.contains("Identical failed request blocked") == true)
        #expect(repeated.quota?.used == 1)
        #expect(recorder.paths.count == 1)
        #expect(await restarted.prepareExplicitRetry() == nil)
        let retried = await restarted.profile(courseID: "osm:400", path: path, straight: true)
        #expect(retried.quota?.used == 2)
        #expect(recorder.paths.count == 2)
    }

    @Test func openingIsCacheOnlyAndFailedCommitStopsSecondLeg() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = GPXZOfflineRecorder(mode: .badRequest)
        let store = TerrainElevationStore(repository: repository(root: root, recorder: recorder))
        let request = TerrainRequest(courseID: "osm:initial400", holeNumber: 1,
            path: [point(0), point(200)], flag: point(200), origin: point(20), target: point(100),
            usesPointOnlyGeometry: true, usesGPS: true)
        store.open(request)
        // Offline-only cooperative wait, bounded so regressions fail rather than hang.
        for _ in 0..<10_000 {
            if !store.isHoleLoading && !store.isShotLoading { break }
            await Task.yield()
        }
        #expect(!store.isHoleLoading && !store.isShotLoading)
        #expect(recorder.paths.isEmpty)
        #expect(store.quota?.used == 0)
        #expect(store.holeMessage?.contains("Tap the course map") == true)
        #expect(!store.shotPending)
        store.commitShot(request)
        for _ in 0..<10_000 {
            if !store.isShotLoading { break }
            await Task.yield()
        }
        #expect(!store.isShotLoading)
        #expect(recorder.paths.count == 1) // committed first leg, never hole or second leg
        #expect(store.quota?.used == 1)
        store.commitShot(request)
        for _ in 0..<10_000 {
            if !store.isShotLoading { break }
            await Task.yield()
        }
        #expect(recorder.paths.count == 1) // identical failed commit is locked
        store.open(request)
        for _ in 0..<10_000 {
            if !store.isHoleLoading && !store.isShotLoading { break }
            await Task.yield()
        }
        #expect(recorder.paths.count == 1)
        #expect(store.holeMessage?.contains("HTTP 400") == false)
        #expect(store.shotMessage?.contains("HTTP 400") == false)
        #expect(store.quota?.used == 1)
    }

    @Test func legacyJSONLocksAndFiveCallsSurviveOpenAndOnlyClickedLegsAcquire() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = GPXZOfflineRecorder(mode: .valid)
        let repo = repository(root: root, recorder: recorder)
        for _ in 0..<5 { try await repo.ledger.reserve() }
        let path = [point(20), point(100)]
        let legacyCount = try await repo.client.request(path: path).1
        let legacy = try JSONSerialization.data(withJSONObject: [
            "latlons": path.map { "\($0.lat),\($0.lon)" }.joined(separator: "|"),
            "samples": legacyCount,
            "interpolation": "bilinear", "bathymetry": false
        ], options: [.sortedKeys])
        let fingerprint = SHA256.hash(data: legacy).map { String(format: "%02x", $0) }.joined()
        try await repo.ledger.recordFailure(fingerprint, reason: "Samples argument should be a positive integer.")
        let ledgerURL = root.appendingPathComponent("ledger.json")
        let before = try Data(contentsOf: ledgerURL)
        let store = TerrainElevationStore(repository: repo)
        let request = TerrainRequest(courseID: "osm:five", holeNumber: 1, path: [point(0), point(200)],
            flag: point(200), origin: point(20), target: point(100), usesPointOnlyGeometry: true, usesGPS: true)
        for hole in [1, 2] {
            let opening = TerrainRequest(courseID: request.courseID, holeNumber: hole, path: request.path,
                flag: request.flag, origin: request.origin, target: request.target,
                usesPointOnlyGeometry: true, usesGPS: true)
            store.open(opening)
            for _ in 0..<10_000 {
                if !store.isHoleLoading && !store.isShotLoading { break }
                await Task.yield()
            }
            #expect(recorder.paths.isEmpty)
            #expect(store.quota?.used == 5)
            #expect(try Data(contentsOf: ledgerURL) == before)
        }
        store.beginTargetInteraction()
        #expect(recorder.paths.isEmpty)
        store.commitShot(request)
        #expect(store.mode == .shot)
        for _ in 0..<10_000 {
            if !store.isShotLoading && !store.isHoleLoading { break }
            await Task.yield()
        }
        #expect(recorder.paths == [[point(20), point(100)], [point(100), point(200)]])
        #expect(store.quota?.used == 7)
        #expect(store.snapshot.shotProfile?.elevationChangeMeters != nil)
        #expect(store.snapshot.holeProfile?.samples.contains { $0.elevationMeters == nil } == true)
        let ledger = try JSONDecoder().decode(GPXZBudgetLedger.Ledger.self, from: Data(contentsOf: ledgerURL))
        #expect(ledger.failedRequests?[fingerprint] == "Samples argument should be a positive integer.")
        store.open(request) // cache-only reopen, including both cached shot legs
        for _ in 0..<10_000 {
            if !store.isHoleLoading && !store.isShotLoading { break }
            await Task.yield()
        }
        #expect(recorder.paths.count == 2)
        #expect(store.quota?.used == 7)
        #expect(store.snapshot.targetToFlagProfile?.elevationChangeMeters != nil)
        #expect(await repo.prepareExplicitRetry() == nil)
        let archived = try JSONDecoder().decode(GPXZBudgetLedger.Ledger.self, from: Data(contentsOf: ledgerURL))
        #expect(archived.archivedFailedRequests?[fingerprint] == ledger.failedRequests?[fingerprint])
        #expect(try await repo.ledger.quota().used == 7)
    }

    @Test func corruptLedgerAndExhaustionBlockEvenMockDispatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("ledger.json")
        try Data("corrupt".utf8).write(to: url)
        let recorder = GPXZOfflineRecorder(mode: .valid)
        let repo = repository(root: root, recorder: recorder)
        let result = await repo.profile(courseID: "golfapi:blocked", path: [point(0), point(100)], straight: true)
        #expect(result.message == TerrainError.ledgerUnavailable.localizedDescription)
        #expect(recorder.paths.isEmpty)
        // New isolated directory for exhausted-budget fixture; never repair/reset a real ledger.
        let exhaustedRoot = root.appendingPathComponent("exhausted")
        let ledger = GPXZBudgetLedger(url: exhaustedRoot.appendingPathComponent("ledger.json"))
        for _ in 0..<100 { try await ledger.reserve() }
        let exhaustedRepo = repository(root: exhaustedRoot, recorder: recorder)
        let exhausted = await exhaustedRepo.profile(courseID: "golfapi:blocked", path: [point(0), point(100)], straight: true)
        #expect(exhausted.message == TerrainError.exhausted.localizedDescription)
        #expect(recorder.paths.isEmpty)
    }
}

nonisolated final class GPXZOfflineRecorder: @unchecked Sendable {
    enum Mode: Sendable { case valid, invalid, httpFailure, badRequest }
    let mode: Mode
    private let lock = NSLock()
    private var storage: [[GeoPoint]] = []
    init(mode: Mode) { self.mode = mode }
    var paths: [[GeoPoint]] { lock.lock(); defer { lock.unlock() }; return storage }
    func record(_ path: [GeoPoint]) { lock.lock(); storage.append(path); lock.unlock() }
}

/// Shared strict form parser for serialization assertions and every mock dispatch.
/// No live transport or production parser changes are involved.
nonisolated enum GPXZOfflineForm {
    static func decode(_ request: URLRequest) throws -> [String: String] {
        guard request.httpMethod == "POST",
              request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded",
              let data = request.httpBody, data.allSatisfy({ $0 < 128 }),
              let text = String(data: data, encoding: .utf8), !text.contains("+"), !text.contains("|") else {
            throw URLError(.badURL)
        }
        var components = URLComponents()
        components.percentEncodedQuery = text
        var fields: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard fields[item.name] == nil, let value = item.value else { throw URLError(.badURL) }
            fields[item.name] = value
        }
        guard fields.count == 4, let samples = fields["samples"],
              samples.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
              let count = Int(samples), (2...512).contains(count), samples == String(count),
              fields["latlons"] != nil, fields["interpolation"] == "bilinear", fields["bathymetry"] == "false" else {
            throw URLError(.badURL)
        }
        return fields
    }
}

nonisolated final class GPXZOfflineRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var recorders: [String: GPXZOfflineRecorder] = [:]
    func register(_ recorder: GPXZOfflineRecorder, id: String) { lock.lock(); recorders[id] = recorder; lock.unlock() }
    func get(_ id: String) -> GPXZOfflineRecorder? { lock.lock(); defer { lock.unlock() }; return recorders[id] }
}

nonisolated final class GPXZOfflineProtocol: URLProtocol, @unchecked Sendable {
    static let registry = GPXZOfflineRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let form = try GPXZOfflineForm.decode(request)
            guard let id = request.value(forHTTPHeaderField: "X-Offline-Test"), let recorder = Self.registry.get(id),
                  let encoded = form["latlons"], let samples = form["samples"], let count = Int(samples),
                  let url = request.url else { throw URLError(.notConnectedToInternet) }
            let path = try encoded.split(separator: "|").map { value -> GeoPoint in
                let pair = value.split(separator: ",")
                guard pair.count == 2, let lat = Double(pair[0]), let lon = Double(pair[1]) else { throw URLError(.badURL) }
                return GeoPoint(lat: lat, lon: lon)
            }
            recorder.record(path)
            let length = TerrainGeometry.chainages(path).last!
            let results: [[String: Any]] = recorder.mode == .invalid ? [] : (0..<count).map { i in
                let d = Double(i) / Double(count - 1) * length
                let p = TerrainGeometry.point(path, at: d)
                return ["elevation": d / 10, "lat": p.lat, "lon": p.lon, "data_source": "OFFLINE_FIXTURE", "resolution": 30]
            }
            let payload: [String: Any] = recorder.mode == .badRequest
                ? ["status": "INVALID_REQUEST", "error": "OFFLINE: samples rejected"]
                : ["status": "OK", "results": results]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let statusCode = recorder.mode == .badRequest ? 400 : recorder.mode == .httpFailure ? 503 : 200
            let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                           httpVersion: "HTTP/1.1", headerFields: ["X-DATASET-VERSION": "fixture"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error) // NEVER fall through to real networking.
        }
    }
}