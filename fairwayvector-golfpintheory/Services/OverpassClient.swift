import Foundation

struct OverpassElement: Decodable, Sendable {
    var type: String
    var id: Int
    var lat: Double?
    var lon: Double?
    var tags: [String: String]?
    var geometry: [GeoPoint]?
    var center: GeoPoint?
    var bounds: OverpassBounds?
}

struct OverpassBounds: Decodable, Sendable {
    let minlat: Double
    let minlon: Double
    let maxlat: Double
    let maxlon: Double

    func padded(by margin: Double) -> String {
        "\(minlat - margin),\(minlon - margin),\(maxlat + margin),\(maxlon + margin)"
    }
}

private struct OverpassResponse: Decodable, Sendable {
    var elements: [OverpassElement]
    var remark: String?
}

private struct OverpassAttempt: Sendable {
    let elements: [OverpassElement]?
    let failure: String?
}

enum OverpassError: LocalizedError {
    case badStatus(Int)
    case allServersFailed([String])
    case courseNotFound(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "OpenStreetMap returned status \(code). Try again shortly."
        case .allServersFailed(let failures):
            let details = failures.joined(separator: "; ")
            return details.isEmpty
                ? "Course map data is temporarily unavailable. Try again shortly."
                : "Course map data is temporarily unavailable. Try again shortly. Details: \(details)"
        case .courseNotFound(let course):
            return "No OpenStreetMap course area was found for \(course). Try a different course or retry later."
        }
    }
}

struct OverpassClient {
    private static let defaultEndpoints = [
        URL(string: "https://overpass.openstreetmap.fr/api/interpreter")!,
        URL(string: "https://overpass-api.de/api/interpreter")!,
    ]

    let session: URLSession
    let endpoints: [URL]

    init(session: URLSession = .shared, endpoints: [URL] = defaultEndpoints) {
        self.session = session
        self.endpoints = endpoints
    }

    func findCourseRelationID(for reference: CourseReference) async throws -> Int {
        let clubTokens = matchTokens(reference.clubName)
        let courseTokens = matchTokens(reference.courseName)
        let generic: Set<String> = ["golf", "golfklubb", "golfklubben", "gk", "gc", "club", "country", "sports", "course", "slinga", "bana", "banan", "the", "and"]
        let clubTerm = preferredTerm(in: clubTokens.subtracting(generic))
        let courseTerm = preferredTerm(in: courseTokens.subtracting(generic))
        let terms = [clubTerm, courseTerm].compactMap { $0 }.reduce(into: [String]()) { terms, term in
            if !terms.contains(term) { terms.append(term) }
        }
        guard !terms.isEmpty else { throw OverpassError.courseNotFound(reference.courseName) }

        for term in terms {
            let expression = NSRegularExpression.escapedPattern(for: term)
            let query = """
            [out:json][timeout:20];relation["leisure"="golf_course"]["name"~"\(expression)",i](55,10,70,25);out center tags;
            """
            let elements = try await perform(query: query, timeout: 26)
            let candidates = elements.compactMap { element -> (id: Int, score: Int)? in
                guard element.type == "relation",
                      let name = element.tags?["name"],
                      let center = element.center,
                      (55.0...70.0).contains(center.lat),
                      (10.0...25.0).contains(center.lon) else { return nil }
                let nameTokens = matchTokens(name)
                let courseMatches = nameTokens.intersection(courseTokens).count
                let clubMatches = nameTokens.intersection(clubTokens).count
                guard courseMatches + clubMatches > 0 else { return nil }
                return (element.id, clubMatches * 3 + courseMatches * 2)
            }
            if let match = candidates.max(by: { $0.score < $1.score }) {
                return match.id
            }
        }
        throw OverpassError.courseNotFound(reference.courseName)
    }

    func fetchGolfFeatures(courseRelationID: Int) async throws -> [OverpassElement] {
        let areaID = 3_600_000_000 + courseRelationID
        let query = """
        [out:json][timeout:18];area(id:\(areaID))->.c;(way["golf"="hole"](area.c);way["golf"="green"](area.c);way["golf"="fairway"](area.c);way["golf"="rough"](area.c);way["golf"="tee"](area.c);node["golf"="pin"](area.c););out geom;
        """
        if let areaFeatures = try? await perform(query: query, timeout: 24),
           areaFeatures.contains(where: { $0.tags?["golf"] == "hole" }) {
            return areaFeatures
        }
        try Task.checkCancellation()

        let relation = try await perform(
            query: "[out:json][timeout:10];relation(\(courseRelationID));out bb;",
            timeout: 15,
            requiresElements: true
        )
        guard let bounds = relation.first(where: { $0.id == courseRelationID })?.bounds else {
            throw OverpassError.courseNotFound("relation \(courseRelationID)")
        }
        let bbox = bounds.padded(by: 0.002)
        let fallbackQuery = """
        [out:json][timeout:20];(way["golf"="hole"](\(bbox));way["golf"="green"](\(bbox));way["golf"="fairway"](\(bbox));way["golf"="rough"](\(bbox));way["golf"="tee"](\(bbox));node["golf"="pin"](\(bbox)););out geom;
        """
        return try await perform(query: fallbackQuery, timeout: 28, requiresElements: true)
    }

    private func perform(query: String, timeout: TimeInterval, requiresElements: Bool = false) async throws -> [OverpassElement] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return try await withThrowingTaskGroup(of: OverpassAttempt.self) { group in
            for endpoint in endpoints {
                group.addTask { @MainActor in
                    do {
                        var request = URLRequest(url: endpoint)
                        request.httpMethod = "POST"
                        request.timeoutInterval = timeout
                        request.setValue("FairwayVectorMap/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
                        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                        request.httpBody = Data("data=\(encoded)".utf8)

                        let (data, response) = try await session.data(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            return OverpassAttempt(elements: nil, failure: "\(endpoint.host ?? "Overpass"): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                        }
                        let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
                        if let remark = decoded.remark, !remark.isEmpty {
                            return OverpassAttempt(elements: nil, failure: "\(endpoint.host ?? "Overpass"): \(remark)")
                        }
                        if requiresElements && decoded.elements.isEmpty {
                            return OverpassAttempt(elements: nil, failure: "\(endpoint.host ?? "Overpass"): no course data")
                        }
                        return OverpassAttempt(elements: decoded.elements, failure: nil)
                    } catch {
                        return OverpassAttempt(elements: nil, failure: "\(endpoint.host ?? "Overpass"): \(error.localizedDescription)")
                    }
                }
            }

            var failures: [String] = []
            while let attempt = try await group.next() {
                if let elements = attempt.elements {
                    group.cancelAll()
                    return elements
                }
                if let failure = attempt.failure {
                    failures.append(failure)
                }
            }
            try Task.checkCancellation()
            throw OverpassError.allServersFailed(failures)
        }
    }

    private func matchTokens(_ value: String) -> Set<String> {
        Set(value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter {
            $0.count >= 2 || $0.contains(where: \.isNumber)
        })
    }

    private func preferredTerm(in tokens: Set<String>) -> String? {
        tokens.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }.first
    }

    static func decode(_ data: Data) throws -> [OverpassElement] {
        try JSONDecoder().decode(OverpassResponse.self, from: data).elements
    }
}
