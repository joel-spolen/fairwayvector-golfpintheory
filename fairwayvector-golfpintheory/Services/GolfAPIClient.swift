import CryptoKit
import Foundation

struct GolfAPICoursePayload {
    let detail: GolfAPICourseDetail
    let coordinates: [GolfAPICoordinate]
}

struct GolfAPIClient {
    static let shared = GolfAPIClient()

    private let session: URLSession?
    private let cache: GolfAPICache
    private let edgeBaseURL: URL?
    private let bundledSavedCourses: BundledSavedCourseStore?
    let mode: DevelopmentAPIConfiguration.Mode

    init(
        session: URLSession? = nil,
        cache: GolfAPICache = GolfAPICache(),
        projectURL: URL? = nil,
        mode: DevelopmentAPIConfiguration.Mode = DevelopmentAPIConfiguration.current.golfAPI,
        bundledSavedCourses: BundledSavedCourseStore? = BundledSavedCourseStore()
    ) {
        self.session = session
        self.cache = cache
        self.mode = mode
        self.bundledSavedCourses = bundledSavedCourses
        edgeBaseURL = SupabaseProviderEndpoint.functionBase(projectURL: projectURL)
    }

    var isConfigured: Bool {
        mode == .mock || edgeBaseURL != nil
    }

    func searchClubs(
        named query: String = "",
        country: String,
        region: String = "",
        forceRefresh: Bool = false,
        requiresGPS: Bool = true
    ) async throws -> [GolfAPIClub] {
        let normalizedQuery = Self.normalizedSearchTerm(query)
        let normalizedCountry = Self.normalizedSearchTerm(country)
        let normalizedRegion = Self.normalizedSearchTerm(region)
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
        let data = try await get("/golf/clubs", queryItems: queryItems)
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
        let data = try await get("/golf/courses/\(id)")
        let detail = try Self.decodeDetail(from: data)
        guard detail.courseID == id else {
            throw GolfAPIError.invalidResponse("The returned course ID does not match the requested course.")
        }
        if mode == .live { try cache.persistCourseDetail(data, id: id) }
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
        let data = try await get("/golf/coordinates/\(id)")
        let coordinates = try Self.decodeCoordinates(from: data, expectedCourseID: id)
        if mode == .live { try cache.persistCoordinates(data, id: id) }
        return coordinates
    }

    func loadCourse(id: String) async throws -> GolfAPICoursePayload {
        // The account auth service serializes token verification. Complete each
        // download before starting the next, and persist both before success.
        let detail = try await loadCourseDetail(id: id)
        let coordinates = try await loadCoordinates(id: id)
        return GolfAPICoursePayload(detail: detail, coordinates: coordinates)
    }

    static func normalizedSearchTerm(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
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
        let data = try await get("/golf/courses", queryItems: [
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
        // Mock mode is fixture-only. Live mode is restricted to Supabase's
        // authenticated Edge Function; no provider URL or provider key exists here.
        if mode == .mock {
            let fixturePath = path.hasPrefix("/golf/") ? String(path.dropFirst("/golf".count)) : path
            return try DevelopmentGolfAPIFixtures.response(path: fixturePath, queryItems: queryItems)
        }
        guard let edgeBaseURL else { throw GolfAPIError.missingDataServiceConfiguration }
        var components = URLComponents(url: edgeBaseURL.appending(path: String(path.dropFirst())), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result: SupabaseProviderResponse
        do {
            if let session {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw GolfAPIError.invalidResponse("The data service did not return an HTTP response.")
                }
                let headers: [String: String] = Dictionary(uniqueKeysWithValues: http.allHeaderFields.compactMap { key, value -> (String, String)? in
                    guard let key = key as? String else { return nil }
                    return (key, String(describing: value))
                })
                result = SupabaseProviderResponse(data: data, statusCode: http.statusCode, headers: headers)
            } else {
                result = try await SupabaseProviderGateway.shared.send(request)
            }
        } catch let error as GolfAPIError { throw error }
        catch let error as SupabaseProviderError {
            switch error {
            case .authenticationRequired: throw GolfAPIError.unauthorized
            case .configurationUnavailable: throw GolfAPIError.missingDataServiceConfiguration
            case .httpStatus(let status, _, _): throw GolfAPIError.httpStatus(status)
            case .requestRejected: throw GolfAPIError.invalidResponse("The provider-data request exceeded service limits.")
            case .transportUnavailable: throw GolfAPIError.httpStatus(503)
            }
        } catch { throw GolfAPIError.httpStatus(503) }

        guard result.statusCode != 401 && result.statusCode != 403 else { throw GolfAPIError.unauthorized }
        guard (200..<300).contains(result.statusCode) else {
            // Never echo server messages: only known protocol codes select local
            // fixed text. Raw errors can contain keys, URLs or submitted values.
            struct Envelope: Decodable {
                struct Failure: Decodable { let code: String }
                let error: Failure
            }
            let allowed = Set(["provider_disabled", "provider_not_configured", "daily_budget_exceeded",
                "request_pending", "provider_cooldown", "ambiguous_attempt", "cache_write_rejected",
                "rate_limit", "provider_unavailable", "invalid_provider_response", "service_unavailable"])
            let decoded = result.data.count <= 65_536
                ? (try? JSONDecoder().decode(Envelope.self, from: result.data).error.code) : nil
            let code = decoded.flatMap { allowed.contains($0) ? $0 : nil } ?? "service_unavailable"
            let stage = path.hasPrefix("/golf/coordinates/") ? "course GPS coordinates"
                : path.hasPrefix("/golf/courses/") ? "course details and tees" : "course search results"
            throw GolfAPIError.dataService(status: result.statusCode, code: code, stage: stage)
        }
        return result.data
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
        read(named: searchFilename(query: query, country: country, region: region))
    }
    func writeSearch(_ data: Data, query: String, country: String, region: String) {
        write(data, named: searchFilename(query: query, country: country, region: region))
    }
    func readCourseDetail(id: String) -> Data? { read(named: "course-\(safeKey(id))-detail.json") }
    func writeCourseDetail(_ data: Data, id: String) { write(data, named: "course-\(safeKey(id))-detail.json") }
    func readCoordinates(id: String) -> Data? { read(named: "course-\(safeKey(id))-coordinates.json") }
    func writeCoordinates(_ data: Data, id: String) { write(data, named: "course-\(safeKey(id))-coordinates.json") }

    func persistCourseDetail(_ data: Data, id: String) throws {
        try writeRequired(data, named: "course-\(safeKey(id))-detail.json")
    }

    func persistCoordinates(_ data: Data, id: String) throws {
        try writeRequired(data, named: "course-\(safeKey(id))-coordinates.json")
    }

    private func searchFilename(query: String, country: String, region: String) -> String {
        // Punctuation, case and different filters must never alias an unrelated
        // (possibly empty) search. Only trim + NFC are equivalent to the server.
        // Do not trust legacy lossy filenames; the shared server cache still
        // prevents a new provider call for previously cached requests.
        let fields = [country, region, query].map(GolfAPIClient.normalizedSearchTerm)
        let bytes = (try? JSONEncoder().encode(fields)) ?? Data()
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return "search-v2-\(digest).json"
    }

    private func writeRequired(_ data: Data, named name: String) throws {
        guard let rootURL else { throw GolfAPIError.localStorageUnavailable }
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try data.write(to: rootURL.appending(path: name), options: .atomic)
        } catch { throw GolfAPIError.localStorageUnavailable }
    }

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
