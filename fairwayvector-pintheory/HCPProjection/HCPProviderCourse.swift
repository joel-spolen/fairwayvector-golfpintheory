import Foundation

/// Transient identity and verified provider values; no SwiftData schema or history migration.
struct HCPProviderCourse: Hashable {
    let providerID: String
    let teeID: String
    let tee: CourseTeeInfo

    var id: String { "\(providerID)|\(teeID)|\(tee.ratingSex?.rawValue ?? "")" }

    static func convert(detail: GolfAPICourseDetail, tee: GolfAPITee, sex: String,
                        clubName: String? = nil) throws -> HCPProviderCourse {
        guard !DevelopmentAPIConfiguration.isDemoCourse(detail.courseID),
              !detail.courseID.isEmpty, let category = PlayerSex(rawValue: sex),
              detail.tees.contains(tee), [9, 18].contains(detail.numHoles),
              let rating = tee.rating(for: sex), rating.isFinite, rating > 0, rating <= 100,
              let slope = tee.slope(for: sex), (55...155).contains(slope) else {
            throw GolfAPIError.invalidResponse("A real 9- or 18-hole course and valid rating for the selected category are required.")
        }
        let pars = sharedHoleData(detail: detail, men: \.parsMen, women: \.parsWomen,
                      courseMen: detail.parsMen, courseWomen: detail.parsWomen)
        let indices = sharedHoleData(detail: detail, men: \.indexesMen, women: \.indexesWomen,
                         courseMen: detail.indexesMen, courseWomen: detail.indexesWomen)
        // Par must be complete to calculate a total. Missing SI disables hole-by-hole;
        // incomplete/invalid supplied SI is never replaced with invented sequential indices.
        guard pars.count == detail.numHoles, pars.allSatisfy({ (3...6).contains($0) }) else {
            throw GolfAPIError.invalidResponse("Complete provider hole pars are required; use Custom course or an official differential instead.")
        }
        let validIndices = indices.count == detail.numHoles
            && Set(indices).count == detail.numHoles && indices.allSatisfy { (1...18).contains($0) }
        return HCPProviderCourse(providerID: detail.courseID, teeID: tee.teeID,
            tee: CourseTeeInfo(clubName: clubName ?? detail.clubName, courseName: detail.courseName,
                name: tee.teeName, holes: detail.numHoles, par: pars.reduce(0, +),
                courseRating: rating, slopeRating: slope, ratingSex: category,
                holeParsData: pars, holeHandicapIndicesData: validIndices ? indices : nil))
    }

    private static func sharedHoleData(
        detail: GolfAPICourseDetail,
        men: KeyPath<GolfAPITee, [Int]>,
        women: KeyPath<GolfAPITee, [Int]>,
        courseMen: [Int],
        courseWomen: [Int]
    ) -> [Int] {
        if courseMen.count == detail.numHoles { return courseMen }
        if courseWomen.count == detail.numHoles { return courseWomen }
        if let teeData = detail.tees.lazy.map({ $0[keyPath: men] }).first(where: { $0.count == detail.numHoles }) {
            return teeData
        }
        return detail.tees.lazy.map({ $0[keyPath: women] }).first(where: { $0.count == detail.numHoles }) ?? []
    }
}