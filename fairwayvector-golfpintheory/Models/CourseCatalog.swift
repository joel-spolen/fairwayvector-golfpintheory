import Foundation

struct SwedenCourseCatalog: Decodable {
    let schemaVersion: Int
    let revision: String
    let country: String
    let source: SwedenCatalogSource
    let clubs: [CatalogClub]
}

struct SwedenCatalogSource: Decodable {
    let name: String
    let url: String
    let retrievedAt: String
}

struct CatalogClub: Decodable, Hashable, Identifiable {
    let name: String
    let city: String?
    let region: String?
    let courses: [CatalogCourse]
    var golfAPIClubID: String? = nil

    var id: String { golfAPIClubID ?? name }
}

struct CatalogCourse: Decodable, Hashable, Identifiable {
    let name: String
    let holes: Int
    let par: Int
    let ratings: [CatalogTeeRating]
    var golfAPICourseID: String? = nil

    var id: String { golfAPICourseID ?? name }
}

struct CatalogTeeRating: Decodable, Hashable, Identifiable {
    let tee: String
    let sex: String
    let courseRating: Double
    let slopeRating: Int
    var golfAPITeeID: String? = nil

    var id: String { golfAPITeeID ?? "\(tee)|\(sex)" }
}

struct SelectedCourse: Hashable, Identifiable {
    let club: CatalogClub
    let course: CatalogCourse
    let tee: CatalogTeeRating

    var id: String { "\(club.name)|\(course.name)|\(tee.id)" }
}

struct SwedenCourseCatalogStore {
    let catalog: SwedenCourseCatalog

    init(bundle: Bundle = .main) {
        let nestedURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: "CourseCatalogs") ?? []
        let rootURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let url = (nestedURLs + rootURLs).first { $0.lastPathComponent == "sweden.json" }
        if let url,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(SwedenCourseCatalog.self, from: data),
           decoded.schemaVersion == 1 {
            catalog = decoded
        } else {
            catalog = SwedenCourseCatalog(
                schemaVersion: 1,
                revision: "",
                country: "Sweden",
                source: SwedenCatalogSource(name: "Unavailable", url: "", retrievedAt: ""),
                clubs: []
            )
        }
    }
}
