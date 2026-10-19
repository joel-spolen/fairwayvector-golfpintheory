import Foundation
import Observation

struct CourseWeather: Codable, Hashable {
    let elevationMeters: Double?
    let timezone: String?
    let observedAt: String
    let temperatureC: Double?
    let relativeHumidityPercent: Double?
    let surfacePressureHpa: Double?
    let seaLevelPressureHpa: Double?
    let windSpeedMps: Double?
    let windDirectionDegrees: Double?
    let windGustsMps: Double?
}

private struct CachedCourseWeather: Codable {
    let fetchedAt: Date
    let weather: CourseWeather
}

enum CourseWeatherError: LocalizedError {
    case invalidResponse
    case missingCurrentConditions
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The weather service returned an unreadable response."
        case .missingCurrentConditions: "Current weather is not available for this course."
        case .httpStatus(let status): "The weather service returned HTTP \(status)."
        }
    }
}

@MainActor
@Observable
final class CourseWeatherStore {
    private(set) var weather: CourseWeather?
    private(set) var weatherLocation: GeoPoint?
    private(set) var fetchedAt: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var loadedLocationKey: String?
    private var activeRequestID: UUID?
    private let session: URLSession
    private let fileManager: FileManager
    private let cacheDuration: TimeInterval = 30 * 60

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    /// Read-only association check; never loads or refreshes weather. Prevents
    /// an old location's conditions being used during a geometry/location change.
    func weather(for location: GeoPoint) -> CourseWeather? {
        guard let weatherLocation, Self.locationKey(weatherLocation) == Self.locationKey(location) else { return nil }
        return weather
    }

    var isStale: Bool {
        fetchedAt.map { Date.now.timeIntervalSince($0) >= cacheDuration } ?? true
    }

    func load(for location: GeoPoint, forceRefresh: Bool = false) async {
        let locationKey = Self.locationKey(location)
        if loadedLocationKey == locationKey, !forceRefresh, weather != nil { return }

        let locationChanged = loadedLocationKey != locationKey
        loadedLocationKey = locationKey
        if let cached = readCache(for: locationKey) {
            weather = cached.weather
            weatherLocation = location
            fetchedAt = cached.fetchedAt
            if !forceRefresh, Date.now.timeIntervalSince(cached.fetchedAt) < cacheDuration {
                errorMessage = nil
                return
            }
        } else if locationChanged {
            weather = nil
            weatherLocation = nil
            fetchedAt = nil
        }

        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        errorMessage = nil

        do {
            let current = try await fetch(for: location)
            guard activeRequestID == requestID else { return }
            weather = current
            weatherLocation = location
            let savedAt = Date.now
            fetchedAt = savedAt
            writeCache(CachedCourseWeather(fetchedAt: savedAt, weather: current), for: locationKey)
        } catch {
            guard activeRequestID == requestID else { return }
            errorMessage = error.localizedDescription
        }
        if activeRequestID == requestID {
            activeRequestID = nil
            isLoading = false
        }
    }

    private func fetch(for location: GeoPoint) async throws -> CourseWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.lat)),
            URLQueryItem(name: "longitude", value: String(location.lon)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,surface_pressure,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("FairwayVector/1.0 (iOS; course weather)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CourseWeatherError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw CourseWeatherError.httpStatus(http.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any],
              let observedAt = current["time"] as? String else {
            throw CourseWeatherError.missingCurrentConditions
        }

        return CourseWeather(
            elevationMeters: Self.double(root["elevation"]),
            timezone: root["timezone"] as? String,
            observedAt: observedAt,
            temperatureC: Self.double(current["temperature_2m"]),
            relativeHumidityPercent: Self.double(current["relative_humidity_2m"]),
            surfacePressureHpa: Self.double(current["surface_pressure"]),
            seaLevelPressureHpa: Self.double(current["pressure_msl"]),
            windSpeedMps: Self.double(current["wind_speed_10m"]),
            windDirectionDegrees: Self.double(current["wind_direction_10m"]),
            windGustsMps: Self.double(current["wind_gusts_10m"])
        )
    }

    private func cacheURL(for locationKey: String) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "CourseWeather", directoryHint: .isDirectory)
            .appending(path: "weather-\(locationKey).json")
    }

    private func readCache(for locationKey: String) -> CachedCourseWeather? {
        guard let url = cacheURL(for: locationKey),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedCourseWeather.self, from: data)
    }

    private func writeCache(_ cached: CachedCourseWeather, for locationKey: String) {
        guard let url = cacheURL(for: locationKey),
              let data = try? JSONEncoder().encode(cached) else { return }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func locationKey(_ location: GeoPoint) -> String {
        String(format: "%.3f-%.3f", location.lat, location.lon)
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
