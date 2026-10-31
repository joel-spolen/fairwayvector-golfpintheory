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

struct GolfAPICatalogPage: Hashable {
    let clubs: [GolfAPIClub]
    let numClubs: Int
    let numAllClubs: Int
    let page: Int
    let pageSize: Int
    let hasMore: Bool
    let datasetVersion: String
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
        guard let courseID = Self.string(json[L("courseID")]),
              let rawCourseName = json[L("courseName")] as? String else {
            throw GolfAPIError.invalidResponse("Course detail is missing its course ID or name.")
        }
        self.courseID = courseID
        clubID = Self.string(json[L("clubID")]) ?? ""
        clubName = Self.string(json[L("clubName")]) ?? ""
        let name = rawCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let club = clubName.trimmingCharacters(in: .whitespacesAndNewlines)
        let holes = Self.int(json[L("numHoles")]) ?? 0
        courseName = !name.isEmpty ? rawCourseName : !club.isEmpty ? club
            : holes > 0 ? "\(holes)-hole course" : "Course"
        city = Self.string(json["city"])
        state = Self.string(json["state"])
        country = Self.string(json["country"]) ?? ""
        latitude = Self.double(json["latitude"])
        longitude = Self.double(json["longitude"])
        numHoles = Self.int(json[L("numHoles")]) ?? 0
        let measureUnit = Self.string(json["measure"]) ?? "y"
        measure = measureUnit
        timestampUpdated = Self.string(json[L("timestampUpdated")])
        hasGPS = Self.bool(json[L("hasGPS")]) ?? false
        parsMen = Self.intArray(json[L("parsMen")])
        indexesMen = Self.intArray(json[L("indexesMen")])
        parsWomen = Self.intArray(json[L("parsWomen")])
        indexesWomen = Self.intArray(json[L("indexesWomen")])
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
        guard let teeID = Self.string(json[L("teeID")]),
              let teeName = Self.string(json[L("teeName")]) else { return nil }
        self.teeID = teeID
        self.teeName = teeName
        teeColor = Self.string(json[L("teeColor")])
        courseRatingMen = Self.double(json[L("courseRatingMen")])
        slopeMen = Self.int(json[L("slopeMen")])
        courseRatingWomen = Self.double(json[L("courseRatingWomen")])
        slopeWomen = Self.int(json[L("slopeWomen")])
        lengthsMeters = (1...18).map { hole in
            guard let length = Self.double(json["length\(hole)"]) else { return nil }
            return length * (measure == "m" ? 1 : 0.9144)
        }
        parsMen = Self.intArray(json["pars"])
        indexesMen = Self.intArray(json["indexes"])
        parsWomen = Self.intArray(json[L("parsWomen")])
        indexesWomen = Self.intArray(json[L("indexesWomen")])
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
        sideFW = Self.int(json[L("sideFW")])
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
    case missingDataServiceConfiguration
    case localStorageUnavailable
    case unauthorized
    case httpStatus(Int)
    case dataService(status: Int, code: String, stage: String)
    case invalidResponse(String)
    case noGPSData(String)
    case noRatedTees(String)
    case savedCourseUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .localStorageUnavailable:
            return AppLanguage.localized("The course could not be saved on this device. Free up storage and select it again; the server copy remains cached.")
        case .missingDataServiceConfiguration:
            return AppLanguage.localized("Course information is temporarily unavailable. Please try again later.")
        case .unauthorized:
            return AppLanguage.localized("Please sign in again to load this course.")
        case .httpStatus:
            return AppLanguage.localized("We couldn't load this course right now. Check your connection and try again.")
        case .dataService(_, let code, _):
            switch code {
            case "provider_disabled":
                return AppLanguage.localized("Course information is temporarily unavailable. Please try again later.")
            case "provider_not_configured":
                return AppLanguage.localized("Course information is temporarily unavailable. Please try again later.")
            case "daily_budget_exceeded":
                return AppLanguage.localized("Course downloads are busy right now. Please try again later.")
            case "request_pending":
                return AppLanguage.localized("We're already loading this course. Please wait a moment and try again.")
            case "provider_cooldown":
                return AppLanguage.localized("We couldn't load this course just now. Please wait a few minutes, then try again.")
            case "ambiguous_attempt":
                return AppLanguage.localized("This course is temporarily unavailable. Please try another course or come back later.")
            case "cache_write_rejected":
                return AppLanguage.localized("We couldn't save this course just now. Please try again later.")
            case "rate_limit":
                return AppLanguage.localized("Too many course requests were made. Please wait a little and try again.")
            case "provider_unavailable", "invalid_provider_response":
                return AppLanguage.localized("Course information couldn't be loaded. Please try again later.")
            default:
                return AppLanguage.localized("We couldn't load this course right now. Please try again later.")
            }
        case .invalidResponse:
            return AppLanguage.localized("The course information appears incomplete. Please try again later.")
        case .noGPSData(let course):
            return AppLanguage.localized("Map data isn't available for %@. You can still use it for Handicap.",
                arguments: [course])
        case .noRatedTees(let course):
            return AppLanguage.localized("No rated tee sets were found for %@.", arguments: [course])
        case .savedCourseUnavailable(let course):
            return AppLanguage.localized("Previously downloaded course data for %@ is not available on this device. Your course selection has been preserved.",
                arguments: [course])
        }
    }
}
