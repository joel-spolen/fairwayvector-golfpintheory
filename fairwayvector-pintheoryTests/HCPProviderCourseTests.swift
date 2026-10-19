import Foundation
import Testing
@testable import fairwayvector_pintheory

/// Offline regression source. Compile only; sessions forbid any actual transport.
@MainActor
struct HCPProviderCourseTests {
    private func json(holes: Int = 18, id: String = "hcp-real-course", slope: Int = 132,
                      rating: Double = 73.2, pars: [Int]? = nil, indices: [Int]? = nil) -> [String: Any] {
        ["courseID": id, "clubID": "hcp-club", "clubName": "Provider club",
         "courseName": "Provider course", "country": "Sweden", "numHoles": holes, "hasGPS": false,
         "parsMen": pars ?? Array(repeating: 4, count: holes),
         "parsWomen": Array(repeating: 5, count: holes),
         "indexesMen": indices ?? Array(1...holes),
         "indexesWomen": Array((1...holes).reversed()),
         "tees": [["teeID": "tee-exact", "teeName": "62", "courseRatingMen": rating,
                   "slopeMen": slope, "courseRatingWomen": 76.8, "slopeWomen": 144],
                  ["teeID": "tee-other", "teeName": "55", "courseRatingMen": 69.1, "slopeMen": 121]]]
    }

    private func forbiddenSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GPXZForbiddenNetworkProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func exactSexRatingParsIndicesAndStableIdentityWithoutGPS() throws {
        let detail = try GolfAPICourseDetail(json: json())
        let tee = detail.tees[0]
        let men = try HCPProviderCourse.convert(detail: detail, tee: tee, sex: "male")
        let women = try HCPProviderCourse.convert(detail: detail, tee: tee, sex: "female")
        #expect(men.providerID == "hcp-real-course")
        #expect(men.teeID == "tee-exact")
        #expect(men.tee.courseRating == 73.2 && men.tee.slopeRating == 132)
        #expect(women.tee.courseRating == 76.8 && women.tee.slopeRating == 144)
        #expect(men.tee.ratingSex == .male && women.tee.ratingSex == .female)
        #expect(men.tee.par == 72 && women.tee.par == 72)
        #expect(men.tee.holeParsData == detail.parsMen)
        #expect(women.tee.holeParsData == detail.parsMen)
        #expect(men.tee.holeHandicapIndicesData == detail.indexesMen)
        #expect(women.tee.holeHandicapIndicesData == detail.indexesMen)
        #expect(men.id != women.id)
        #expect(!detail.hasGPS)
        #expect(men.tee.snapshot.courseRating == 73.2)
    }

    @Test func courseHoleDataIsSharedAcrossTeeAndRatingCategory() throws {
        var raw = json()
        var tees = raw["tees"] as! [[String: Any]]
        tees[0]["pars"] = Array(repeating: 3, count: 18)
        tees[0]["indexes"] = Array((1...18).reversed())
        raw["tees"] = tees
        let detail = try GolfAPICourseDetail(json: raw)
        let result = try HCPProviderCourse.convert(detail: detail, tee: detail.tees[0], sex: "male")
        #expect(result.tee.par == 72)
        #expect(result.tee.holeParsData == detail.parsMen)
        #expect(result.tee.holeHandicapIndicesData == detail.indexesMen)
    }

    @Test func nineHolesRetainActualFullCourseStrokeIndices() throws {
        let indices = [1, 3, 5, 7, 9, 11, 13, 15, 17]
        let detail = try GolfAPICourseDetail(json: json(holes: 9, rating: 36.6, indices: indices))
        let result = try HCPProviderCourse.convert(detail: detail, tee: detail.tees[0], sex: "male")
        #expect(result.tee.holes == 9 && result.tee.par == 36)
        #expect(result.tee.courseRating == 36.6)
        #expect(result.tee.holeHandicapIndicesData == indices)
    }

