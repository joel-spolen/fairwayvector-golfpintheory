import Foundation

nonisolated private final class ProviderNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated struct GPXZElevationClient: Sendable {
    let session: URLSession
    private let hasInjectedSession: Bool
    let edgeBaseURL: URL?
    let mode: DevelopmentAPIConfiguration.Mode
    init(session: URLSession? = nil, projectURL: URL? = nil,
         mode: DevelopmentAPIConfiguration.Mode = DevelopmentAPIConfiguration.current.gpxz) {
        self.mode = mode
        hasInjectedSession = session != nil
        if let session {
            self.session = session
        } else {
            let settings = URLSessionConfiguration.ephemeral
            settings.urlCache = nil
            settings.httpCookieStorage = nil
            settings.urlCredentialStorage = nil
            settings.httpShouldSetCookies = false
            settings.requestCachePolicy = .reloadIgnoringLocalCacheData
            settings.timeoutIntervalForRequest = 30
            settings.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: settings, delegate: ProviderNoRedirectDelegate(), delegateQueue: nil)
        }
        edgeBaseURL = SupabaseProviderEndpoint.dataURL(projectURL: projectURL, route: "/elevation/sample")
    }
    var configured: Bool {
        mode == .mock || edgeBaseURL != nil
    }

    struct Response: Decodable, Sendable {
        let status: String
        let results: [Result]
    }
    private struct ProviderError: Decodable {
        let error: String
    }
    struct Result: Decodable, Sendable {
        let elevation: Double
        let lat: Double
        let lon: Double
        let data_source: String
        let resolution: Double
        let capture_date_min: String?
        let capture_date_max: String?
    }

    // Building/encoding occurs BEFORE budget reservation. The caller then reserves and sends once.
    func request(path: [GeoPoint], courseID: String? = nil) throws -> (URLRequest, Int) {
        guard configured else { throw TerrainError.notConfigured }
        let path = try TerrainGeometry.clean(path)
        let length = TerrainGeometry.chainages(path).last ?? 0
        guard path.count >= 2, length > 0, length.isFinite else { throw TerrainError.invalidPath }
        let count = length >= 511 ? 512 : max(2, Int(ceil(length)) + 1)
        guard (2...512).contains(count) else { throw TerrainError.invalidPath }
        let endpoint = edgeBaseURL ?? URL(string: "https://development.invalid/synthetic-terrain")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "latlons", value: path.map { "\($0.lat),\($0.lon)" }.joined(separator: "|")),
            URLQueryItem(name: "samples", value: String(count)),
            URLQueryItem(name: "interpolation", value: "bilinear"),
            URLQueryItem(name: "bathymetry", value: "false")
        ]
        if let courseID {
            let metadataID = courseID.hasPrefix("golfapi:") ? String(courseID.dropFirst("golfapi:".count)) : courseID
            if metadataID.range(of: #"^[A-Za-z0-9_-]{1,100}$"#, options: .regularExpression) != nil {
                form.queryItems?.append(URLQueryItem(name: "courseID", value: metadataID))
            }
        }
        // URL query syntax permits '+', but form decoders treat it as a space.
        // Fixed field order gives a stable fingerprint of the actual wire body.
        guard let encoded = form.percentEncodedQuery else { throw TerrainError.invalidPath }
        request.httpBody = Data(encoded.replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "|", with: "%7C").utf8)
        return (request, count)
    }

    func send(_ request: URLRequest, path: [GeoPoint], count: Int,
              dispatch: @Sendable (@Sendable () -> Void) -> Bool = { start in start(); return true }) async throws -> TerrainResponseRecord {
        // No dispatch callback or network task exists in mock mode.
        if mode == .mock { return try Self.syntheticRecord(path: path, count: count) }
        guard configured else { throw TerrainError.notConfigured }
        let authorizedRequest: URLRequest
        if hasInjectedSession {
            authorizedRequest = request
        } else {
            do { authorizedRequest = try await SupabaseProviderGateway.shared.authorizedRequest(request) }
            catch { throw TerrainError.notConfigured }
        }
        let response: SupabaseProviderResponse = try await withCheckedThrowingContinuation { continuation in
            // Task creation/resume shares the interaction lock with beginTargetInteraction.
            // A maySend check alone could race an executor hop before actual dispatch.
            let started = dispatch {
                session.dataTask(with: authorizedRequest) { data, rawResponse, error in
                    if error != nil {
                        continuation.resume(throwing: TerrainError.transport)
                    } else if let data, let http = rawResponse as? HTTPURLResponse {
                        let headers: [String: String] = Dictionary(uniqueKeysWithValues: http.allHeaderFields.compactMap { key, value -> (String, String)? in
                            guard let key = key as? String else { return nil }
                            return (key, String(describing: value))
                        })
                        continuation.resume(returning: SupabaseProviderResponse(data: data,
                            statusCode: http.statusCode, headers: headers))
                    } else {
                        continuation.resume(throwing: TerrainError.invalidResponse)
                    }
                }
                .resume()
            }
            if !started { continuation.resume(throwing: TerrainError.requestPaused) }
        }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw TerrainError.notConfigured
            }
            if [429, 503].contains(response.statusCode),
               let value = response.value(forHTTPHeaderField: "Retry-After"), let date = Self.retryDate(value) {
                throw TerrainError.retryAfter(date)
            }
            throw TerrainError.http(response.statusCode, reason: Self.edgeErrorMessage(data: response.data))
        }
        return try Self.validate(data: response.data, path: path, count: count,
                                 datasetVersion: response.value(forHTTPHeaderField: "X-DATASET-VERSION"), fetchedAt: .now)
    }

    /// Coordinate-based surface keeps shared endpoints identical across independently sampled paths.
    static func syntheticElevation(at point: GeoPoint) -> Double {
        let offset = TerrainGeometry.vector(point, from: GeoPoint(lat: 57.623, lon: 12.0))
        return 72 + 9 * sin(offset.x / 210) + 6 * cos(offset.y / 170) + 3 * sin((offset.x + offset.y) / 95)
    }

    static func syntheticRecord(path: [GeoPoint], count: Int, generatedAt: Date = .now) throws -> TerrainResponseRecord {
        let path = try TerrainGeometry.clean(path)
        let length = TerrainGeometry.chainages(path).last ?? 0
        guard path.count >= 2, length > 0, length.isFinite, (2...512).contains(count) else { throw TerrainError.invalidPath }
        let provenance = TerrainProvenance(dataSource: DevelopmentAPIConfiguration.syntheticSource,
            resolutionMeters: 1, captureDateMin: nil, captureDateMax: nil, datasetVersion: "synthetic-development-v1",
            fetchedAt: generatedAt, interpolation: "analytical synthetic surface", verticalDatum: "Synthetic (not surveyed)",
            providerSampleIntervalMeters: length / Double(count - 1))
        let samples = (0..<count).map { i in
            let distance = Double(i) / Double(count - 1) * length
            let point = i == 0 ? path[0] : i == count - 1 ? path[path.count - 1] : TerrainGeometry.point(path, at: distance)
            return TerrainSample(distanceMeters: distance, point: point,
                elevationMeters: syntheticElevation(at: point), provenance: [provenance])
        }
        return TerrainResponseRecord(path: path, samples: samples, fetchedAt: generatedAt)
    }

    static func validate(data: Data, path: [GeoPoint], count: Int, datasetVersion: String?, fetchedAt: Date) throws -> TerrainResponseRecord {
        guard path.count >= 2, path.count <= 5_000, path.allSatisfy(TerrainGeometry.valid),
              fetchedAt.timeIntervalSince1970.isFinite,
              data.count <= 4_000_000, (2...512).contains(count),
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.status.uppercased() == "OK", response.results.count == count else { throw TerrainError.invalidResponse }
        let length = TerrainGeometry.chainages(path).last ?? 0
        guard length.isFinite, length > 0 else { throw TerrainError.invalidResponse }
        let positionTolerance = min(max(0.5, length * 0.00001), length / Double(count - 1) * 0.4)
        var samples: [TerrainSample] = []
        for (i, result) in response.results.enumerated() {
            let point = GeoPoint(lat: result.lat, lon: result.lon)
            let distance = Double(i) / Double(count - 1) * length
            guard TerrainGeometry.valid(point), result.elevation.isFinite, result.resolution.isFinite, result.resolution > 0,
                  !result.data_source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  TerrainGeometry.length(point, TerrainGeometry.point(path, at: distance)) <= positionTolerance else {
                throw TerrainError.invalidResponse
            }
            if i == 0 || i == count - 1 {
                guard TerrainGeometry.length(point, i == 0 ? path[0] : path[path.count - 1]) <= TerrainGeometry.tolerance else {
                    throw TerrainError.invalidResponse
                }
            }
            let provenance = TerrainProvenance(dataSource: result.data_source, resolutionMeters: result.resolution,
                                               captureDateMin: result.capture_date_min, captureDateMax: result.capture_date_max,
                                               datasetVersion: datasetVersion, fetchedAt: fetchedAt,
                                               interpolation: "bilinear", verticalDatum: "EGM2008",
                                               providerSampleIntervalMeters: length / Double(count - 1))
            samples.append(TerrainSample(distanceMeters: distance, point: point, elevationMeters: result.elevation, provenance: [provenance]))
        }
        return TerrainResponseRecord(path: path, samples: samples, fetchedAt: fetchedAt)
    }

    /// Accept only the Edge Function's fixed error envelope; never echo provider
    /// URLs, credentials, headers, or raw upstream response bodies.
    static func edgeErrorMessage(data: Data) -> String? {
        guard data.count <= 65_536,
              let envelope = try? JSONDecoder().decode(EdgeErrorEnvelope.self, from: data) else { return nil }
        var text = envelope.error.message
        if text.range(of: #"(?i)(x-api-key|api[_ -]?key|authorization|bearer|cookie|headers?\s*:|https?://)"#,
                      options: .regularExpression) != nil {
            return nil
        }
        text = text.components(separatedBy: .controlCharacters).joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return String(text.prefix(400))
    }

    private struct EdgeErrorEnvelope: Decodable { let error: EdgeError }
    private struct EdgeError: Decodable { let code: String; let message: String }

    private static func retryDate(_ value: String) -> Date? {
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return Date.now.addingTimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}