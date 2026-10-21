import Foundation
import SwiftData
import Testing
@testable import fairwayvector_golfpintheory

/// Offline regression source: local models only, no provider construction or transport.
@MainActor
struct HCPCustomCourseSearchTests {
    private func matches(_ clubs: [GolfClub], courses: [GolfCourse] = [], tees: [TeeSet] = [],
                         query: String = "Hills", country: String = "Sweden", region: String = "Europe",
                         sex: PlayerSex = .male) -> [HCPCustomCourseSearch.Match] {
        HCPCustomCourseSearch.matches(clubs: clubs, courses: courses, tees: tees,
            query: query, country: country, region: region, sex: sex)
    }

    @Test func exactNormalizedCountryAndRegionMembership() {
        let sweden = GolfClub(name: "Hills", city: "Mölndal", country: "  sWeDeN \n", isCustom: true)
        let usa = GolfClub(name: "Hills", city: "Sweden", country: "USA", isCustom: true)
        let partial = GolfClub(name: "Hills", city: "", country: "Sweden Islands", isCustom: true)
        let clubs = [sweden, usa, partial]
        #expect(matches(clubs).map(\.id) == [sweden.persistentModelID])
        #expect(matches(clubs, country: " SWEDEN ").map(\.id) == [sweden.persistentModelID])
        #expect(matches(clubs, country: "Swed").isEmpty)
        #expect(matches(clubs, region: "North America").isEmpty)
        #expect(matches(clubs, region: "Unknown").isEmpty)
        #expect(matches(clubs, country: "USA", region: "USA + Canada").map(\.id) == [usa.persistentModelID])
        #expect(matches(clubs, country: "USA", region: "North America").map(\.id) == [usa.persistentModelID])
    }

    @Test func typedQueryMatchesClubOrCourseNotCityAndBlankShowsNothing() {
        let club = GolfClub(name: "North Golf", city: "Hills", country: "Sweden", isCustom: true)
        let course = GolfCourse(clubName: club.name, name: "South Course", isCustom: true)
        #expect(matches([club], courses: [course], query: "  nOrTh  ").count == 1)
        #expect(matches([club], courses: [course], query: " south ").count == 1)
        #expect(matches([club], courses: [course], query: "Hills").isEmpty)
        #expect(matches([club], courses: [course], query: " \n ").isEmpty)
        #expect(matches([club], courses: [course], country: "").isEmpty)
        // @Query replacement after custom creation is sufficient; no search request is needed.
        #expect(matches([], courses: [], query: "North").isEmpty)
        #expect(matches([club], courses: [course], query: "North").count == 1)
    }

    @Test func savedLocalCourseChoicesAndProfileRatingsKeepPersistentTeeIdentity() {
        let club = GolfClub(name: "Hills", city: "", isCustom: true)
        let courses = [GolfCourse(clubName: club.name, name: "North", isCustom: true),
                       GolfCourse(clubName: club.name, name: "South", isCustom: true)]
        let men = TeeSet(clubName: club.name, courseName: "North", name: "Blue", par: 72,
            courseRating: 71.2, slopeRating: 123, ratingSexRawValue: "male", isCustom: true)
        let women = TeeSet(clubName: club.name, courseName: "North", name: "Blue", par: 72,
            courseRating: 75.4, slopeRating: 137, ratingSexRawValue: "female", isCustom: true)
        let universal = TeeSet(clubName: club.name, courseName: "North", name: "Red", par: 72,
            courseRating: 70.1, slopeRating: 119, isCustom: true)
        let orphan = TeeSet(clubName: club.name, courseName: "Legacy", name: "White", par: 72,
            courseRating: 72.0, slopeRating: 113)
        let tees = [men, women, universal, orphan]
        #expect(matches([club], courses: courses, tees: tees).first?.courseNames == ["Legacy", "North", "South"])
        #expect(HCPCustomCourseSearch.availableTees(tees, club: club, courseName: "North", sex: .male)
            .map(\.persistentModelID) == [men.persistentModelID, universal.persistentModelID])
        #expect(HCPCustomCourseSearch.availableTees(tees, club: club, courseName: "North", sex: .female)
            .map(\.persistentModelID) == [women.persistentModelID, universal.persistentModelID])
        #expect(men.persistentModelID != women.persistentModelID)
        let selected = tees.first { $0.persistentModelID == women.persistentModelID }!
        let info = CourseTeeInfo(custom: selected)
        #expect(info.courseRating == 75.4 && info.slopeRating == 137 && info.ratingSex == .female)
    }

    @Test func sameDisplayNamesRemainSeparateLocalRecords() {
        let first = GolfClub(name: "Hills", city: "One", isCustom: true)
        let second = GolfClub(name: "Hills", city: "Two", isCustom: true)
        let found = matches([first, second])
        #expect(found.count == 2)
        #expect(Set(found.map(\.id)).count == 2)
        #expect(Set(found.map(\.id)) == Set([first.persistentModelID, second.persistentModelID]))
    }
}