    @Test func incompleteParsInvalidRatingsAndDemoAreRejected() throws {
        for raw in [json(pars: [4]), json(slope: 54), json(slope: 156), json(rating: 0),
                    json(holes: 12), json(id: DevelopmentGolfAPIFixtures.courseID)] {
            let detail = try GolfAPICourseDetail(json: raw)
            #expect(throws: GolfAPIError.self) {
                try HCPProviderCourse.convert(detail: detail, tee: detail.tees[0], sex: "male")
            }
        }
        let detail = try GolfAPICourseDetail(json: json())
        #expect(throws: GolfAPIError.self) {
            try HCPProviderCourse.convert(detail: detail, tee: detail.tees[1], sex: "female")
        }
        #expect(throws: GolfAPIError.self) {
            try HCPProviderCourse.convert(detail: detail, tee: detail.tees[0], sex: "unknown")
        }
    }

    @Test func missingOrInvalidStrokeIndicesDisableHoleByHoleOnly() throws {
        for indices in [[], [1], Array(repeating: 1, count: 18), Array(2...19)] {
            let detail = try GolfAPICourseDetail(json: json(indices: indices))
            let result = try HCPProviderCourse.convert(detail: detail, tee: detail.tees[0], sex: "male")
            #expect(result.tee.holeHandicapIndicesData == nil)
            #expect(result.tee.holeParsData == detail.parsMen)
            #expect(result.tee.snapshot.par == 72)
        }
    }

    @Test func bothModesReuseDetailOnlyCacheAndMapStillRequiresGPS() async throws {
        for mode in [DevelopmentAPIConfiguration.Mode.mock, .live] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let cache = GolfAPICache(directoryURL: root)
            let bytes = try JSONSerialization.data(withJSONObject: json())
            cache.writeCourseDetail(bytes, id: "hcp-real-course")
            let client = GolfAPIClient(session: forbiddenSession(), cache: cache, apiKey: "",
                                       mode: mode, bundledSavedCourses: nil)
            #expect(client.cachedClubs().isEmpty)
            let club = try #require(client.cachedClubs(requiresGPS: false).first)
            let course = try #require(club.courses.first)
            let handicap = GolfAPICourseSelectionModel(client: client, purpose: .handicap, sex: "female")
            #expect(handicap.courseDetail == nil) // Construction/discovery never loads a selected detail.
            handicap.selectClub(club)
            await handicap.selectCourse(course)
            #expect(handicap.selectedTeeID == nil && handicap.selection == nil)
            #expect(handicap.ratedTees.count == 1)
            handicap.selectedTeeID = handicap.ratedTees.first?.teeID
            #expect(handicap.selection?.sex == "female")
            #expect(cache.readCoordinates(id: course.courseID) == nil)
            #expect(cache.readCourseDetail(id: course.courseID) == bytes)
            let map = GolfAPICourseSelectionModel(client: client)
            map.selectClub(club)
            await map.selectCourse(course)
            #expect(map.courseDetail == nil && map.errorMessage != nil)
            if mode == .mock {
                handicap.searchText = "Provider"
                await handicap.search()
                #expect(handicap.clubs.contains { $0.clubID == club.clubID })
                handicap.searchText = "Hills"
                await handicap.search()
                #expect(handicap.clubs.isEmpty) // Demo Hills never enters HCP chooser.
            }
        }
    }

    @Test func recentDifferentSexRequiresExplicitTeeChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = GolfAPICache(directoryURL: root)
        let bytes = try JSONSerialization.data(withJSONObject: json())
        cache.writeCourseDetail(bytes, id: "hcp-real-course")
        let client = GolfAPIClient(session: forbiddenSession(), cache: cache, apiKey: "", mode: .mock, bundledSavedCourses: nil)
        let club = try #require(client.cachedClubs(requiresGPS: false).first)
        let detail = try GolfAPICourseDetail(json: json())
        let reference = GolfAPICourseSelection(club: club, course: club.courses[0],
            details: detail, tee: detail.tees[0], sex: "male").reference
        let model = GolfAPICourseSelectionModel(client: client, purpose: .handicap, sex: "female")
        await model.selectReference(reference)
        #expect(model.courseDetail?.courseID == reference.golfAPICourseID)
        #expect(model.selectedTeeID == nil && model.selection == nil)
        model.selectedTeeID = detail.tees[0].teeID
        #expect(model.selection?.tee.rating(for: "female") == 76.8)
        let sameSex = GolfAPICourseSelectionModel(client: client, purpose: .handicap, sex: "male")
        await sameSex.selectReference(reference)
        #expect(sameSex.selection?.tee.teeID == reference.golfAPITeeID)
    }

    @Test func bundledRealHillsSharesAllEligibleRatingValuesAndRejectsDemo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = BundledSavedCourseStore()
        let client = GolfAPIClient(session: forbiddenSession(), cache: GolfAPICache(directoryURL: root),
            apiKey: "", mode: .mock, bundledSavedCourses: bundle)
        let club = try #require(client.cachedClubs(requiresGPS: false).first { club in
            club.courses.contains { $0.courseID == BundledSavedCourseStore.hillsCourseID }
        })
        let course = try #require(club.courses.first { $0.courseID == BundledSavedCourseStore.hillsCourseID })
        for sex in ["male", "female"] {
            let model = GolfAPICourseSelectionModel(client: client, purpose: .handicap, sex: sex)
            #expect(model.savedCourses.isEmpty) // Handicap never builds geometry or reads coordinate caches.
            model.selectClub(club)
            await model.selectCourse(course)
            let detail = try #require(model.courseDetail)
            #expect(model.selectedTeeID == nil)
            #expect(!model.ratedTees.isEmpty)
            for tee in model.ratedTees {
                model.selectedTeeID = tee.teeID
                let result = try HCPProviderCourse.convert(detail: detail, tee: tee, sex: sex)
                #expect(result.providerID == BundledSavedCourseStore.hillsCourseID)
                #expect(result.tee.courseRating == tee.rating(for: sex))
                #expect(result.tee.slopeRating == tee.slope(for: sex))
                #expect(result.tee.holeParsData?.count == 18)
                #expect(result.tee.holeHandicapIndicesData?.count == 18)
            }
        }
        let model = GolfAPICourseSelectionModel(client: client, purpose: .handicap)
        let demo = GolfAPICourseSummary(courseID: DevelopmentGolfAPIFixtures.courseID,
            courseName: "DEMO", numHoles: 18, hasGPS: true, timestampUpdated: nil)
        await model.selectCourse(demo)
        #expect(model.courseDetail == nil && model.selection == nil && model.errorMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: root.path)) // Mock bundle access remains read-only.
    }
}