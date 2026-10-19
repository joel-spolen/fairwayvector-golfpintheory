import Foundation

/// Deliberately no retries, probes, logging of request bodies, or key-bearing URLs.
/// A redirect is rejected so a credential header can never follow a new host.
nonisolated final class GPXZRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated struct GPXZElevationClient: Sendable {
    let session: URLSession
    let key: String
    let mode: DevelopmentAPIConfiguration.Mode
    init(key: String? = nil, session: URLSession? = nil,
         mode: DevelopmentAPIConfiguration.Mode = DevelopmentAPIConfiguration.current.gpxz) {
        self.mode = mode
        self.key = mode == .mock ? "" : (key ?? (Bundle.main.object(forInfoDictionaryKey: "GPXZ_API_KEY") as? String ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        config.urlCache = nil
        self.session = session ?? URLSession(configuration: config, delegate: GPXZRedirectPolicy(), delegateQueue: nil)
    }
    var configured: Bool {
        mode == .mock || (!key.isEmpty && !key.contains("$(") && !key.contains("${") && !key.contains("YOUR_")
            && !key.contains("<") && !key.contains(">")
        )
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
    func request(path: [GeoPoint]) throws -> (URLRequest, Int) {
        guard configured else { throw TerrainError.notConfigured }
        let path = try TerrainGeometry.clean(path)
        let length = TerrainGeometry.chainages(path).last ?? 0
        guard path.count >= 2, length > 0, length.isFinite else { throw TerrainError.invalidPath }
        let count = length >= 511 ? 512 : max(2, Int(ceil(length)) + 1)
        guard (2...512).contains(count) else { throw TerrainError.invalidPath }
        var request = URLRequest(url: URL(string: mode == .mock
            ? "https://development.invalid/synthetic-terrain" : "https://api.gpxz.io/v1/elevation/sample")!)
        request.httpMethod = "POST"
        if mode == .live { request.setValue(key, forHTTPHeaderField: "x-api-key") }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "latlons", value: path.map { "\($0.lat),\($0.lon)" }.joined(separator: "|")),
            URLQueryItem(name: "samples", value: String(count)),
            URLQueryItem(name: "interpolation", value: "bilinear"),
            URLQueryItem(name: "bathymetry", value: "false")
        ]
        // URL query syntax permits '+', but form decoders treat it as a space.
        // Fixed field order gives a stable fingerprint of the actual wire body.
        guard let encoded = form.percentEncodedQuery else { throw TerrainError.invalidPath }
        request.httpBody = Data(encoded.replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "|", with: "%7C").utf8)
        return (request, count)
    }

    func send(_ request: URLRequest, path: [GeoPoint], count: Int,
              dispatch: @Sendable (@Sendable () -> Void) -> Bool = { start in start(); return true }) async throws -> TerrainResponseRecord {
        // Final hard gate also protects callers passing an already-built live URLRequest.
        // No dispatch callback, credential access or session task exists in mock mode.
        if mode == .mock { return try Self.syntheticRecord(path: path, count: count) }
        guard configured else { throw TerrainError.notConfigured }
        let (data, rawResponse): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            // Task creation/resume shares the interaction lock with beginTargetInteraction.
            // A maySend check alone could race an executor hop before actual dispatch.
            let started = dispatch {
                session.dataTask(with: request) { data, response, error in
                    if error != nil { continuation.resume(throwing: TerrainError.transport) }
                    else if let data, let response { continuation.resume(returning: (data, response)) }
                    else { continuation.resume(throwing: TerrainError.invalidResponse) }
                }.resume()
            }
            if !started { continuation.resume(throwing: TerrainError.requestPaused) }
        }
        guard let http = rawResponse as? HTTPURLResponse else { throw TerrainError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
                if [429, 503].contains(http.statusCode),
                    let value = http.value(forHTTPHeaderField: "Retry-After"), let date = Self.retryDate(value) {
                throw TerrainError.retryAfter(date)
            }
            throw TerrainError.http(http.statusCode, reason: Self.providerReason(data: data, key: key))
        }
        return try Self.validate(data: data, path: path, count: count,
                                 datasetVersion: http.value(forHTTPHeaderField: "X-DATASET-VERSION"), fetchedAt: .now)
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

    /// Decode ONLY the documented plain-language field, never HTML, URLs, or headers.
    /// Keep unknown/oversized error formats out of both UI and the persisted failure lock.
    static func providerReason(data: Data, key: String) -> String? {
        guard data.count <= 65_536,
              let envelope = try? JSONDecoder().decode(ProviderError.self, from: data) else { return nil }
        var text = envelope.error
        if !key.isEmpty { text = text.replacingOccurrences(of: key, with: "[redacted]") }
        // Header/credential-bearing details are not safe to echo, even inside an error field.
        if text.range(of: #"(?i)(x-api-key|api[_ -]?key|authorization|bearer|cookie|headers?\s*:)"#,
                      options: .regularExpression) != nil {
            return "Provider detail omitted because it contains credential or header information."
        }
        text = text.replacingOccurrences(of: #"(?i)\b[a-z][a-z0-9+.-]*://\S+|\bak_[a-z0-9_-]+"#,
                                         with: "[redacted]", options: .regularExpression)
        text = text.components(separatedBy: .controlCharacters).joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return String(text.prefix(400))
    }

    private static func retryDate(_ value: String) -> Date? {
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return Date.now.addingTimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}