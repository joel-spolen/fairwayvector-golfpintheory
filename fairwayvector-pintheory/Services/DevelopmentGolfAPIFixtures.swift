import Foundation

/// Invented layout/ratings near Hills, NOT the club's actual course data or survey.
enum DevelopmentGolfAPIFixtures {
    static let courseID = "mock-hills-v1"
    static let clubID = "mock-hills-club-v1"
    static let lengths = [370, 410, 165, 495, 345, 390, 180, 510, 365, 405, 155, 480, 355, 425, 175, 505, 380, 400]
    static let pars = [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4]
    static let indexes = [9, 3, 17, 1, 13, 7, 15, 5, 11, 10, 18, 2, 14, 4, 16, 6, 12, 8]

    static func detailJSON(id: String) -> [String: Any] {
        let tees: [[String: Any]] = [("mock-blue-v1", "Demo Blue", 1.0, 72.1, 132),
                                    ("mock-red-v1", "Demo Red", 0.84, 68.2, 121)].map { id, name, scale, rating, slope in
            var tee: [String: Any] = ["teeID": id, "teeName": name,
                "courseRatingMen": rating, "slopeMen": slope,
                "courseRatingWomen": rating + 4, "slopeWomen": slope + 5]
            for hole in 1...18 { tee["length\(hole)"] = Double(lengths[hole - 1]) * scale }
            return tee
        }
        return ["courseID": id, "clubID": clubID, "clubName": "Demo Hills",
            "courseName": "Demo Hills · synthetic 18 holes", "city": "Mölndal", "state": "Västra Götaland",
            "country": "Sweden", "latitude": 57.623, "longitude": 12.0,
            "numHoles": 18, "measure": "m", "hasGPS": 1,
            "parsMen": pars, "parsWomen": pars, "indexesMen": indexes, "indexesWomen": indexes, "tees": tees]
    }

    static func reference(teeID: String? = nil, sex: String = "male") -> CourseReference {
        // Constant fixture schema; programmer errors must never fall back to a real reference.
        let detail = try! GolfAPICourseDetail(json: detailJSON(id: courseID))
        let summary = GolfAPICourseSummary(courseID: courseID, courseName: detail.courseName,
            numHoles: 18, hasGPS: true, timestampUpdated: nil)
        let club = GolfAPIClub(clubID: clubID, clubName: detail.clubName, city: detail.city,
            state: detail.state, country: "Sweden", courses: [summary])
        let tee = detail.tees.first { $0.teeID == teeID } ?? detail.tees[0]
        return GolfAPICourseSelection(club: club, course: summary, details: detail, tee: tee, sex: sex).reference
    }

    static func response(path: String, queryItems: [URLQueryItem]) throws -> Data {
        let query = Dictionary(queryItems.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        let object: [String: Any]
        if path == "/clubs" {
            let country = query["country"] ?? "", region = query["state"] ?? "", name = query["name"] ?? ""
            let matches = (country.isEmpty || country.caseInsensitiveCompare("Sweden") == .orderedSame)
                && (region.isEmpty || "Västra Götaland".localizedCaseInsensitiveContains(region))
                && (name.isEmpty || "Demo Hills Golf & Country Club".localizedCaseInsensitiveContains(name))
            let club: [String: Any] = ["clubID": clubID, "clubName": "Demo Hills", "city": "Mölndal",
                "state": "Västra Götaland", "country": "Sweden",
                "courses": [["courseID": courseID, "courseName": "Demo Hills · synthetic 18 holes", "numHoles": 18, "hasGPS": 1]]]
            object = ["clubs": matches ? [club] : [], "numClubs": matches ? 1 : 0]
        } else if path == "/courses" {
            object = ["courses": []] // No update probes or pretend provider timestamps.
        } else if path.hasPrefix("/courses/") {
            let id = String(path.dropFirst("/courses/".count))
            guard id == courseID else { throw GolfAPIError.savedCourseUnavailable(id) }
            object = detailJSON(id: id)
        } else if path.hasPrefix("/coordinates/") {
            let id = String(path.dropFirst("/coordinates/".count))
            guard id == courseID else { throw GolfAPIError.savedCourseUnavailable(id) }
            var coordinates: [[String: Any]] = []
            for hole in 1...18 {
                let column = (hole - 1) % 3, row = (hole - 1) / 3
                let north = row % 2 == 0 ? 1.0 : -1.0
                let tee = GeoPoint(lat: 57.619 + Double(row) * 0.0015, lon: 11.994 + Double(column) * 0.005)
                let green = GeoPoint(lat: tee.lat + north * Double(lengths[hole - 1]) / TerrainGeometry.radius * 180 / .pi,
                                     lon: tee.lon + 0.0004)
                for (poi, location, point) in [(11, 0, tee),
                    (12, 0, GeoPoint(lat: tee.lat - north * 0.00008, lon: tee.lon)),
                    (1, 1, GeoPoint(lat: green.lat - north * 0.00012, lon: green.lon)),
                    (1, 2, green), (1, 3, GeoPoint(lat: green.lat + north * 0.00012, lon: green.lon))] {
                    coordinates.append(["poi": poi, "location": location, "hole": hole,
                                        "latitude": point.lat, "longitude": point.lon])
                }
            }
            object = ["courseID": id, "coordinates": coordinates, "numCoordinates": coordinates.count]
        } else { throw GolfAPIError.invalidResponse("Unknown development fixture endpoint.") }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}