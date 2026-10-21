import Foundation

struct GolfAPICoursePayload {
    let detail: GolfAPICourseDetail
    let coordinates: [GolfAPICoordinate]
}

struct GolfAPIClient {
    static let baseURL = URL(string: "https://golfapi.io/api/v2.3")!
    static let shared = GolfAPIClient()

    private let session: URLSession
    private let cache: GolfAPICache
    private let apiKey: String
    private let bundledSavedCourses: BundledSavedCourseStore?
    let mode: DevelopmentAPIConfiguration.Mode

    init(
        session: URLSession = .shared,
        cache: GolfAPICache = GolfAPICache(),
        apiKey: String? = nil,
        mode: DevelopmentAPIConfiguration.Mode = DevelopmentAPIConfiguration.current.golfAPI,
        bundledSavedCourses: BundledSavedCourseStore? = BundledSavedCourseStore()
    ) {
        self.session = session
        self.cache = cache
        self.mode = mode
        self.bundledSavedCourses = bundledSavedCourses
        self.apiKey = mode == .mock ? "" : (apiKey ?? (Bundle.main.object(forInfoDictionaryKey: "GOLF_API_KEY") as? String ?? ""))
    }

    var isConfigured: Bool {
        mode == .mock || (!apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.contains("$(") && !apiKey.contains("${"))
    }

    func searchClubs(
        named query: String = "",
        country: String,
        region: String = "",
        forceRefresh: Bool = false,
        requiresGPS: Bool = true
    ) async throws -> [GolfAPIClub] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty || !normalizedCountry.isEmpty || !normalizedRegion.isEmpty else { return [] }
        if mode == .mock {
            // Read-only, including force refresh. Only complete downloaded courses are selectable.
            let saved = cachedClubs(requiresGPS: requiresGPS).filter {
                (normalizedCountry.isEmpty || $0.country.caseInsensitiveCompare(normalizedCountry) == .orderedSame)
                    && (normalizedRegion.isEmpty || ($0.state ?? "").localizedCaseInsensitiveContains(normalizedRegion))
                    && (normalizedQuery.isEmpty || $0.clubName.localizedCaseInsensitiveContains(normalizedQuery)
                        || $0.courses.contains { $0.courseName.localizedCaseInsensitiveContains(normalizedQuery) })
            }
            let demo = try Self.decodeClubs(from: await get("/clubs", queryItems: [
                URLQueryItem(name: "country", value: normalizedCountry),
                URLQueryItem(name: "state", value: normalizedRegion),
                URLQueryItem(name: "name", value: normalizedQuery)
            ]))
            return saved + demo
        }
        if mode == .live, !forceRefresh, let cached = cache.readSearch(query: normalizedQuery, country: normalizedCountry, region: normalizedRegion) {
            return try Self.decodeClubs(from: cached)
        }

