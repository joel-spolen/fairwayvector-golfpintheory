import CoreLocation

nonisolated struct GeoPoint: Codable, Hashable, Sendable {
    var lat: Double
    var lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(lat: coordinate.latitude, lon: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct Hole: Codable, Hashable, Identifiable {
    var number: Int
    var par: Int?
    var handicapIndex: Int?
    /// Line of play derived from the selected course data source.
    var path: [GeoPoint]
    var green: [GeoPoint]
    var fairways: [[GeoPoint]] = []
    var roughs: [[GeoPoint]] = []
    var tees: [[GeoPoint]] = []
    var pin: GeoPoint?
    var greenFront: GeoPoint?
    var greenBack: GeoPoint?
    var teeFront: GeoPoint?
    var teeBack: GeoPoint?
    var measuredLengthMeters: Double?
    var usesPointOnlyGeometry = false

    var id: Int { number }
    var tee: GeoPoint? { path.first }

    var greenCenter: GeoPoint? {
        green.count >= 3 ? GolfGeometry.centroid(of: green) : greenCenterPoint ?? path.last
    }

    var greenCenterPoint: GeoPoint?

    var flag: GeoPoint? { pin ?? greenCenter }

    init(
        number: Int,
        par: Int?,
        handicapIndex: Int? = nil,
        path: [GeoPoint],
        green: [GeoPoint],
        fairways: [[GeoPoint]] = [],
        roughs: [[GeoPoint]] = [],
        tees: [[GeoPoint]] = [],
        pin: GeoPoint? = nil,
        greenFront: GeoPoint? = nil,
        greenBack: GeoPoint? = nil,
        teeFront: GeoPoint? = nil,
        teeBack: GeoPoint? = nil,
        measuredLengthMeters: Double? = nil,
        greenCenterPoint: GeoPoint? = nil,
        usesPointOnlyGeometry: Bool = false
    ) {
        self.number = number
        self.par = par
        self.handicapIndex = handicapIndex
        self.path = path
        self.green = green
        self.fairways = fairways
        self.roughs = roughs
        self.tees = tees
        self.pin = pin
        self.greenFront = greenFront
        self.greenBack = greenBack
        self.teeFront = teeFront
        self.teeBack = teeBack
        self.measuredLengthMeters = measuredLengthMeters
        self.greenCenterPoint = greenCenterPoint
        self.usesPointOnlyGeometry = usesPointOnlyGeometry
    }

    private enum CodingKeys: String, CodingKey {
        case number, par, handicapIndex, path, green, fairways, roughs, tees, pin
        case greenFront, greenBack, teeFront, teeBack, measuredLengthMeters, greenCenterPoint, usesPointOnlyGeometry
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        number = try values.decode(Int.self, forKey: .number)
        par = try values.decodeIfPresent(Int.self, forKey: .par)
        handicapIndex = try values.decodeIfPresent(Int.self, forKey: .handicapIndex)
        path = try values.decode([GeoPoint].self, forKey: .path)
        green = try values.decode([GeoPoint].self, forKey: .green)
        fairways = try values.decodeIfPresent([[GeoPoint]].self, forKey: .fairways) ?? []
        roughs = try values.decodeIfPresent([[GeoPoint]].self, forKey: .roughs) ?? []
        tees = try values.decodeIfPresent([[GeoPoint]].self, forKey: .tees) ?? []
        pin = try values.decodeIfPresent(GeoPoint.self, forKey: .pin)
        greenFront = try values.decodeIfPresent(GeoPoint.self, forKey: .greenFront)
        greenBack = try values.decodeIfPresent(GeoPoint.self, forKey: .greenBack)
        teeFront = try values.decodeIfPresent(GeoPoint.self, forKey: .teeFront)
        teeBack = try values.decodeIfPresent(GeoPoint.self, forKey: .teeBack)
        measuredLengthMeters = try values.decodeIfPresent(Double.self, forKey: .measuredLengthMeters)
        greenCenterPoint = try values.decodeIfPresent(GeoPoint.self, forKey: .greenCenterPoint)
        usesPointOnlyGeometry = try values.decodeIfPresent(Bool.self, forKey: .usesPointOnlyGeometry) ?? false
    }

    var length: Double {
        if let measuredLengthMeters { return measuredLengthMeters }
        guard path.count > 1 else { return 0 }
        return zip(path, path.dropFirst()).reduce(0) { total, segment in
            total + GolfGeometry.distance(segment.0, segment.1)
        }
    }
}

struct CourseReference: Codable, Hashable {
    var osmRelationID: Int?
    var golfAPICourseID: String?
    var golfAPITeeID: String?
    var clubName: String
    var courseName: String
    var city: String
    var region: String
    var location: GeoPoint?
    var holeCount: Int
    var totalPar: Int
    var teeName: String
    var teeSex: String
    var courseRating: Double
    var slopeRating: Int

    var name: String { courseName }

    var cacheKey: String {
        [golfAPICourseID ?? "", clubName, courseName, teeName, teeSex]
            .joined(separator: "-")
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined()
            .lowercased()
    }

    init(selection: SelectedCourse) {
        osmRelationID = nil
        golfAPICourseID = selection.course.golfAPICourseID
        golfAPITeeID = selection.tee.golfAPITeeID
        clubName = selection.club.name
        courseName = selection.course.name
        city = selection.club.city ?? ""
        region = selection.club.region ?? ""
        location = nil
        holeCount = selection.course.holes
        totalPar = selection.course.par
        teeName = selection.tee.tee
        teeSex = selection.tee.sex
        courseRating = selection.tee.courseRating
        slopeRating = selection.tee.slopeRating
    }

    init(osmRelationID: Int, name: String) {
        self.osmRelationID = osmRelationID
        golfAPICourseID = nil
        golfAPITeeID = nil
        clubName = name
        courseName = name
        city = ""
        region = ""
        location = nil
        holeCount = 18
        totalPar = 72
        teeName = ""
        teeSex = "male"
        courseRating = 0
        slopeRating = 0
    }

    init(golfAPISelection: GolfAPICourseSelection) {
        osmRelationID = nil
        golfAPICourseID = golfAPISelection.course.courseID
        golfAPITeeID = golfAPISelection.tee.teeID
        clubName = golfAPISelection.club.clubName
        courseName = golfAPISelection.details.courseName
        city = golfAPISelection.details.city ?? golfAPISelection.club.city ?? ""
        region = golfAPISelection.details.state ?? golfAPISelection.club.state ?? ""
        if let latitude = golfAPISelection.details.latitude, let longitude = golfAPISelection.details.longitude {
            location = GeoPoint(lat: latitude, lon: longitude)
        } else {
            location = nil
        }
        let coursePars = golfAPISelection.sex == "female" ? golfAPISelection.details.parsWomen : golfAPISelection.details.parsMen
        let pars = golfAPISelection.tee.pars(for: golfAPISelection.sex, fallback: coursePars)
        holeCount = golfAPISelection.details.numHoles
        totalPar = pars.reduce(0, +)
        teeName = golfAPISelection.tee.teeName
        teeSex = golfAPISelection.sex
        courseRating = golfAPISelection.tee.rating(for: golfAPISelection.sex) ?? 0
        slopeRating = golfAPISelection.tee.slope(for: golfAPISelection.sex) ?? 0
    }

    static let hills = CourseReference(osmRelationID: 10480238, name: "Hills Golf & Country Club")
}

struct Course: Codable {
    var osmRelationID: Int?
    var golfAPICourseID: String?
    var name: String
    var holes: [Hole]
    var fetchedAt: Date

    init(osmRelationID: Int? = nil, golfAPICourseID: String? = nil, name: String, holes: [Hole], fetchedAt: Date) {
        self.osmRelationID = osmRelationID
        self.golfAPICourseID = golfAPICourseID
        self.name = name
        self.holes = holes
        self.fetchedAt = fetchedAt
    }
}

enum DistanceUnit: String, CaseIterable, Identifiable {
    case meters
    case yards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meters: "Meters"
        case .yards: "Yards"
        }
    }

    var symbol: String {
        switch self {
        case .meters: "m"
        case .yards: "yd"
        }
    }

    func value(_ meters: Double) -> Int {
        let converted = self == .meters ? meters : meters / 0.9144
        return Int(converted.rounded())
    }

    func format(_ meters: Double) -> String {
        "\(value(meters)) \(symbol)"
    }
}
