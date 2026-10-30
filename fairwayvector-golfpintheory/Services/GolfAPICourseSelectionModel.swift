import Foundation
import Observation

@MainActor
@Observable
final class GolfAPICourseSelectionModel {
    static let catalogPageSize = 50
    enum Purpose { case map, handicap }
    private let client: GolfAPIClient
    private let pageSize: Int
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
    private(set) var isLoadingMore = false
    private(set) var hasMoreClubs = false
    private(set) var totalClubCount = 0
    private(set) var isLoadingCourse = false
    private(set) var errorMessage: String?
    private(set) var apiRequestsLeft: String?
    private var currentPage = 0
    private var activeSearchQuery = ""
    private var activeSearchCountry = ""
    private var activeSearchCountries: [String] = []
    private var activeSearchState = ""
    private var activeDatasetVersion: String?

    init(client: GolfAPIClient? = nil, purpose: Purpose = .map, sex: String = "male", pageSize: Int = 50) {
        let resolved = client ?? .shared
        self.client = resolved
        self.pageSize = min(max(pageSize, 1), Self.catalogPageSize)
        self.purpose = purpose
        self.selectedSex = sex
        savedCourses = purpose == .map ? resolved.savedReferences : []
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
        selectableTees.first { $0.teeID == selectedTeeID }
    }

    /// Ratings are required for Handicap, not for browsing downloaded GPS holes.
    var selectableTees: [GolfAPITee] {
        purpose == .map ? (courseDetail?.tees ?? []) : ratedTees
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
        guard !isSearching else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedCountry.isEmpty || !availableCountries.isEmpty || !query.isEmpty else {
            errorMessage = "Select a region and country, or enter a club name to search."
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        activeSearchQuery = query
        activeSearchCountry = selectedCountry
        activeSearchCountries = selectedCountry.isEmpty ? availableCountries : []
        activeSearchState = ""
        activeDatasetVersion = nil
        clubs = []
        currentPage = 0
        totalClubCount = 0
        hasMoreClubs = false
        selectedClubID = nil
        selectedCourseID = nil
        courseDetail = nil
        selectedTeeID = nil
        do {
            let result = try await client.searchCatalogClubs(named: query, country: selectedCountry,
                countries: activeSearchCountries, state: activeSearchState,
                page: 1, pageSize: pageSize)
            clubs = eligibleClubs(result.clubs)
            currentPage = result.page
            totalClubCount = result.numAllClubs
            hasMoreClubs = result.hasMore
            activeDatasetVersion = result.datasetVersion
            apiRequestsLeft = nil
            if clubs.isEmpty && !hasMoreClubs {
                let terms = [selectedCountry, query].filter { !$0.isEmpty }.joined(separator: " · ")
                errorMessage = "No golf clubs matched \"\(terms)\"."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreClubs() async {
        guard hasMoreClubs, !isSearching, !isLoadingMore else { return }
        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }
        do {
            let nextPage = currentPage + 1
            let result = try await client.searchCatalogClubs(named: activeSearchQuery,
                country: activeSearchCountry, countries: activeSearchCountries,
                state: activeSearchState,
                page: nextPage, pageSize: pageSize)
            guard result.page == nextPage else {
                throw GolfAPIError.invalidResponse("The course catalog returned an unexpected page.")
            }
            guard result.datasetVersion == activeDatasetVersion else {
                clubs = []
                currentPage = 0
                hasMoreClubs = false
                totalClubCount = 0
                throw GolfAPIError.invalidResponse("The course catalog changed while loading results. Search again.")
            }
            let existing = Set(clubs.map(\.id))
            clubs.append(contentsOf: eligibleClubs(result.clubs).filter { !existing.contains($0.id) })
            currentPage = result.page
            totalClubCount = result.numAllClubs
            hasMoreClubs = result.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func eligibleClubs(_ values: [GolfAPIClub]) -> [GolfAPIClub] {
        guard purpose == .handicap else { return values }
        return values.compactMap { club in
            let courses = club.courses.filter { !DevelopmentAPIConfiguration.isDemoCourse($0.courseID) }
            guard !courses.isEmpty else { return nil }
            return GolfAPIClub(clubID: club.clubID, clubName: club.clubName, city: club.city,
                state: club.state, country: club.country, courses: courses)
        }
    }

    func selectCountry(_ country: String) {
        selectedCountry = country
        clearSearchResults()
    }

    private func clearSearchResults() {
        clubs = []
        selectedClubID = nil
        selectedCourseID = nil
        courseDetail = nil
        selectedTeeID = nil
        currentPage = 0
        totalClubCount = 0
        hasMoreClubs = false
        activeDatasetVersion = nil
        errorMessage = nil
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
        clearSearchResults()
    }

    func selectCourse(_ course: GolfAPICourseSummary) async {
        guard !isLoadingCourse else { return }
        // A rejected selection must not leave the previous course/tee active.
        selectedCourseID = course.courseID
        courseDetail = nil
        selectedTeeID = nil
        errorMessage = nil
        guard purpose != .handicap || !DevelopmentAPIConfiguration.isDemoCourse(course.courseID) else {
            errorMessage = "This course cannot be used for Handicap. Choose a rated course or an explicitly custom course."
            return
        }
        guard purpose != .map || course.hasGPS else {
            errorMessage = "\(course.courseName): GPS data not available. GolfAPI lists this course without map coordinates, so it cannot be explored. No download was requested."
            return
        }
        isLoadingCourse = true
        defer { isLoadingCourse = false }
        do {
            let details: GolfAPICourseDetail
            if purpose == .map {
                // A map selection downloads both ratings and GPS geometry now,
                // not later when opening the map. Search alone downloads neither.
                details = try await client.loadCourse(id: course.courseID).detail
            } else {
                // Handicap selection needs ratings only, never paid GPS data.
                details = try await client.loadCourseDetail(id: course.courseID)
            }
            guard selectedCourseID == course.courseID, !Task.isCancelled else { return }
            courseDetail = details
            apiRequestsLeft = nil
            if selectableTees.isEmpty {
                errorMessage = purpose == .handicap
                    ? "No eligible \(selectedSex == "female" ? "Women" : "Men") tees with valid ratings and complete hole pars. Use Custom course or an official differential."
                    : "Course data was downloaded, but the provider returned no tee sets. A tee is needed to open this course."
            } else {
                // Map keeps its default; Handicap requires explicit tee confirmation.
                selectedTeeID = purpose == .map ? (ratedTees.first ?? selectableTees.first)?.teeID : nil
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
