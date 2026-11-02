import Foundation
import Testing
@testable import fairwayvector_golfpintheory

/// Regression SOURCE: compile only. All sessions forbid HTTP; all files are temporary fixtures.
@MainActor struct DevelopmentAPIMockTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ForbiddenNetworkProtocol.self]
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
        let client = GolfAPIClient(session: session(), cache: cache, mode: .mock, bundledSavedCourses: nil)
        #expect(client.isConfigured)
        for _ in [false, true] {
            let clubs = try await client.searchClubs(named: "Hills", country: "Sweden")
            #expect(clubs.count == 1)
            #expect(clubs[0].clubName == "Demo Hills")
            #expect(clubs[0].courses[0].courseID == DevelopmentGolfAPIFixtures.courseID)
            #expect(try await client.searchClubs(named: "Hills", country: "USA").isEmpty)
            #expect(try await client.searchClubs(named: "Other club", country: "Sweden").isEmpty)
            #expect(try await client.searchClubs(named: "Hills", country: "Sweden", region: "Other region").isEmpty)
            do {
                _ = try await client.loadCourse(id: "real-hills")
                Issue.record("Missing/corrupt real downloads must not return demo data under a real ID")
            } catch { #expect(error as? GolfAPIError == .savedCourseUnavailable("real-hills")) }
            let payload = try await client.loadCourse(id: DevelopmentGolfAPIFixtures.courseID)
            #expect(payload.detail.courseID == DevelopmentGolfAPIFixtures.courseID)
            #expect(payload.detail.clubName == "Demo Hills")
            #expect(payload.detail.numHoles == 18 && payload.detail.tees.count == 2)
            #expect(payload.coordinates.count == 90)
            #expect(try await client.checkForUpdates() == false)
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
        let client = GolfAPIClient(session: session(), cache: cache, mode: .mock, bundledSavedCourses: nil)
        for refresh in [false, true] {
            let clubs = try await client.searchClubs(named: "Hills", country: "Sweden")
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
            mode: .mock, bundledSavedCourses: bundle)
        for refresh in [false, true] {
            let clubs = try await client.searchClubs(named: "Hills", country: "Sweden")
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
}