        var queryItems = [URLQueryItem(name: "page", value: "1")]
        if !normalizedCountry.isEmpty { queryItems.append(URLQueryItem(name: "country", value: normalizedCountry)) }
        if !normalizedRegion.isEmpty { queryItems.append(URLQueryItem(name: "state", value: normalizedRegion)) }
        if !normalizedQuery.isEmpty { queryItems.append(URLQueryItem(name: "name", value: normalizedQuery)) }
        let data = try await get("/clubs", queryItems: queryItems)
        _ = try Self.decodeClubs(from: data)
        if mode == .live { cache.writeSearch(data, query: normalizedQuery, country: normalizedCountry, region: normalizedRegion) }
        return try Self.decodeClubs(from: data)
    }

    func loadCourseDetail(id: String, forceRefresh: Bool = false) async throws -> GolfAPICourseDetail {
        if mode == .live, !forceRefresh, let cached = cache.readCourseDetail(id: id) {
            let detail = try Self.decodeDetail(from: cached)
            guard detail.courseID == id else { throw GolfAPIError.invalidResponse("Saved detail course ID mismatch.") }
            return detail
        }
        if (mode == .mock || !forceRefresh), let cached = cache.readCourseDetail(id: id),
           let detail = try? Self.decodeDetail(from: cached), detail.courseID == id {
            return detail
        }
          if (mode == .mock || !forceRefresh), let bytes = bundledSavedCourses?.detail(id: id),
              let detail = try? Self.decodeDetail(from: bytes), detail.courseID == id { return detail }
          if mode == .mock, id != DevelopmentGolfAPIFixtures.courseID { throw GolfAPIError.savedCourseUnavailable(id) }
        let data = try await get("/courses/\(id)")
        let detail = try Self.decodeDetail(from: data)
        guard detail.courseID == id else {
            throw GolfAPIError.invalidResponse("The returned course ID does not match the requested course.")
        }
        if mode == .live { cache.writeCourseDetail(data, id: id) }
        return detail
    }

    func loadCoordinates(id: String, forceRefresh: Bool = false) async throws -> [GolfAPICoordinate] {
        if mode == .live, !forceRefresh, let cached = cache.readCoordinates(id: id) {
            return try Self.decodeCoordinates(from: cached, expectedCourseID: id)
        }
        if (mode == .mock || !forceRefresh), let cached = cache.readCoordinates(id: id),
           let coordinates = try? Self.decodeCoordinates(from: cached, expectedCourseID: id) {
            return coordinates
        }
          if (mode == .mock || !forceRefresh), let bytes = bundledSavedCourses?.coordinates(id: id),
              let coordinates = try? Self.decodeCoordinates(from: bytes, expectedCourseID: id) { return coordinates }
          if mode == .mock, id != DevelopmentGolfAPIFixtures.courseID { throw GolfAPIError.savedCourseUnavailable(id) }
        let data = try await get("/coordinates/\(id)")
        let coordinates = try Self.decodeCoordinates(from: data, expectedCourseID: id)
        if mode == .live { cache.writeCoordinates(data, id: id) }
        return coordinates
    }

    func loadCourse(id: String) async throws -> GolfAPICoursePayload {
        async let detail = loadCourseDetail(id: id)
        async let coordinates = loadCoordinates(id: id)
        return try await GolfAPICoursePayload(detail: detail, coordinates: coordinates)
    }

    func refreshCourse(id: String) async throws -> GolfAPICoursePayload {
        if mode == .mock { return try await loadCourse(id: id) }
        let currentDetail = try await loadCourseDetail(id: id)
        if try await checkForUpdates(to: currentDetail) {
            async let detail = loadCourseDetail(id: id, forceRefresh: true)
            async let coordinates = loadCoordinates(id: id, forceRefresh: true)
            return try await GolfAPICoursePayload(detail: detail, coordinates: coordinates)
        }
        return try await loadCourse(id: id)
    }

    func checkForUpdates(to detail: GolfAPICourseDetail) async throws -> Bool {
        guard mode == .live else { return false }
        guard let timestamp = detail.timestampUpdated, !timestamp.isEmpty else { return false }
        let data = try await get("/courses", queryItems: [
            URLQueryItem(name: "country", value: "Sweden"),
            URLQueryItem(name: "name", value: detail.clubName),
            URLQueryItem(name: "timestampUpdated", value: timestamp),
            URLQueryItem(name: "page", value: "1")
        ])
        let object = try Self.jsonObject(data)
        let courses = object["courses"] as? [[String: Any]] ?? []
        return courses.contains { Self.string($0["courseID"]) == detail.courseID }
    }

    /// No writes, migrations, update checks, credentials or transport.
    func cachedPayload(id: String) -> GolfAPICoursePayload? {
        guard id != DevelopmentGolfAPIFixtures.courseID,
                            let detail = [cache.readCourseDetail(id: id), bundledSavedCourses?.detail(id: id)]
                                .compactMap({ $0 }).compactMap({ try? Self.decodeDetail(from: $0) }).first(where: { $0.courseID == id }),
                            let coordinates = [cache.readCoordinates(id: id), bundledSavedCourses?.coordinates(id: id)]
                                .compactMap({ $0 }).compactMap({ try? Self.decodeCoordinates(from: $0, expectedCourseID: id) }).first else { return nil }
        return GolfAPICoursePayload(detail: detail, coordinates: coordinates)
    }

        func bundledCourse(reference: CourseReference) -> Course? {
                bundledSavedCourses?.course(reference: reference)
        }

    /// Detail-only access for handicap selection; never requests coordinates or transport.
    func cachedDetail(id: String) -> GolfAPICourseDetail? {
        [cache.readCourseDetail(id: id), bundledSavedCourses?.detail(id: id)]
            .compactMap { $0 }.compactMap { try? Self.decodeDetail(from: $0) }
            .first { $0.courseID == id }
    }

    func cachedClubs(requiresGPS: Bool = true) -> [GolfAPIClub] {
        // Some detail payloads omit club/country names; saved search metadata supplies
        // those names, but search metadata alone NEVER makes a course downloadable offline.
        var clubs: [GolfAPIClub] = cache.searchData().flatMap { (try? Self.decodeClubs(from: $0)) ?? [] }
        if let bytes = bundledSavedCourses?.clubData { clubs += (try? Self.decodeClubs(from: bytes)) ?? [] }
        let details = cache.courseDetailData().compactMap { try? Self.decodeDetail(from: $0) }
        clubs += details.map { detail in
            GolfAPIClub(clubID: detail.clubID, clubName: detail.clubName, city: detail.city, state: detail.state,
                country: detail.country, courses: [GolfAPICourseSummary(courseID: detail.courseID,
                    courseName: detail.courseName, numHoles: detail.numHoles, hasGPS: detail.hasGPS,
                    timestampUpdated: detail.timestampUpdated)])
        }
        var seen = Set<String>()
        var saved: [GolfAPIClub] = []
        for club in clubs {
            let courses = club.courses.filter { summary in
                guard !seen.contains(summary.courseID) else { return false }
                if requiresGPS {
                    guard summary.hasGPS, cachedPayload(id: summary.courseID) != nil else { return false }
                } else {
                    guard cachedDetail(id: summary.courseID) != nil else { return false }
                }
                seen.insert(summary.courseID)
                return true
            }
            guard !courses.isEmpty else { continue }
            if let index = saved.firstIndex(where: { $0.clubID == club.clubID }) {
                let existing = saved[index]
                saved[index] = GolfAPIClub(clubID: existing.clubID, clubName: existing.clubName,
                    city: existing.city, state: existing.state, country: existing.country,
                    courses: existing.courses + courses)
            } else {
                saved.append(GolfAPIClub(clubID: club.clubID, clubName: club.clubName, city: club.city,
                    state: club.state, country: club.country, courses: courses))
            }
        }
        return saved.sorted { $0.clubName < $1.clubName }
    }

    var savedReferences: [CourseReference] {
        cachedClubs().flatMap { club in
            club.courses.flatMap { summary -> [CourseReference] in
                guard let payload = cachedPayload(id: summary.courseID) else { return [] }
                return ["male", "female"].flatMap { sex in
                    payload.detail.tees.compactMap { tee -> CourseReference? in
                        guard tee.rating(for: sex) != nil, tee.slope(for: sex) != nil else { return nil }
                        let reference = GolfAPICourseSelection(club: club, course: summary,
                            details: payload.detail, tee: tee, sex: sex).reference
                        guard (try? GolfAPICourseBuilder.build(reference: reference, payload: payload)) != nil else { return nil }
                        return reference
                    }
                }
            }
        }
    }

    private func get(_ path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        // Hard gate at the only transport boundary, BEFORE keys, URLRequest or URLSession.
        if mode == .mock { return try DevelopmentGolfAPIFixtures.response(path: path, queryItems: queryItems) }
        guard !DevelopmentAPIConfiguration.isDemoCourse(path) else {
            throw GolfAPIError.invalidResponse("Demo IDs cannot be sent to the live provider. Select a real course after rebuilding in live mode.")
        }
        guard isConfigured else { throw GolfAPIError.missingAPIKey }
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GolfAPIError.invalidResponse("The server did not return an HTTP response.")
        }
        guard http.statusCode != 401 && http.statusCode != 403 else { throw GolfAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw GolfAPIError.httpStatus(http.statusCode) }
        return data
    }

    private static func decodeClubs(from data: Data) throws -> [GolfAPIClub] {
        let object = try jsonObject(data)
        guard let values = object["clubs"] as? [[String: Any]] else {
            throw GolfAPIError.invalidResponse("The clubs list is missing.")
        }
        return values.compactMap { value in
            guard let id = string(value["clubID"]),
                  let name = string(value["clubName"]) else { return nil }
            let courses = (value["courses"] as? [[String: Any]] ?? []).compactMap { course -> GolfAPICourseSummary? in
                guard let courseID = string(course["courseID"]),
                      let courseName = string(course["courseName"]) else { return nil }
                return GolfAPICourseSummary(
                    courseID: courseID,
                    courseName: courseName,
                    numHoles: int(course["numHoles"]) ?? 0,
                    hasGPS: bool(course["hasGPS"]) ?? false,
                    timestampUpdated: string(course["timestampUpdated"])
                )
            }
            return GolfAPIClub(
                clubID: id,
                clubName: name,
                city: string(value["city"]),
                state: string(value["state"]),
                country: string(value["country"]) ?? "",
                courses: courses
            )
        }
    }

    private static func decodeDetail(from data: Data) throws -> GolfAPICourseDetail {
        try GolfAPICourseDetail(json: jsonObject(data))
    }

    private static func decodeCoordinates(from data: Data, expectedCourseID: String) throws -> [GolfAPICoordinate] {
        let object = try jsonObject(data)
        guard string(object["courseID"]) == expectedCourseID else {
            throw GolfAPIError.invalidResponse("The returned coordinate course ID does not match the selected course.")
        }
        guard let values = object["coordinates"] as? [[String: Any]] else {
            throw GolfAPIError.invalidResponse("The course coordinates are missing.")
        }
        var coordinates: [GolfAPICoordinate] = []
        for value in values {
            if let coordinate = GolfAPICoordinate(json: value) {
                guard TerrainGeometry.valid(coordinate.point) else {
                    throw GolfAPIError.invalidResponse("Saved GPS coordinates are outside valid course bounds.")
                }
                coordinates.append(coordinate)
            }
        }
        guard !coordinates.isEmpty else {
            throw GolfAPIError.noGPSData(string(object["courseID"]) ?? "Selected course")
        }
        return coordinates
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GolfAPIError.invalidResponse("Expected a JSON object.")
        }
        return object
    }

    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String { return string.isEmpty ? nil : string }
        return String(describing: value)
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        guard let string = value as? String else { return nil }
        return Int(string)
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.intValue != 0 }
        guard let string = value as? String else { return nil }
        return string == "1" || string.lowercased() == "true"
    }
}

