import Foundation
import Testing
@testable import fairwayvector_golfpintheory

private final class GolfAPIStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        guard let handler = Self.handler else { return }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct GolfAPITests {
    @Test func courseSearchAcceptsLongTypedAndPastedText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = makeClient(directory: directory) { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = items.first { $0.name == "q" }?.value
            #expect(query == String(repeating: "Å", count: 75))
            return (200, Data(#"{"clubs":[]}"#.utf8))
        }
        for purpose in [GolfAPICourseSelectionModel.Purpose.map, .handicap] {
            let model = GolfAPICourseSelectionModel(client: client, purpose: purpose)
            model.searchText = "Short search"
            #expect(model.searchText == "Short search")
            model.searchText = String(repeating: "Å", count: 75)
            #expect(model.searchText == String(repeating: "Å", count: 75))
            await model.search()
            model.searchText = String(repeating: "👩🏽‍💻", count: 21)
            #expect(model.searchText == String(repeating: "👩🏽‍💻", count: 21))
            model.searchText = ""
            #expect(model.searchText.isEmpty)
        }
        #expect(GolfAPIStubProtocol.requestCount == 2)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func coverageRegionCountryCountsMatchPublishedCoverageList() {
        let counts = Dictionary(uniqueKeysWithValues: GolfAPICoverage.regions.map { ($0.name, $0.countries.count) })
        #expect(counts["North America"] == 24)
        #expect(counts["USA + Canada"] == 2)
        #expect(counts["Europe"] == 40)
        #expect(counts["Asia"] == 41)
        #expect(counts["Australia/Oceania"] == 8)
        #expect(counts["Latin America and the Caribbean"] == 35)
        #expect(counts["Africa"] == 36)
        #expect(GolfAPICoverage.regions.first { $0.name == "Europe" }?.countries.contains("Sweden") == true)
    }

    private let courseDetailJSON = #"""
    {
      "courseID":"course-123",
      "clubID":"club-1",
      "clubName":"Åre Golfklubb",
      "courseName":"Åre GK",
      "city":"Åre",
      "state":"Jämtland",
      "country":"Sweden",
      "numHoles":"2",
      "measure":"y",
      "timestampUpdated":"1700000000",
      "hasGPS":"1",
      "parsMen":[4,3],
      "indexesMen":[7,15],
      "parsWomen":[5,3],
      "indexesWomen":[8,16],
      "tees":[
        {"teeID":"tee-blue","teeName":"Blue","teeColor":"#00CCFF","length1":380,"length2":150,"courseRatingMen":70.1,"slopeMen":125,"courseRatingWomen":"","slopeWomen":""},
        {"teeID":"tee-red","teeName":"Red","teeColor":"#FF5050","length1":340,"length2":130,"courseRatingMen":66.2,"slopeMen":112,"courseRatingWomen":71.0,"slopeWomen":120}
      ]
    }
    """#

    private let coordinatesJSON = #"""
    {
      "courseID":"course-123",
      "numCoordinates":10,
      "coordinates":[
        {"poi":11,"hole":1,"latitude":63.40,"longitude":13.08},
        {"poi":12,"hole":1,"latitude":63.401,"longitude":13.081},
        {"poi":1,"location":1,"hole":1,"latitude":63.41,"longitude":13.09},
        {"poi":1,"location":2,"hole":1,"latitude":63.411,"longitude":13.091},
        {"poi":1,"location":3,"hole":1,"latitude":63.412,"longitude":13.092},
        {"poi":11,"hole":2,"latitude":63.42,"longitude":13.10},
        {"poi":12,"hole":2,"latitude":63.421,"longitude":13.101},
        {"poi":1,"location":1,"hole":2,"latitude":63.43,"longitude":13.11},
        {"poi":1,"location":2,"hole":2,"latitude":63.431,"longitude":13.111},
        {"poi":1,"location":3,"hole":2,"latitude":63.432,"longitude":13.112}
      ]
    }
    """#

    private func makeClient(directory: URL, handler: @escaping (URLRequest) -> (Int, Data)) -> GolfAPIClient {
        GolfAPIStubProtocol.handler = handler
        GolfAPIStubProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GolfAPIStubProtocol.self]
        return GolfAPIClient(
            session: URLSession(configuration: configuration),
            cache: GolfAPICache(directoryURL: directory),
            projectURL: URL(string: "https://edge.example.test")!,
            mode: .live // Explicit transport evaluation; this session intercepts every request offline.
        )
    }

    @Test func decodesSearchAndCourseMetadataWithStringAndNumericFields() throws {
        let data = Data(#"{"apiRequestsLeft":"90.8","numClubs":1,"clubs":[{"clubID":"club-1","clubName":"Åre Golfklubb","city":"Åre","state":"Jämtland","country":"Sweden","courses":[{"courseID":"course-123","courseName":"Åre GK","numHoles":"2","hasGPS":"1"}]}]}"#.utf8)
        let search = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let clubs = try #require(search["clubs"] as? [[String: Any]])
        #expect(clubs.count == 1)
        #expect(clubs[0]["clubName"] as? String == "Åre Golfklubb")

        let detail = try GolfAPICourseDetail(json: JSONSerialization.jsonObject(with: Data(courseDetailJSON.utf8)) as! [String: Any])
        #expect(detail.numHoles == 2)
        #expect(detail.parsMen == [4, 3])
        #expect(detail.indexesWomen == [8, 16])
        #expect(detail.tees.first?.rating(for: "male") == 70.1)
        #expect(detail.tees.first?.rating(for: "female") == nil)
        #expect(detail.tees.first?.lengthsMeters[0] == 380 * 0.9144)
    }

    @Test func providerDataEndpointsAreFixedToSupabaseEdgeFunction() throws {
        let project = URL(string: "https://project.example.test")!
        let golf = try #require(SupabaseProviderEndpoint.dataURL(projectURL: project, route: "/golf/clubs"))
        let elevation = try #require(SupabaseProviderEndpoint.dataURL(projectURL: project, route: "/elevation/sample"))
        #expect(golf.absoluteString == "https://project.example.test/functions/v1/golf-data/api/v1/golf/clubs")
        #expect(elevation.absoluteString == "https://project.example.test/functions/v1/golf-data/api/v1/elevation/sample")
        #expect(SupabaseProviderEndpoint.dataURL(projectURL: URL(string: "http://project.example.test"), route: "/golf/clubs") == nil)
        #expect(SupabaseProviderEndpoint.dataURL(projectURL: project, route: "//api.gpxz.io/v1/elevation/sample") == nil)
    }

    @Test func buildsPointOnlyHolesWithRatingsParIndexesAndTeeLengths() throws {
        let detail = try GolfAPICourseDetail(json: JSONSerialization.jsonObject(with: Data(courseDetailJSON.utf8)) as! [String: Any])
        let coordObject = try JSONSerialization.jsonObject(with: Data(coordinatesJSON.utf8)) as! [String: Any]
        let rawCoordinates = try #require(coordObject["coordinates"] as? [[String: Any]])
        let coordinates = rawCoordinates.compactMap(GolfAPICoordinate.init(json:))
        let payload = GolfAPICoursePayload(detail: detail, coordinates: coordinates)
        let club = GolfAPIClub(clubID: "club-1", clubName: "Åre Golfklubb", city: "Åre", state: "Jämtland", country: "Sweden", courses: [])
        let summary = GolfAPICourseSummary(courseID: "course-123", courseName: "Åre GK", numHoles: 2, hasGPS: true, timestampUpdated: detail.timestampUpdated)
        let selection = GolfAPICourseSelection(club: club, course: summary, details: detail, tee: detail.tees[0], sex: "male")
        let course = try GolfAPICourseBuilder.build(reference: selection.reference, payload: payload)

        #expect(course.golfAPICourseID == "course-123")
        #expect(course.holes.count == 2)
        #expect(course.holes[0].par == 4)
        #expect(course.holes[1].handicapIndex == 15)
        #expect(course.holes[0].green.isEmpty)
        #expect(course.holes[0].usesPointOnlyGeometry)
        #expect(course.holes[0].greenFront == GeoPoint(lat: 63.41, lon: 13.09))
        #expect(course.holes[0].greenCenter == GeoPoint(lat: 63.411, lon: 13.091))
        #expect(course.holes[0].length == 380 * 0.9144)
    }

    @Test func courseDetailsArePersistedAndDoNotRepeatPaidRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = Data(courseDetailJSON.utf8)
        let client = makeClient(directory: directory) { request in
            #expect(request.url?.host == "edge.example.test")
            #expect(request.url?.path == "/functions/v1/golf-data/api/v1/golf/courses/course-123")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
            return (200, response)
        }

        _ = try await client.loadCourseDetail(id: "course-123")
        _ = try await client.loadCourseDetail(id: "course-123")
        #expect(GolfAPIStubProtocol.requestCount == 1)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func courseAndCoordinatePayloadsAreBothCached() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let detailData = Data(courseDetailJSON.utf8)
        let coordinateData = Data(coordinatesJSON.utf8)
        let client = makeClient(directory: directory) { request in
            switch request.url?.path {
            case "/functions/v1/golf-data/api/v1/golf/courses/course-123": (200, detailData)
            case "/functions/v1/golf-data/api/v1/golf/coordinates/course-123": (200, coordinateData)
            default: (404, Data())
            }
        }

        let first = try await client.loadCourse(id: "course-123")
        let second = try await client.loadCourse(id: "course-123")
        #expect(first.detail.courseName == second.detail.courseName)
        #expect(first.coordinates.count == second.coordinates.count)
        #expect(GolfAPIStubProtocol.requestCount == 2)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func refreshingCourseUsesOnlyDetailAndCoordinateEndpointsNotSearch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = makeClient(directory: directory) { request in
            switch request.url?.path {
            case "/functions/v1/golf-data/api/v1/golf/courses/course-123":
                return (200, Data(courseDetailJSON.utf8))
            case "/functions/v1/golf-data/api/v1/golf/coordinates/course-123":
                return (200, Data(coordinatesJSON.utf8))
            default:
                Issue.record("Course refresh must not call GolfAPI search endpoints")
                return (404, Data())
            }
        }
        let refreshed = try await client.refreshCourse(id: "course-123")
        #expect(refreshed.detail.courseID == "course-123")
        #expect(refreshed.coordinates.count == 10)
        #expect(GolfAPIStubProtocol.requestCount == 2)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func server503ExplainsSafeFailureCodeAndDownloadStageWithoutRetry() async throws {
        for code in ["provider_disabled", "provider_not_configured", "daily_budget_exceeded",
                     "provider_cooldown", "request_pending", "ambiguous_attempt", "cache_write_rejected"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let body = try JSONSerialization.data(withJSONObject: [
                "error": ["code": code, "message": "PRIVATE_CREDENTIAL_DO_NOT_DISPLAY"]
            ])
            let client = makeClient(directory: directory) { _ in (503, body) }
            do {
                _ = try await client.loadCoordinates(id: "course-123")
                Issue.record("A service failure must not be treated as a downloaded course")
            } catch {
                #expect(error as? GolfAPIError == .dataService(status: 503, code: code,
                    stage: "course GPS coordinates"))
                #expect(!error.localizedDescription.contains("PRIVATE_CREDENTIAL"))
            }
            #expect(GolfAPIStubProtocol.requestCount == 1)
            GolfAPIStubProtocol.handler = nil
        }
    }

    @Test func unknown503ErrorCodeAndRawMessageAreNotDisplayed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = Data(#"{"error":{"code":"PRIVATE_SECRET","message":"private credentials"}}"#.utf8)
        let client = makeClient(directory: directory) { _ in (503, body) }
        do {
            _ = try await client.loadCourseDetail(id: "course-123")
            Issue.record("Expected a service error")
        } catch {
            #expect(error as? GolfAPIError == .dataService(status: 503,
                code: "service_unavailable", stage: "course details and tees"))
            #expect(!error.localizedDescription.contains("PRIVATE_SECRET"))
        }
        GolfAPIStubProtocol.handler = nil
    }

    @Test func unavailableGPSSelectionClearsPreviousCourseWithoutRequestingDownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let detailData = Data(courseDetailJSON.utf8)
        let coordinateData = Data(coordinatesJSON.utf8)
        let client = makeClient(directory: directory) { request in
            request.url?.path.contains("/coordinates/") == true ? (200, coordinateData) : (200, detailData)
        }
        let available = GolfAPICourseSummary(courseID: "course-123", courseName: "Available",
            numHoles: 2, hasGPS: true, timestampUpdated: nil)
        let unavailable = GolfAPICourseSummary(courseID: "unavailable-course", courseName: "Unavailable",
            numHoles: 9, hasGPS: false, timestampUpdated: nil)
        let model = GolfAPICourseSelectionModel(client: client)
        model.selectClub(GolfAPIClub(clubID: "club-1", clubName: "Club", city: nil, state: nil,
            country: "Sweden", courses: [available, unavailable]))
        await model.selectCourse(available)
        #expect(model.selection != nil)
        let count = GolfAPIStubProtocol.requestCount
        await model.selectCourse(unavailable)
        #expect(model.selectedCourseID == unavailable.courseID)
        #expect(model.selection == nil)
        #expect(model.courseDetail == nil)
        #expect(model.errorMessage?.contains("GPS data not available") == true)
        #expect(GolfAPIStubProtocol.requestCount == count)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func unratedDownloadedCourseCanBeExploredButCannotEnterHandicap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var object = try #require(JSONSerialization.jsonObject(with: Data(courseDetailJSON.utf8)) as? [String: Any])
        var tees = try #require(object["tees"] as? [[String: Any]])
        for index in tees.indices {
            for key in ["courseRatingMen", "slopeMen", "courseRatingWomen", "slopeWomen"] {
                tees[index].removeValue(forKey: key)
            }
        }
        object["tees"] = tees
        let cache = GolfAPICache(directoryURL: directory)
        try cache.persistCourseDetail(JSONSerialization.data(withJSONObject: object), id: "course-123")
        try cache.persistCoordinates(Data(coordinatesJSON.utf8), id: "course-123")
        let client = GolfAPIClient(cache: cache, projectURL: URL(string: "https://edge.example.test"),
            mode: .live, bundledSavedCourses: nil)
        let summary = GolfAPICourseSummary(courseID: "course-123", courseName: "Unrated GPS course",
            numHoles: 2, hasGPS: true, timestampUpdated: nil)
        let club = GolfAPIClub(clubID: "club-1", clubName: "Club", city: nil, state: nil,
            country: "Sweden", courses: [summary])
        let map = GolfAPICourseSelectionModel(client: client)
        map.selectClub(club)
        await map.selectCourse(summary)
        #expect(map.errorMessage == nil)
        #expect(map.ratedTees.isEmpty)
        #expect(map.selectableTees.count == 2)
        let selection = try #require(map.selection)
        let payload = try #require(client.cachedPayload(id: summary.courseID))
        #expect(try GolfAPICourseBuilder.build(reference: selection.reference, payload: payload).holes.count == 2)
        #expect(selection.tee.rating(for: selection.sex) == nil)
        #expect(throws: (any Error).self) {
            try HCPProviderCourse.convert(detail: selection.details, tee: selection.tee, sex: selection.sex)
        }
        let handicap = GolfAPICourseSelectionModel(client: client, purpose: .handicap)
        handicap.selectClub(club)
        await handicap.selectCourse(summary)
        #expect(handicap.selectableTees.isEmpty)
        #expect(handicap.selection == nil)
        #expect(handicap.errorMessage != nil)
    }

    @Test func catalogSearchUsesSupabaseAndDoesNotPersistSearchResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = GolfAPICache(directoryURL: directory)
        legacy.writeSearch(Data(#"{"clubs":[{"clubID":"stale","clubName":"Old cache","courses":[]}]}"#.utf8),
            query: "Åre", country: "Sweden", region: "")
        let response = Data(#"{"datasetVersion":"catalog-v1","numClubs":1,"numAllClubs":1,"page":1,"pageSize":50,"hasMore":false,"clubs":[{"clubID":"club-1","clubName":"Pebble Links","city":"Pebble Beach","state":"CA","country":"USA","courses":[{"courseID":"course-1","courseName":"Pebble Beach","numHoles":18,"hasGPS":1}]}]}"#.utf8)
        let client = makeClient(directory: directory) { request in
            #expect(request.url?.path == "/functions/v1/golf-data/api/v1/catalog/clubs")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(items.first { $0.name == "q" }?.value == "Pebble Be")
            #expect(items.first { $0.name == "country" }?.value == "USA")
            #expect(items.first { $0.name == "page" }?.value == "1")
            #expect(request.url?.host == "edge.example.test")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
            return (200, response)
        }

        let first = try await client.searchCatalogClubs(named: "Pebble Be", country: "USA", page: 1)
        let second = try await client.searchCatalogClubs(named: "Pebble Be", country: "USA", page: 1)
        #expect(first.clubs == second.clubs)
        #expect(first.clubs.first?.clubName == "Pebble Links")
        #expect(first.clubs.first?.courses.first?.courseName == "Pebble Beach")
        #expect(first.numAllClubs == 1 && !first.hasMore)
        #expect(GolfAPICache(directoryURL: directory).readSearch(query: "Åre", country: "Sweden", region: "") == nil)
        #expect(GolfAPIStubProtocol.requestCount == 2)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func catalogSearchPagesStayInMemoryAndLoadMoreDoesNotCallGolfAPI() async throws {
        #expect(GolfAPICourseSelectionModel.catalogPageSize == 10)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Data(#"{"datasetVersion":"catalog-v1","numClubs":2,"numAllClubs":3,"page":1,"pageSize":2,"hasMore":true,"clubs":[{"clubID":"club-1","clubName":"One","country":"Sweden","courses":[]},{"clubID":"club-2","clubName":"Two","country":"Sweden","courses":[]}] }"#.utf8)
        let second = Data(#"{"datasetVersion":"catalog-v1","numClubs":1,"numAllClubs":3,"page":2,"pageSize":2,"hasMore":false,"clubs":[{"clubID":"club-3","clubName":"Three","country":"Sweden","courses":[]}] }"#.utf8)
        let client = makeClient(directory: directory) { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "page" }?.value
            #expect(request.url?.path.hasSuffix("/catalog/clubs") == true)
            return page == "1" ? (200, first) : (200, second)
        }
        let model = GolfAPICourseSelectionModel(client: client, purpose: .map, pageSize: 2)
        model.selectedCountry = "Sweden"
        model.searchText = ""
        await model.search()
        #expect(model.errorMessage == nil)
        #expect(model.clubs.map(\.clubID) == ["club-1", "club-2"])
        #expect(model.totalClubCount == 3 && model.hasMoreClubs)
        await model.loadMoreClubs()
        #expect(model.errorMessage == nil)
        #expect(model.clubs.map(\.clubID) == ["club-1", "club-2", "club-3"])
        #expect(model.totalClubCount == 3 && !model.hasMoreClubs)
        #expect(GolfAPICache(directoryURL: directory).searchData().isEmpty)
        #expect(GolfAPIStubProtocol.requestCount == 2)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func regionSearchSendsExactSelectedCountriesAndSearchPhrase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = makeClient(directory: directory) { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = items.first { $0.name == "q" }?.value
            let countries = items.first { $0.name == "countries" }?.value?.split(separator: "|").map(String.init) ?? []
            #expect(query == "Pebble Be")
            #expect(countries == GolfAPICoverage.regions.first { $0.name == "North America" }?.countries.sorted())
            #expect(items.first { $0.name == "country" } == nil)
            return (200, Data(#"{"datasetVersion":"catalog-v1","numClubs":0,"numAllClubs":0,"page":1,"pageSize":10,"hasMore":false,"clubs":[]}"#.utf8))
        }
        let model = GolfAPICourseSelectionModel(client: client)
        model.selectRegion("North America")
        model.searchText = "Pebble Be"
        await model.search()
        #expect(model.errorMessage?.contains("No golf clubs matched") == true)
        #expect(GolfAPIStubProtocol.requestCount == 1)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func liveCatalogClientDeletesLegacySearchFilesButKeepsCourseFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = GolfAPICache(directoryURL: directory)
        cache.writeSearch(Data(#"{"clubs":[]}"#.utf8), query: "Legacy", country: "Sweden", region: "")
        cache.writeCourseDetail(Data(courseDetailJSON.utf8), id: "course-123")
        cache.writeCoordinates(Data(coordinatesJSON.utf8), id: "course-123")
        #expect(!cache.searchData().isEmpty)
        #expect(cache.readCourseDetail(id: "course-123") != nil)
        #expect(cache.readCoordinates(id: "course-123") != nil)

        _ = GolfAPIClient(cache: cache, projectURL: URL(string: "https://edge.example.test"),
            mode: .live, bundledSavedCourses: nil)
        #expect(cache.searchData().isEmpty)
        #expect(cache.readCourseDetail(id: "course-123") != nil)
        #expect(cache.readCoordinates(id: "course-123") != nil)
    }

    @Test func accountCourseCacheKeepsOnlyFiveRecentSelectedCourses() async throws {
        let accountDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: accountDirectory) }
        let previousDirectory = AccountCourseStorage.accountDirectory
        AccountCourseStorage.configure(accountDirectory: accountDirectory)
        defer { AccountCourseStorage.configure(accountDirectory: previousDirectory) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GolfAPIStubProtocol.self]
        GolfAPIStubProtocol.requestCount = 0
        GolfAPIStubProtocol.handler = { request in
            let id = String(request.url!.lastPathComponent)
            let payload = courseDetailJSON.replacingOccurrences(of: "course-123", with: id)
            return (200, Data(payload.utf8))
        }
        let client = GolfAPIClient(session: URLSession(configuration: configuration), cache: GolfAPICache(),
            projectURL: URL(string: "https://edge.example.test"), mode: .live, bundledSavedCourses: nil)
        let cacheDirectory = accountDirectory.appendingPathComponent("GolfAPI", isDirectory: true)
        let firstGeometry = CourseDataStore.directory(courseID: "golfapi:course-1")
        try FileManager.default.createDirectory(at: firstGeometry, withIntermediateDirectories: true)
        try Data("fixture geometry".utf8).write(to: firstGeometry.appendingPathComponent("course.json"))

        for number in 1...6 {
            let id = "course-\(number)"
            #expect(try await client.loadCourseDetail(id: id).courseID == id)
        }
        #expect(CourseDataStore.savedProviderCourseIDs() == Set((2...6).map { "course-\($0)" }))
        let persistedCache = GolfAPICache(directoryURL: cacheDirectory)
        #expect(persistedCache.readCourseDetail(id: "course-1") == nil)
        #expect(persistedCache.readCourseDetail(id: "course-6") != nil)
        #expect(!FileManager.default.fileExists(atPath: firstGeometry.path))
        GolfAPIStubProtocol.handler = nil
    }

    @Test func accountSwitchUsesSeparatePersistentCourseCacheRoots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = AccountCourseStorage.accountDirectory
        defer { AccountCourseStorage.configure(accountDirectory: original) }
        let first = root.appendingPathComponent("account-one", isDirectory: true)
        let second = root.appendingPathComponent("account-two", isDirectory: true)

        AccountCourseStorage.configure(accountDirectory: first)
        GolfAPICache().writeCourseDetail(Data(courseDetailJSON.utf8), id: "course-123")
        #expect(GolfAPICache().readCourseDetail(id: "course-123") != nil)
        let firstGeometry = CourseDataStore.directory(courseID: "golfapi:course-123")

        AccountCourseStorage.configure(accountDirectory: second)
        #expect(GolfAPICache().readCourseDetail(id: "course-123") == nil)
        let secondGeometry = CourseDataStore.directory(courseID: "golfapi:course-123")
        #expect(firstGeometry != secondGeometry)
        #expect(firstGeometry.path.hasPrefix(first.path))
        #expect(secondGeometry.path.hasPrefix(second.path))
        AccountCourseStorage.configure(accountDirectory: first)
        #expect(GolfAPICache().readCourseDetail(id: "course-123") != nil)
    }

    @Test func searchCacheUsesNFCWithoutConflatingDistinctFilters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = GolfAPICache(directoryURL: directory)
        let empty = Data(#"{"clubs":[]}"#.utf8)
        cache.writeSearch(empty, query: " A\u{030A}re ", country: "Sweden", region: "")
        #expect(cache.readSearch(query: "Åre", country: "Sweden", region: "") == empty)
        #expect(cache.readSearch(query: "Are", country: "Sweden", region: "") == nil)
        #expect(cache.readSearch(query: "Åre", country: "Norway", region: "") == nil)
    }

    @Test func selectingMapCourseDownloadsDetailsAndCoordinatesThenReopensOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let detailData = Data(courseDetailJSON.utf8)
        let coordinateData = Data(coordinatesJSON.utf8)
        let client = makeClient(directory: directory) { request in
            switch request.url?.path {
            case "/functions/v1/golf-data/api/v1/golf/courses/course-123": (200, detailData)
            case "/functions/v1/golf-data/api/v1/golf/coordinates/course-123": (200, coordinateData)
            default: (404, Data())
            }
        }
        let course = GolfAPICourseSummary(courseID: "course-123", courseName: "Åre GK",
            numHoles: 2, hasGPS: true, timestampUpdated: nil)
        let club = GolfAPIClub(clubID: "club-1", clubName: "Åre Golfklubb", city: "Åre",
            state: "Jämtland", country: "Sweden", courses: [course])
        let model = GolfAPICourseSelectionModel(client: client)
        model.selectClub(club)
        await model.selectCourse(course)
        #expect(model.errorMessage == nil)
        #expect(GolfAPIStubProtocol.requestCount == 2)
        #expect(model.selection != nil)
        let reopened = GolfAPIClient(cache: GolfAPICache(directoryURL: directory),
            projectURL: URL(string: "https://edge.example.test"), mode: .live, bundledSavedCourses: nil)
        #expect(reopened.cachedPayload(id: "course-123")?.coordinates.count == 10)
        let offlineModel = GolfAPICourseSelectionModel(client: reopened)
        offlineModel.selectClub(club)
        await offlineModel.selectCourse(course)
        #expect(offlineModel.errorMessage == nil)
        #expect(GolfAPIStubProtocol.requestCount == 2)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func handicapDetailsAreReusedWhenMapAndPlayNeedCoordinates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let detailData = Data(courseDetailJSON.utf8)
        let coordinateData = Data(coordinatesJSON.utf8)
        let client = makeClient(directory: directory) { request in
            switch request.url?.path {
            case "/functions/v1/golf-data/api/v1/golf/courses/course-123": (200, detailData)
            case "/functions/v1/golf-data/api/v1/golf/coordinates/course-123": (200, coordinateData)
            default: (404, Data())
            }
        }
        let course = GolfAPICourseSummary(courseID: "course-123", courseName: "Åre GK",
            numHoles: 2, hasGPS: true, timestampUpdated: nil)
        let club = GolfAPIClub(clubID: "club-1", clubName: "Åre Golfklubb", city: "Åre",
            state: "Jämtland", country: "Sweden", courses: [course])

        // HCP first needs ratings/detail only: one Edge request, no coordinates.
        let handicapDetails = try await client.loadCourseDetail(id: course.courseID)
        #expect(handicapDetails.tees.first?.teeID == "tee-blue")
        #expect(GolfAPIStubProtocol.requestCount == 1)

        // Explore reuses that cached detail and downloads the missing map geometry.
        let explore = GolfAPICourseSelectionModel(client: client, purpose: .map)
        explore.selectClub(club)
        await explore.selectCourse(course)
        #expect(explore.selection != nil)
        #expect(GolfAPIStubProtocol.requestCount == 2)

        // Play's CourseStore uses the same client cache, so it needs no third fetch.
        let store = CourseStore(reference: try #require(explore.selection).reference,
            golfAPIClient: client)
        await store.load()
        #expect(store.course?.holes.count == 2)
        #expect(store.errorMessage == nil)
        #expect(GolfAPIStubProtocol.requestCount == 2)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func downloadReportsLocalStorageFailure() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let detailData = Data(courseDetailJSON.utf8)
        let client = makeClient(directory: file) { _ in (200, detailData) }
        do {
            _ = try await client.loadCourseDetail(id: "course-123")
            Issue.record("A failed local save must not report a completed course download")
        } catch { #expect(error as? GolfAPIError == .localStorageUnavailable) }
        GolfAPIStubProtocol.handler = nil
    }

    @Test func courseSearchUsesCatalogFiltersAndNeverGolfAPISearchEndpoint() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = makeClient(directory: directory) { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(query["country"] == "Sweden")
            #expect(query["state"] == "Jämtland")
            #expect(query["q"] == "Åre")
            #expect(query["page"] == "1")
            #expect(request.url?.path == "/functions/v1/golf-data/api/v1/catalog/clubs")
            return (200, Data(#"{"datasetVersion":"catalog-v1","numClubs":0,"numAllClubs":0,"page":1,"pageSize":50,"hasMore":false,"clubs":[]}"#.utf8))
        }

        _ = try await client.searchClubs(named: "Åre", country: "Sweden", region: "Jämtland")
        #expect(GolfAPIStubProtocol.requestCount == 1)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func missingSupabaseConfigurationFailsBeforeNetworkRequest() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        GolfAPIStubProtocol.handler = { _ in (200, Data(#"{"clubs":[]}"#.utf8)) }
        GolfAPIStubProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GolfAPIStubProtocol.self]
        let noKeyClient = GolfAPIClient(
            session: URLSession(configuration: configuration),
            cache: GolfAPICache(directoryURL: directory),
            projectURL: URL(string: "http://edge.example.test"),
            mode: .live
        )

        do {
            _ = try await noKeyClient.searchClubs(named: "Åre", country: "Sweden")
            Issue.record("Expected missing Supabase project configuration")
        } catch let error as GolfAPIError {
            #expect(error == .missingDataServiceConfiguration)
            #expect(GolfAPIStubProtocol.requestCount == 0)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        GolfAPIStubProtocol.handler = nil
    }
}
