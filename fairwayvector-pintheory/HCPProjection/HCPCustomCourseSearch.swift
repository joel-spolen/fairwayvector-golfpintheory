import Foundation
import SwiftData

/// Local HCP records only; never merges identity with provider clubs by display name.
@MainActor
enum HCPCustomCourseSearch {
    struct Match: Identifiable {
        let club: GolfClub
        let courseNames: [String]
        var id: PersistentIdentifier { club.persistentModelID }
    }

    static func normalizedCountry(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func availableTees(_ tees: [TeeSet], club: GolfClub, courseName: String, sex: PlayerSex) -> [TeeSet] {
        // Existing local schema links these records by name; selectable rows retain persistent IDs.
        tees.filter { $0.clubName == club.name && $0.courseName == courseName && $0.isAvailable(for: sex) }
    }

    static func matches(clubs: [GolfClub], courses: [GolfCourse], tees: [TeeSet],
                        query: String, country: String, region: String, sex: PlayerSex) -> [Match] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = normalizedCountry(country)
        guard !query.isEmpty, !country.isEmpty,
              let coverage = GolfAPICoverage.regions.first(where: { $0.name == region }),
              coverage.countries.contains(where: { normalizedCountry($0) == country }) else { return [] }
        // GolfClub has country/city, not a state or region. Region is country membership only.
        // Adding multiple custom courses can create repeated GolfClub rows with the same
        // name and country, so group them before presenting search results.
        let clubsInCountry = clubs.filter { normalizedCountry($0.country) == country }
        let groups = Dictionary(grouping: clubsInCountry) {
            "\(normalizedCountry($0.name))|\(normalizedCountry($0.country))"
        }

        return groups.values.compactMap { clubGroup -> Match? in
            guard let club = clubGroup.first else { return nil }
            let names = Array(Set(courses.filter { $0.clubName == club.name }.map(\.name)
                + tees.filter { $0.clubName == club.name && $0.isAvailable(for: sex) }.map(\.courseName))).sorted()
            guard club.name.localizedCaseInsensitiveContains(query)
                    || names.contains(where: { $0.localizedCaseInsensitiveContains(query) }) else { return nil }
            return Match(club: club, courseNames: names)
        }.sorted { $0.club.name.localizedStandardCompare($1.club.name) == .orderedAscending }
    }
}