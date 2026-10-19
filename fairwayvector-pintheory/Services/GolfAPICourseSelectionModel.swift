import Foundation
import Observation

@MainActor
@Observable
final class GolfAPICourseSelectionModel {
    enum Purpose { case map, handicap }
    private let client: GolfAPIClient
    let purpose: Purpose
    let savedCourses: [CourseReference]
    var savedClubs: [GolfAPIClub] { client.cachedClubs(requiresGPS: purpose == .map) }

    var selectedRegion = "Europe"
    var selectedCountry = "Sweden"
    var searchText = ""
    private(set) var clubs: [GolfAPIClub] = []
    private(set) var selectedClubID: String?
    private(set) var selectedCourseID: String?
    private(set) var courseDetail: GolfAPICourseDetail?
    var selectedSex = "male"
    var selectedTeeID: String?
    private(set) var isSearching = false
    private(set) var isLoadingCourse = false
    private(set) var errorMessage: String?
    private(set) var apiRequestsLeft: String?

    init(client: GolfAPIClient? = nil, purpose: Purpose = .map, sex: String = "male") {
        let resolved = client ?? .shared
        self.client = resolved
        self.purpose = purpose
        self.selectedSex = sex
        savedCourses = purpose == .map && resolved.mode == .mock ? resolved.savedReferences : []
    }

    var isConfigured: Bool { client.isConfigured }

    func hasSavedCourse(_ reference: CourseReference) -> Bool {
        if CourseDataStore.readCourse(reference: reference) != nil { return true }
        guard let id = reference.golfAPICourseID, let payload = client.cachedPayload(id: id) else { return false }
        return (try? GolfAPICourseBuilder.build(reference: reference, payload: payload)) != nil
    }

    var coverageRegions: [GolfAPICoverageRegion] { GolfAPICoverage.regions }

    var availableCountries: [String] {
        coverageRegions.first { $0.name == selectedRegion }?.countries ?? []
    }

    var selectedClub: GolfAPIClub? {
        clubs.first { $0.clubID == selectedClubID }
    }

    var selectedCourse: GolfAPICourseSummary? {
        selectedClub?.courses.first { $0.courseID == selectedCourseID }
    }

    var ratedTees: [GolfAPITee] {
        guard let courseDetail else { return [] }
        return courseDetail.tees.filter { tee in
            if purpose == .handicap {
                return (try? HCPProviderCourse.convert(detail: courseDetail, tee: tee, sex: selectedSex)) != nil
            }
            return tee.rating(for: selectedSex) != nil && tee.slope(for: selectedSex) != nil
        }
    }

    var selectedTee: GolfAPITee? {
        ratedTees.first { $0.teeID == selectedTeeID }
    }

    var selection: GolfAPICourseSelection? {
        guard let selectedClub, let selectedCourse, let courseDetail, let selectedTee else { return nil }
        return GolfAPICourseSelection(
            club: selectedClub,
            course: selectedCourse,
            details: courseDetail,
            tee: selectedTee,
            sex: selectedSex
        )
    }

    func search(forceRefresh: Bool = false) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedCountry.isEmpty || !query.isEmpty else {
            errorMessage = "Select a region and country, or enter a club name to search."
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            clubs = try await client.searchClubs(named: query, country: selectedCountry, forceRefresh: forceRefresh,
                                               requiresGPS: purpose == .map)
            if purpose == .handicap {
                clubs = clubs.compactMap { club in
                    let courses = club.courses.filter { !DevelopmentAPIConfiguration.isDemoCourse($0.courseID) }
                    guard !courses.isEmpty else { return nil }
                    return GolfAPIClub(clubID: club.clubID, clubName: club.clubName, city: club.city,
                                       state: club.state, country: club.country, courses: courses)
                }
            }
            apiRequestsLeft = nil
            selectedClubID = nil
            selectedCourseID = nil
            courseDetail = nil
            selectedTeeID = nil
            if clubs.isEmpty {
                let terms = [selectedCountry, query].filter { !$0.isEmpty }.joined(separator: " · ")
                errorMessage = "No golf clubs matched \"\(terms)\"."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectClub(_ club: GolfAPIClub) {
        if let index = clubs.firstIndex(where: { $0.clubID == club.clubID }) {
            clubs[index] = club
        } else {
            clubs.append(club)
        }
        selectedClubID = club.clubID
        selectedCourseID = nil
        courseDetail = nil
        selectedTeeID = nil
        errorMessage = nil
    }

    func selectRegion(_ region: String) {
        selectedRegion = region
        selectedCountry = ""
        clubs = []
        selectedClubID = nil
        selectedCourseID = nil
        courseDetail = nil
        selectedTeeID = nil
        errorMessage = nil
    }

    func selectCourse(_ course: GolfAPICourseSummary) async {
        guard !isLoadingCourse else { return }
        guard purpose != .handicap || !DevelopmentAPIConfiguration.isDemoCourse(course.courseID) else {
            errorMessage = "This course cannot be used for Handicap. Choose a rated course or an explicitly custom course."
            return
        }
        guard purpose != .map || course.hasGPS else {
            errorMessage = "\(course.courseName) has no GPS data in Golf API."
            return
        }
        selectedCourseID = course.courseID
        courseDetail = nil
        selectedTeeID = nil
        isLoadingCourse = true
        errorMessage = nil
        defer { isLoadingCourse = false }
        do {
            let details = try await client.loadCourseDetail(id: course.courseID)
            guard selectedCourseID == course.courseID, !Task.isCancelled else { return }
            courseDetail = details
            apiRequestsLeft = nil
            if ratedTees.isEmpty {
                errorMessage = purpose == .handicap
                    ? "No eligible \(selectedSex == "female" ? "Women" : "Men") tees with valid ratings and complete hole pars. Use Custom course or an official differential."
                    : "No rated tee sets were returned for this course."
            } else {
                // Map keeps its default; Handicap requires explicit tee confirmation.
                selectedTeeID = purpose == .map ? ratedTees.first?.teeID : nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Explicit recent selection always revalidates the exact provider ID and current rating sex.
    func selectReference(_ reference: CourseReference) async {
        guard let id = reference.golfAPICourseID else {
            errorMessage = "This recent course has no Golf API identity. Select a provider course or use Custom course."
            return
        }
        let summary = GolfAPICourseSummary(courseID: id, courseName: reference.courseName,
            numHoles: reference.holeCount, hasGPS: client.cachedDetail(id: id)?.hasGPS ?? (purpose == .map), timestampUpdated: nil)
        let club = GolfAPIClub(clubID: id, clubName: reference.clubName,
            city: reference.city, state: reference.region, country: "", courses: [summary])
        selectClub(club)
        await selectCourse(summary)
        if purpose == .handicap {
            selectedTeeID = reference.teeSex == selectedSex
                && ratedTees.contains(where: { $0.teeID == reference.golfAPITeeID }) ? reference.golfAPITeeID : nil
        }
    }
}
