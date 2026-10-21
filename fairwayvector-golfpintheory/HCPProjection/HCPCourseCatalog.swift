import Foundation

nonisolated struct CountryCourseCatalog: Codable, Sendable {
    let schemaVersion: Int
    let revision: String
    let country: String
    let source: CourseCatalogSource
    let clubs: [CourseCatalogClub]
}

nonisolated struct CourseCatalogSource: Codable, Sendable {
    let name: String
    let url: String
    let retrievedAt: String
}

nonisolated struct CourseCatalogClub: Codable, Sendable {
    let name: String
    let city: String?
    let region: String?
    let courses: [CourseCatalogCourse]
}

nonisolated struct CourseCatalogCourse: Codable, Sendable {
    let name: String
    let holes: Int
    let par: Int
    let ratings: [CourseCatalogRating]
}

nonisolated struct CourseCatalogRating: Codable, Sendable {
    let tee: String
    let sex: PlayerSex
    let courseRating: Double
    let slopeRating: Int
}

nonisolated struct CourseClubInfo: Hashable, Identifiable, Sendable {
    var id: String { "\(country)|\(name)" }
    let name: String
    let city: String
    let country: String

    init(name: String, city: String, country: String) {
        self.name = name
        self.city = city
        self.country = country
    }

    init(custom club: GolfClub) {
        self.init(name: club.name, city: club.city, country: club.country)
    }
}

nonisolated struct CourseInfo: Hashable, Identifiable, Sendable {
    var id: String { "\(clubName)|\(name)" }
    let clubName: String
    let name: String

    init(clubName: String, name: String) {
        self.clubName = clubName
        self.name = name
    }

    init(custom course: GolfCourse) {
        self.init(clubName: course.clubName, name: course.name)
    }
}

nonisolated struct CourseTeeInfo: Hashable, Identifiable, Sendable {
    var id: String { "\(clubName)|\(courseName)|\(name)|\(ratingSex?.rawValue ?? "universal")" }
    let clubName: String
    let courseName: String
    let name: String
    let holes: Int
    let par: Int
    let courseRating: Double
    let slopeRating: Int
    let ratingSex: PlayerSex?
    let holeParsData: [Int]?
    let holeHandicapIndicesData: [Int]?

    init(
        clubName: String,
        courseName: String,
        name: String,
        holes: Int,
        par: Int,
        courseRating: Double,
        slopeRating: Int,
        ratingSex: PlayerSex?,
        holeParsData: [Int]?,
        holeHandicapIndicesData: [Int]?
    ) {
        self.clubName = clubName
        self.courseName = courseName
        self.name = name
        self.holes = holes
        self.par = par
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.ratingSex = ratingSex
        self.holeParsData = holeParsData
        self.holeHandicapIndicesData = holeHandicapIndicesData
    }

    init(custom tee: TeeSet) {
        self.init(
            clubName: tee.clubName,
            courseName: tee.courseName,
            name: tee.name,
            holes: tee.holes,
            par: tee.par,
            courseRating: tee.courseRating,
            slopeRating: tee.slopeRating,
            ratingSex: tee.ratingSex,
            holeParsData: tee.holeParsData,
            holeHandicapIndicesData: tee.holeHandicapIndicesData
        )
    }

    var holePars: [Int] {
        guard let holeParsData, holeParsData.count == holes else {
            return TeeSet.defaultPars(for: holes, totalPar: par)
        }
        return holeParsData
    }

    var holeHandicapIndices: [Int] {
        guard let holeHandicapIndicesData, holeHandicapIndicesData.count == holes else {
            return Array(1...max(holes, 1))
        }
        return holeHandicapIndicesData
    }

    var snapshot: TeeSnapshot {
        TeeSnapshot(
            clubName: clubName,
            courseName: courseName,
            teeName: name,
            holes: holes,
            par: par,
            courseRating: courseRating,
            slopeRating: slopeRating
        )
    }
}

nonisolated final class CourseCatalogStore: @unchecked Sendable {
    private let clubsByCountry: [String: [CourseClubInfo]]
    private let coursesByCountry: [String: [CourseInfo]]
    private let teesByCountryAndSex: [String: [PlayerSex: [CourseTeeInfo]]]

    nonisolated init(bundle: Bundle = .main) {
        var clubsByCountry: [String: [CourseClubInfo]] = [:]
        var coursesByCountry: [String: [CourseInfo]] = [:]
        var teesByCountryAndSex: [String: [PlayerSex: [CourseTeeInfo]]] = [:]

        for catalog in CourseCatalogLoader.bundledCatalogs(bundle: bundle) {
            clubsByCountry[catalog.country] = catalog.clubs.map {
                CourseClubInfo(name: $0.name, city: $0.city ?? "", country: catalog.country)
            }
            coursesByCountry[catalog.country] = catalog.clubs.flatMap { club in
                club.courses.map { CourseInfo(clubName: club.name, name: $0.name) }
            }

            var ratingsBySex: [PlayerSex: [CourseTeeInfo]] = [:]
            for club in catalog.clubs {
                for course in club.courses {
                    for rating in course.ratings {
                        ratingsBySex[rating.sex, default: []].append(
                            CourseTeeInfo(
                                clubName: club.name,
                                courseName: course.name,
                                name: rating.tee,
                                holes: course.holes,
                                par: course.par,
                                courseRating: rating.courseRating,
                                slopeRating: rating.slopeRating,
                                ratingSex: rating.sex,
                                holeParsData: nil,
                                holeHandicapIndicesData: nil
                            )
                        )
                    }
                }
            }
            teesByCountryAndSex[catalog.country] = ratingsBySex
        }

        self.clubsByCountry = clubsByCountry
        self.coursesByCountry = coursesByCountry
        self.teesByCountryAndSex = teesByCountryAndSex
    }

    func clubs(in country: String) -> [CourseClubInfo] {
        clubsByCountry[country] ?? []
    }

    var countries: [String] {
        clubsByCountry.keys.sorted()
    }

    func tees(in country: String, for sex: PlayerSex) -> [CourseTeeInfo] {
        teesByCountryAndSex[country]?[sex] ?? []
    }

    func courses(in country: String) -> [CourseInfo] {
        coursesByCountry[country] ?? []
    }

    func containsRating(
        country: String,
        clubName: String,
        courseName: String,
        teeName: String,
        sex: PlayerSex
    ) -> Bool {
        tees(in: country, for: sex).contains {
            $0.clubName.localizedCaseInsensitiveCompare(clubName) == .orderedSame &&
            $0.courseName.localizedCaseInsensitiveCompare(courseName) == .orderedSame &&
            $0.name.localizedCaseInsensitiveCompare(teeName) == .orderedSame
        }
    }
}

enum CourseCatalogLoader {
    nonisolated static func bundledCatalogs(bundle: Bundle = .main) -> [CountryCourseCatalog] {
        let nestedURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: "CourseCatalogs") ?? []
        let rootURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let urls = Array(Set(nestedURLs + rootURLs))
        let decoder = JSONDecoder()

        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let catalog = try? decoder.decode(CountryCourseCatalog.self, from: data),
                  catalog.schemaVersion == 1 else {
                return nil
            }
            return catalog
        }
    }
}

