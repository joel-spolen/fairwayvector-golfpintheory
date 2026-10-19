import Foundation
import Testing
@testable import fairwayvector_pintheory

/// Regression SOURCE: compile only. All sessions forbid HTTP; all files are temporary fixtures.
@MainActor struct DevelopmentAPIMockTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GPXZForbiddenNetworkProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func onlyExplicitLiveSettingEnablesProvider() {
        for setting in [nil, "", "mock", "$(GOLF_API_MODE)", "${GPXZ_API_MODE}", "liv", "true"] as [String?] {
            #expect(DevelopmentAPIConfiguration.Mode(setting: setting) == .mock)
        }
        #expect(DevelopmentAPIConfiguration.Mode(setting: "live") == .live)
        #expect(DevelopmentAPIConfiguration.Mode(setting: " LIVE ") == .live)
    }

    @Test func golfMockIgnoresKeysPreservesInvalidCacheAndNeverImpersonatesRealIDs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = GolfAPICache(directoryURL: root)
        let sentinel = Data("preserve live provider cache bytes".utf8)
        cache.writeSearch(sentinel, query: "Hills", country: "Sweden", region: "")
        cache.writeCourseDetail(sentinel, id: "real-hills")
        cache.writeCoordinates(sentinel, id: "real-hills")
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        let client = GolfAPIClient(session: session(), cache: cache, apiKey: "OFFLINE_EXISTING_KEY", mode: .mock, bundledSavedCourses: nil)
        #expect(client.isConfigured)
        for refresh in [false, true] {
            let clubs = try await client.searchClubs(named: "Hills", country: "Sweden", forceRefresh: refresh)
            #expect(clubs.count == 1)
            #expect(clubs[0].clubName == "Demo Hills")
            #expect(clubs[0].courses[0].courseID == DevelopmentGolfAPIFixtures.courseID)
            #expect(try await client.searchClubs(named: "Hills", country: "USA", forceRefresh: refresh).isEmpty)
            #expect(try await client.searchClubs(named: "Other club", country: "Sweden", forceRefresh: refresh).isEmpty)
            #expect(try await client.searchClubs(named: "Hills", country: "Sweden", region: "Other region", forceRefresh: refresh).isEmpty)
            do {
                _ = try await client.loadCourse(id: "real-hills")
                Issue.record("Missing/corrupt real downloads must not return demo data under a real ID")
            } catch { #expect(error as? GolfAPIError == .savedCourseUnavailable("real-hills")) }
            let payload = try await client.loadCourse(id: DevelopmentGolfAPIFixtures.courseID)
            #expect(payload.detail.courseID == DevelopmentGolfAPIFixtures.courseID)
            #expect(payload.detail.clubName == "Demo Hills")
            #expect(payload.detail.numHoles == 18 && payload.detail.tees.count == 2)
            #expect(payload.coordinates.count == 90)
            #expect(try await client.checkForUpdates(to: payload.detail) == false)
            _ = try await client.refreshCourse(id: DevelopmentGolfAPIFixtures.courseID)
        }
        #expect(cache.readSearch(query: "Hills", country: "Sweden", region: "") == sentinel)
        #expect(cache.readCourseDetail(id: "real-hills") == sentinel)
        #expect(cache.readCoordinates(id: "real-hills") == sentinel)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == before)
        let store = CourseStore(reference: DevelopmentGolfAPIFixtures.reference(), golfAPIClient: client)
        await store.load()
        #expect(store.reference.golfAPICourseID == DevelopmentGolfAPIFixtures.courseID)
        #expect(store.course?.holes.count == 18)
        #expect(store.course?.holes.allSatisfy { $0.path.count == 2 && $0.greenFront != nil && $0.greenBack != nil } == true)
        #expect(store.reference.location?.lat == 57.623)
        let redReference = DevelopmentGolfAPIFixtures.reference(teeID: "mock-red-v1", sex: "female")
        let payload = try await client.loadCourse(id: DevelopmentGolfAPIFixtures.courseID)
        let red = try GolfAPICourseBuilder.build(reference: redReference, payload: payload)
        #expect(redReference.teeName == "Demo Red")
        for hole in red.holes {
            #expect(abs(TerrainGeometry.length(hole.path[0], hole.path[1]) - hole.length) < 0.01)
        }
    }

    @Test func savedProviderCourseIsReadOnlyAndPrecedesDemoWithoutChangingIdentity() async throws {
        // Constructed regression fixture, NOT downloaded/genuine Hills data.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = GolfAPICache(directoryURL: root)
        let id = "offline-regression-course"
        var detail = DevelopmentGolfAPIFixtures.detailJSON(id: id)
        detail["clubID"] = "offline-regression-club"
        detail["clubName"] = nil // Saved search metadata supplies club/country names.
        detail["country"] = nil
        detail["courseName"] = "Offline regression fixture"
        detail["latitude"] = 57.625
        detail["longitude"] = 12.01
        let rawDetail = try JSONSerialization.data(withJSONObject: detail)
        var coordinates = try #require(JSONSerialization.jsonObject(with:
            DevelopmentGolfAPIFixtures.response(path: "/coordinates/\(DevelopmentGolfAPIFixtures.courseID)", queryItems: [])) as? [String: Any])
        coordinates["courseID"] = id
        let rawCoordinates = try JSONSerialization.data(withJSONObject: coordinates)
        let rawSearch = Data(#"{"clubs":[{"clubID":"offline-regression-club","clubName":"Cached Hills regression fixture","city":"Mölndal","state":"Västra Götaland","country":"Sweden","courses":[{"courseID":"offline-regression-course","courseName":"Offline regression fixture","numHoles":18,"hasGPS":1}]}]}"#.utf8)
        cache.writeSearch(rawSearch, query: "Hills", country: "Sweden", region: "")
        cache.writeCourseDetail(rawDetail, id: id)
        cache.writeCoordinates(rawCoordinates, id: id)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        let client = GolfAPIClient(session: session(), cache: cache, apiKey: "OFFLINE_EXISTING_KEY", mode: .mock, bundledSavedCourses: nil)
        for refresh in [false, true] {
            let clubs = try await client.searchClubs(named: "Hills", country: "Sweden", forceRefresh: refresh)
            #expect(clubs.map(\.clubName) == ["Cached Hills regression fixture", "Demo Hills"])
            #expect(try await client.loadCourseDetail(id: id, forceRefresh: refresh).courseID == id)
            #expect(try await client.loadCoordinates(id: id, forceRefresh: refresh).count == 90)
        }
        let reference = try #require(client.savedReferences.first)
        #expect(reference.golfAPICourseID == id && reference.location == GeoPoint(lat: 57.625, lon: 12.01))
        let store = CourseStore(reference: reference, golfAPIClient: client)
        await store.load()
        await store.refresh()
        #expect(store.reference == reference && store.course?.golfAPICourseID == id)
        #expect(store.terrainCourseID == "golfapi:\(id)")
        #expect(store.course?.holes.count == 18 && store.errorMessage == nil)
        #expect(cache.readSearch(query: "Hills", country: "Sweden", region: "") == rawSearch)
        #expect(cache.readCourseDetail(id: id) == rawDetail && cache.readCoordinates(id: id) == rawCoordinates)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == before)

        let missing = CourseStore(reference: .hills, golfAPIClient: client)
        #expect(missing.reference == .hills) // Never remap an OSM real reference either.
    }

    @Test func bundledRealHillsWorksWithEmptyCacheAndReadOnlyRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = BundledSavedCourseStore()
        let id = BundledSavedCourseStore.hillsCourseID
        let client = GolfAPIClient(session: session(), cache: GolfAPICache(directoryURL: root),
            apiKey: "IGNORED_OFFLINE_KEY", mode: .mock, bundledSavedCourses: bundle)
        for refresh in [false, true] {
            let clubs = try await client.searchClubs(named: "Hills", country: "Sweden", forceRefresh: refresh)
            let club = try #require(clubs.first)
            #expect(club.clubName == "Hills Golf & Sports Club")
            #expect(club.courses.map(\.courseID) == [id]) // Valley is not a saved download.
            #expect(clubs.last?.courses.first?.courseID == DevelopmentGolfAPIFixtures.courseID)
            let detail = try await client.loadCourseDetail(id: id, forceRefresh: refresh)
            #expect(detail.courseID == id && detail.numHoles == 18 && detail.tees.count == 6)
            #expect(try await client.loadCoordinates(id: id, forceRefresh: refresh).count == 121)
        }
        let references = client.savedReferences.filter { $0.golfAPICourseID == id }
        #expect(references.count == 11) // Five men's and six women's rated tees, unchanged.
        let reference = try #require(references.first { $0.golfAPITeeID == "185072" && $0.teeSex == "male" })
        #expect(reference.teeName == "62" && reference.courseRating == 74.7 && reference.slopeRating == 140)
        #expect(reference.location == GeoPoint(lat: 57.6213953, lon: 12.0125269))
        let exported = try #require(bundle.course(reference: reference))
        #expect(exported.holes.count == 18 && exported.golfAPICourseID == id)
        let store = CourseStore(reference: reference, golfAPIClient: client)
        await store.load()
        await store.refresh()
        #expect(store.reference == reference && store.terrainCourseID == "golfapi:\(id)")
        #expect(store.course?.holes == exported.holes && store.course?.fetchedAt == exported.fetchedAt)
        let payload = try #require(client.cachedPayload(id: id))
        for other in references where other != reference {
            #expect(bundle.course(reference: other) == nil) // Never reuse exact 62/Men export for another tee.
            let rebuilt = try GolfAPICourseBuilder.build(reference: other, payload: payload)
            #expect(rebuilt.holes.count == 18 && rebuilt.holes.map(\.path) == exported.holes.map(\.path))
        }
        let rawDetail = try #require(bundle.detail(id: id))
        let object = try #require(JSONSerialization.jsonObject(with: rawDetail) as? [String: Any])
        #expect(object["apiRequestsLeft"] == nil) // No account quota metadata in portable resources.
        #expect(bundle.detail(id: "0121690712297913687") == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func flatAndDurableSavedGeometryAreReadOnlyAndIdentityChecked() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        var reference = DevelopmentGolfAPIFixtures.reference()
        reference.golfAPICourseID = "offline-regression-geometry"
        let course = Course(golfAPICourseID: reference.golfAPICourseID, name: "Regression geometry",
            holes: [Hole(number: 1, par: 4, path: [GeoPoint(lat: 57.62, lon: 12), GeoPoint(lat: 57.623, lon: 12)], green: [])], fetchedAt: .now)
        let bytes = try JSONEncoder().encode(course)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let filename = "course-\(reference.cacheKey)-golfapi-v1.json"
        let flat = support.appendingPathComponent(filename)
        try bytes.write(to: flat)
        #expect(CourseDataStore.readCourse(reference: reference, applicationSupport: support)?.golfAPICourseID == reference.golfAPICourseID)
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("CourseData").path))
        #expect(try Data(contentsOf: flat) == bytes)
        let directory = CourseDataStore.directory(courseID: "golfapi:\(reference.golfAPICourseID!)", root: support.appendingPathComponent("CourseData"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let durable = directory.appendingPathComponent(filename)
        try bytes.write(to: durable)
        try FileManager.default.removeItem(at: flat)
        #expect(CourseDataStore.readCourse(reference: reference, applicationSupport: support)?.holes.count == 1)
        #expect(try Data(contentsOf: durable) == bytes)
        var wrong = course
        wrong.golfAPICourseID = "wrong-provider-id"
        try JSONEncoder().encode(wrong).write(to: durable)
        #expect(CourseDataStore.readCourse(reference: reference, applicationSupport: support) == nil)
    }

    @Test func terrainSendGatePrecedesDispatchEvenForLiveRequest() async throws {
        let client = GPXZElevationClient(key: "OFFLINE_EXISTING_KEY", session: session(), mode: .mock)
        #expect(client.key.isEmpty)
        let path = [GeoPoint(lat: 57.623, lon: 12), GeoPoint(lat: 57.626, lon: 12.001)]
        let request = URLRequest(url: URL(string: "https://api.gpxz.io/v1/elevation/sample")!)
        let record = try await client.send(request, path: path, count: 100, dispatch: { _ in
            Issue.record("Mock must never enter the URLSession dispatch gate")
            return false
        })
        #expect(record.samples.count == 100)
        #expect(record.samples.first?.point == path.first && record.samples.last?.point == path.last)
        #expect(record.samples.allSatisfy { $0.elevationMeters?.isFinite == true && $0.provenance.allSatisfy(\.isSynthetic) })
        #expect(record.samples.first?.provenance.first?.captureDateMin == nil)
        #expect(try client.request(path: path).0.value(forHTTPHeaderField: "x-api-key") == nil)
        let reverse = try GPXZElevationClient.syntheticRecord(path: path.reversed(), count: 100)
        #expect(reverse.samples.first?.elevationMeters == record.samples.last?.elevationMeters)
        #expect(reverse.samples.last?.elevationMeters == record.samples.first?.elevationMeters)
    }

    @Test func mockRepositoryPreservesFiveCallLedgerLocksAndLiveTerrainAcrossReopenRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = "golfapi:real-hills", directory = CourseDataStore.directory(courseID: id, root: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let liveSidecar = directory.appendingPathComponent("terrain-gpxz-v1.json")
        let liveBytes = Data("even corrupt live terrain must never be read or repaired in mock".utf8)
        try liveBytes.write(to: liveSidecar)
        let ledgerURL = root.appendingPathComponent("ledger.json")
        let ledgerBytes = Data(#"{"schemaVersion":1,"months":{"2026-10":5},"failedRequests":{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":"historical 400"}}"#.utf8)
        try ledgerBytes.write(to: ledgerURL)
        let marker = ledgerURL.appendingPathExtension("initialized"), markerBytes = Data("untouched marker".utf8)
        try markerBytes.write(to: marker)
        let client = GPXZElevationClient(key: "OFFLINE_EXISTING_KEY", session: session(), mode: .mock)
        let path = [GeoPoint(lat: 57.623, lon: 12), GeoPoint(lat: 57.625, lon: 12)]
        for _ in 0..<2 {
            let repo = GPXZTerrainRepository(root: root, client: client, ledgerURL: ledgerURL)
            for paid in [false, true] {
                let result = await repo.profile(courseID: id, path: path, straight: true, allowPaid: paid,
                    maySend: { false }, dispatch: { _ in Issue.record("Mock must not dispatch"); return false })
                #expect(result.message == nil && result.quota == nil && result.plannedCalls == 0)
                #expect(result.profile?.samples.allSatisfy { $0.elevationMeters != nil } == true)
            }
            let reverse = await repo.profile(courseID: id, path: path.reversed(), straight: true)
            #expect(reverse.profile?.samples.first?.point == path.last)
            let subpath = [TerrainGeometry.interpolate(path[0], path[1], 0.25), TerrainGeometry.interpolate(path[0], path[1], 0.75)]
            let subsection = await repo.profile(courseID: id, path: subpath, straight: true)
            #expect(subsection.message == nil && subsection.plannedCalls == 0)
            #expect(subsection.profile?.samples.allSatisfy { $0.elevationMeters != nil } == true)
            #expect(await repo.prepareExplicitRetry() == nil)
            #expect(try Data(contentsOf: ledgerURL) == ledgerBytes)
            #expect(try Data(contentsOf: marker) == markerBytes)
            #expect(try Data(contentsOf: liveSidecar) == liveBytes)
        }
        let syntheticID = DevelopmentAPIConfiguration.terrainNamespace + id
        let sidecar = CourseDataStore.directory(courseID: syntheticID, root: root).appendingPathComponent("terrain-synthetic-development-v1.json")
        let cache = try JSONDecoder().decode(TerrainCourseCache.self, from: Data(contentsOf: sidecar))
        try cache.validate(expectedID: syntheticID)
        #expect(cache.responses.count == 1) // Overlap/reversal/relaunch use the same saved synthetic coverage.
        let noLedgerURL = root.appendingPathComponent("never-initialized.json")
        let fresh = GPXZTerrainRepository(root: root, client: client, ledgerURL: noLedgerURL)
        _ = await fresh.profile(courseID: "other-live-id", path: path, straight: true)
        #expect(!FileManager.default.fileExists(atPath: noLedgerURL.path))
        #expect(!FileManager.default.fileExists(atPath: noLedgerURL.appendingPathExtension("initialized").path))
    }
}