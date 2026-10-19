import Foundation
import Testing
@testable import fairwayvector_pintheory

private final class OverpassStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.response else { return }
        let (status, data) = response(request)
        if status == NSURLErrorTimedOut {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct OverpassClientTests {
    private func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func client(_ response: @escaping (URLRequest) -> (Int, Data)) -> OverpassClient {
        OverpassStubProtocol.response = response
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OverpassStubProtocol.self]
        return OverpassClient(
            session: URLSession(configuration: configuration),
            endpoints: [URL(string: "https://first.example/api/interpreter")!, URL(string: "https://second.example/api/interpreter")!]
        )
    }

    @Test func retriesAnotherServerAfterHTTPError() async throws {
        let client = client { request in
            if request.url?.host == "first.example" { return (503, Data()) }
            return (200, Data(#"{"elements":[{"type":"relation","id":42,"tags":{"name":"Hills Golf Club"},"center":{"lat":57.62,"lon":12.0}}]}"#.utf8))
        }
        defer { OverpassStubProtocol.response = nil }

        let result = try await client.findCourseRelationID(for: .hills)
        #expect(result == 42)
    }

    @Test func timeoutOnOneMirrorDoesNotPreventCourseLookup() async throws {
        let client = client { request in
            if request.url?.host == "first.example" { return (NSURLErrorTimedOut, Data()) }
            return (200, Data(#"{"elements":[{"type":"relation","id":42,"tags":{"name":"Hills Golf Club"},"center":{"lat":57.62,"lon":12.0}}]}"#.utf8))
        }
        defer { OverpassStubProtocol.response = nil }

        #expect(try await client.findCourseRelationID(for: .hills) == 42)
    }

    @Test func retriesWhenOverpassReturnsHTTP200WithTimeoutRemark() async throws {
        let client = client { request in
            if request.url?.host == "first.example" {
                return (200, Data(#"{"elements":[],"remark":"runtime error: Query timed out"}"#.utf8))
            }
            return (200, Data(#"{"elements":[{"type":"relation","id":42,"tags":{"name":"Hills Golf Club"},"center":{"lat":57.62,"lon":12.0}}]}"#.utf8))
        }
        defer { OverpassStubProtocol.response = nil }

        #expect(try await client.findCourseRelationID(for: .hills) == 42)
    }

    @Test func searchesClubNameWithoutBroadCourseAlternatives() async throws {
        let reference = CourseReference(selection: SelectedCourse(
            club: CatalogClub(name: "Albatross GK", city: "Göteborg", region: nil, courses: []),
            course: CatalogCourse(name: "18-hålsbanan", holes: 18, par: 72, ratings: []),
            tee: CatalogTeeRating(tee: "56", sex: "male", courseRating: 70, slopeRating: 125)
        ))
        let client = client { request in
            let query = body(of: request).removingPercentEncoding ?? ""
            guard query.contains(#"["name"~"albatross",i]"#), !query.contains("18|"), !query.contains("hålsbanan") else {
                return (400, Data())
            }
            return (200, Data(#"{"elements":[{"type":"relation","id":123,"tags":{"name":"Albatross GK"},"center":{"lat":57.62,"lon":12.0}}]}"#.utf8))
        }
        defer { OverpassStubProtocol.response = nil }

        #expect(try await client.findCourseRelationID(for: reference) == 123)
    }

    @Test func searchesCourseNameIfClubNameHasNoMatch() async throws {
        let reference = CourseReference(selection: SelectedCourse(
            club: CatalogClub(name: "Albatross GK", city: "Göteborg", region: nil, courses: []),
            course: CatalogCourse(name: "Meadow Loop", holes: 18, par: 72, ratings: []),
            tee: CatalogTeeRating(tee: "56", sex: "male", courseRating: 70, slopeRating: 125)
        ))
        let client = client { request in
            let query = body(of: request).removingPercentEncoding ?? ""
            if query.contains(#"["name"~"albatross",i]"#) {
                return (200, Data(#"{"elements":[]}"#.utf8))
            }
            if query.contains(#"["name"~"meadow",i]"#) {
                return (200, Data(#"{"elements":[{"type":"relation","id":124,"tags":{"name":"Meadow Loop"},"center":{"lat":57.62,"lon":12.0}}]}"#.utf8))
            }
            return (400, Data())
        }
        defer { OverpassStubProtocol.response = nil }

        #expect(try await client.findCourseRelationID(for: reference) == 124)
    }

    @Test func fetchesNearbyHolesWhenRelationHasNoArea() async throws {
        let client = client { request in
            let body = body(of: request)
            if body.contains("area%28id") { return (200, Data(#"{"elements":[]}"#.utf8)) }
            if body.contains("out%20bb") {
                return (200, Data(#"{"elements":[{"type":"relation","id":42,"bounds":{"minlat":57.61,"minlon":11.98,"maxlat":57.63,"maxlon":12.02}}]}"#.utf8))
            }
            if body.contains("way%5B") {
                return (200, Data(#"{"elements":[{"type":"way","id":5,"tags":{"golf":"hole","ref":"1"},"geometry":[{"lat":57.61,"lon":12},{"lat":57.62,"lon":12}]}]}"#.utf8))
            }
            return (400, Data())
        }
        defer { OverpassStubProtocol.response = nil }

        let features = try await client.fetchGolfFeatures(courseRelationID: 42)
        #expect(features.contains { $0.tags?["golf"] == "hole" })
    }

    @Test func areaFailureFallsBackToBoundedHoleQuery() async throws {
        let client = client { request in
            let query = body(of: request)
            if query.contains("area%28id") { return (503, Data()) }
            if query.contains("out%20bb") {
                return (200, Data(#"{"elements":[{"type":"relation","id":42,"bounds":{"minlat":57.61,"minlon":11.98,"maxlat":57.63,"maxlon":12.02}}]}"#.utf8))
            }
            if query.contains("way%5B") {
                return (200, Data(#"{"elements":[{"type":"way","id":5,"tags":{"golf":"hole","ref":"1"},"geometry":[{"lat":57.61,"lon":12},{"lat":57.62,"lon":12}]}]}"#.utf8))
            }
            return (400, Data())
        }
        defer { OverpassStubProtocol.response = nil }

        #expect(try await client.fetchGolfFeatures(courseRelationID: 42).contains { $0.tags?["golf"] == "hole" })
    }
}