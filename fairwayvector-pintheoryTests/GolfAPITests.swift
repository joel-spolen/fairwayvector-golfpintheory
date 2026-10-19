import Foundation
import Testing
@testable import fairwayvector_pintheory

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
            apiKey: "unit-test-key",
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
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-key")
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
            case "/api/v2.3/courses/course-123": (200, detailData)
            case "/api/v2.3/coordinates/course-123": (200, coordinateData)
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

    @Test func clubSearchIsCachedForRepeatedQuery() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = Data(#"{"apiRequestsLeft":"99.9","numClubs":1,"clubs":[{"clubID":"club-1","clubName":"Åre Golfklubb","city":"Åre","state":"Jämtland","country":"Sweden","courses":[] }]}"#.utf8)
        let client = makeClient(directory: directory) { request in
            #expect(request.url?.query?.contains("country=Sweden") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-key")
            return (200, response)
        }

        let first = try await client.searchClubs(named: "Åre", country: "Sweden", region: "Jämtland")
        let second = try await client.searchClubs(named: "Åre", country: "Sweden", region: "Jämtland")
        #expect(first == second)
        #expect(first.first?.clubName == "Åre Golfklubb")
        #expect(GolfAPIStubProtocol.requestCount == 1)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func courseSearchSendsCountryAndRegionFilters() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = makeClient(directory: directory) { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(query["country"] == "Sweden")
            #expect(query["state"] == "Jämtland")
            #expect(query["name"] == "Åre")
            return (200, Data(#"{"apiRequestsLeft":"99.9","numClubs":0,"clubs":[]}"#.utf8))
        }

        _ = try await client.searchClubs(named: "Åre", country: "Sweden", region: "Jämtland")
        #expect(GolfAPIStubProtocol.requestCount == 1)
        GolfAPIStubProtocol.handler = nil
    }

    @Test func missingAPIKeyFailsBeforeNetworkRequest() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        GolfAPIStubProtocol.handler = { _ in (200, Data(#"{"clubs":[]}"#.utf8)) }
        GolfAPIStubProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GolfAPIStubProtocol.self]
        let noKeyClient = GolfAPIClient(
            session: URLSession(configuration: configuration),
            cache: GolfAPICache(directoryURL: directory),
            apiKey: "",
            mode: .live
        )

        do {
            _ = try await noKeyClient.searchClubs(named: "Åre", country: "Sweden")
            Issue.record("Expected a missing Golf API key error")
        } catch let error as GolfAPIError {
            #expect(error == .missingAPIKey)
            #expect(GolfAPIStubProtocol.requestCount == 0)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        GolfAPIStubProtocol.handler = nil
    }
}
