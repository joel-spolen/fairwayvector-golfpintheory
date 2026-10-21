import Foundation

struct GolfAPIClub: Decodable, Hashable, Identifiable {
    let clubID: String
    let clubName: String
    let city: String?
    let state: String?
    let country: String
    let courses: [GolfAPICourseSummary]

    var id: String { clubID }
}

struct GolfAPICourseSummary: Decodable, Hashable, Identifiable {
    let courseID: String
    let courseName: String
    let numHoles: Int
    let hasGPS: Bool
    let timestampUpdated: String?

    var id: String { courseID }
}

struct GolfAPICourseDetail: Decodable, Hashable {
    let courseID: String
    let clubID: String
    let clubName: String
    let courseName: String
    let city: String?
    let state: String?
    let country: String
    let latitude: Double?
    let longitude: Double?
    let numHoles: Int
    let measure: String
    let timestampUpdated: String?
    let hasGPS: Bool
    let parsMen: [Int]
    let indexesMen: [Int]
    let parsWomen: [Int]
    let indexesWomen: [Int]
    let tees: [GolfAPITee]

    init(json: [String: Any]) throws {
        guard let courseID = Self.string(json["courseID"]),
              let courseName = Self.string(json["courseName"]) else {
            throw GolfAPIError.invalidResponse("Course detail is missing its course ID or name.")
        }
        self.courseID = courseID
        clubID = Self.string(json["clubID"]) ?? ""
        clubName = Self.string(json["clubName"]) ?? ""
        self.courseName = courseName
        city = Self.string(json["city"])
        state = Self.string(json["state"])
        country = Self.string(json["country"]) ?? ""
        latitude = Self.double(json["latitude"])
        longitude = Self.double(json["longitude"])
        numHoles = Self.int(json["numHoles"]) ?? 0
        let measureUnit = Self.string(json["measure"]) ?? "y"
        measure = measureUnit
        timestampUpdated = Self.string(json["timestampUpdated"])
        hasGPS = Self.bool(json["hasGPS"]) ?? false
        parsMen = Self.intArray(json["parsMen"])
        indexesMen = Self.intArray(json["indexesMen"])
        parsWomen = Self.intArray(json["parsWomen"])
        indexesWomen = Self.intArray(json["indexesWomen"])
        var decodedTees: [GolfAPITee] = []
        for teeJSON in json["tees"] as? [[String: Any]] ?? [] {
            if let tee = GolfAPITee(json: teeJSON, measure: measureUnit) {
                decodedTees.append(tee)
            }
        }
        tees = decodedTees
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
        if let string = value as? String { return string == "1" || string.lowercased() == "true" }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String else { return nil }
        return Double(string)
    }

    private static func intArray(_ value: Any?) -> [Int] {
        var result: [Int] = []
        for item in value as? [Any] ?? [] {
            if let parsed = int(item) { result.append(parsed) }
        }
        return result
    }
}

struct GolfAPITee: Decodable, Hashable, Identifiable {
    let teeID: String
    let teeName: String
    let teeColor: String?
    let courseRatingMen: Double?
    let slopeMen: Int?
    let courseRatingWomen: Double?
    let slopeWomen: Int?
    let lengthsMeters: [Double?]
    let parsMen: [Int]
    let indexesMen: [Int]
    let parsWomen: [Int]
    let indexesWomen: [Int]

    var id: String { teeID }

    init?(json: [String: Any], measure: String) {
        guard let teeID = Self.string(json["teeID"]),
              let teeName = Self.string(json["teeName"]) else { return nil }
        self.teeID = teeID
        self.teeName = teeName
        teeColor = Self.string(json["teeColor"])
        courseRatingMen = Self.double(json["courseRatingMen"])
        slopeMen = Self.int(json["slopeMen"])
        courseRatingWomen = Self.double(json["courseRatingWomen"])
        slopeWomen = Self.int(json["slopeWomen"])
        lengthsMeters = (1...18).map { hole in
            guard let length = Self.double(json["length\(hole)"]) else { return nil }
            return length * (measure == "m" ? 1 : 0.9144)
        }
        parsMen = Self.intArray(json["pars"])
        indexesMen = Self.intArray(json["indexes"])
        parsWomen = Self.intArray(json["parsWomen"])
        indexesWomen = Self.intArray(json["indexesWomen"])
    }

    func rating(for sex: String) -> Double? {
        sex == "female" ? courseRatingWomen : courseRatingMen
    }

    func slope(for sex: String) -> Int? {
        sex == "female" ? slopeWomen : slopeMen
    }

    func pars(for sex: String, fallback: [Int]) -> [Int] {
        let teePars = sex == "female" ? parsWomen : parsMen
        return teePars.isEmpty ? fallback : teePars
    }

    func indexes(for sex: String, fallback: [Int]) -> [Int] {
        let teeIndexes = sex == "female" ? indexesWomen : indexesMen
        return teeIndexes.isEmpty ? fallback : teeIndexes
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

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String else { return nil }
        return Double(string)
    }

    private static func intArray(_ value: Any?) -> [Int] {
        var result: [Int] = []
        for item in value as? [Any] ?? [] {
            if let number = item as? NSNumber {
                result.append(number.intValue)
            } else if let string = item as? String, let parsed = Int(string) {
                result.append(parsed)
            }
        }
        return result
    }
}

struct GolfAPICoordinate: Decodable, Hashable, Identifiable {
    let poi: Int
    let location: Int?
    let sideFW: Int?
    let hole: Int
    let latitude: Double
    let longitude: Double

    var id: String { "\(hole)-\(poi)-\(location ?? 0)-\(sideFW ?? 0)-\(latitude)-\(longitude)" }

    var point: GeoPoint { GeoPoint(lat: latitude, lon: longitude) }

    init?(json: [String: Any]) {
        guard let poi = Self.int(json["poi"]),
              let hole = Self.int(json["hole"]),
              let latitude = Self.double(json["latitude"]),
              let longitude = Self.double(json["longitude"]) else { return nil }
        self.poi = poi
        location = Self.int(json["location"])
        sideFW = Self.int(json["sideFW"])
        self.hole = hole
        self.latitude = latitude
        self.longitude = longitude
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        guard let string = value as? String else { return nil }
        return Int(string)
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String else { return nil }
        return Double(string)
    }
}

struct GolfAPICourseSelection: Hashable, Identifiable {
    let club: GolfAPIClub
    let course: GolfAPICourseSummary
    let details: GolfAPICourseDetail
    let tee: GolfAPITee
    let sex: String

    var id: String { "\(course.courseID)-\(tee.teeID)-\(sex)" }

    var reference: CourseReference {
        CourseReference(golfAPISelection: self)
    }
}

enum GolfAPIError: LocalizedError, Equatable {
    case missingAPIKey
    case unauthorized
    case httpStatus(Int)
    case invalidResponse(String)
    case noGPSData(String)
    case noRatedTees(String)
    case savedCourseUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Golf API is not configured. Add GOLF_API_KEY to the app target's build settings."
        case .unauthorized:
            return "Golf API rejected the key. Check that the API key is active."
        case .httpStatus(let status):
            return "Golf API returned HTTP \(status). Try again shortly."
        case .invalidResponse(let detail):
            return "Golf API returned incomplete course data: \(detail)"
        case .noGPSData(let course):
            return "\(course) has no GPS coordinates in Golf API."
        case .noRatedTees(let course):
            return "No rated tee sets were found for \(course)."
        case .savedCourseUnavailable(let course):
            return "Previously downloaded course data for \(course) is not available on this device. Your course selection has been preserved."
        }
    }
}