struct GolfAPICache {
    private let rootURL: URL?

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        rootURL = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "GolfAPI", directoryHint: .isDirectory)
    }

    func readSearch(query: String, country: String, region: String) -> Data? {
        read(named: "search-\(safeKey(country))-\(safeKey(region))-\(safeKey(query)).json")
    }
    func writeSearch(_ data: Data, query: String, country: String, region: String) {
        write(data, named: "search-\(safeKey(country))-\(safeKey(region))-\(safeKey(query)).json")
    }
    func readCourseDetail(id: String) -> Data? { read(named: "course-\(safeKey(id))-detail.json") }
    func writeCourseDetail(_ data: Data, id: String) { write(data, named: "course-\(safeKey(id))-detail.json") }
    func readCoordinates(id: String) -> Data? { read(named: "course-\(safeKey(id))-coordinates.json") }
    func writeCoordinates(_ data: Data, id: String) { write(data, named: "course-\(safeKey(id))-coordinates.json") }

    func courseDetailData() -> [Data] {
        cachedData(prefix: "course-", suffix: "-detail.json")
    }

    func searchData() -> [Data] { cachedData(prefix: "search-", suffix: ".json") }

    private func cachedData(prefix: String, suffix: String) -> [Data] {
        guard let rootURL, let files = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.hasSuffix(suffix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { try? Data(contentsOf: $0) }
    }

    private func read(named name: String) -> Data? {
        guard let rootURL else { return nil }
        return try? Data(contentsOf: rootURL.appending(path: name))
    }

    private func write(_ data: Data, named name: String) {
        guard let rootURL else { return }
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? data.write(to: rootURL.appending(path: name), options: .atomic)
    }

    private func safeKey(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.lowercased().unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
    }
}
