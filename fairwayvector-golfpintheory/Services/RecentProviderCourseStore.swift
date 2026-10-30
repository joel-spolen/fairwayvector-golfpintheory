import Foundation

/// Account-scoped five-course history shared by HCP, Explore and Play pickers.
/// Identity is the GolfAPI course ID; selecting another tee moves that course to front.
enum RecentProviderCourseStore {
    static let key = "provider.recentCourses.v1"
    static let maximumCount = 5

    static func decode(_ data: Data) -> [CourseReference] {
        guard let values = try? JSONDecoder().decode([CourseReference].self, from: data) else { return [] }
        var seen = Set<String>()
        return values.filter { reference in
            guard let id = reference.golfAPICourseID, !id.isEmpty else { return false }
            return seen.insert(id).inserted
        }.prefix(maximumCount).map { $0 }
    }

    static func recording(_ reference: CourseReference, in data: Data) -> Data {
        guard let id = reference.golfAPICourseID, !id.isEmpty else { return data }
        var values = decode(data).filter { $0.golfAPICourseID != id }
        values.insert(reference, at: 0)
        return (try? JSONEncoder().encode(Array(values.prefix(maximumCount)))) ?? data
    }

    static func merging(_ references: [CourseReference], into data: Data) -> Data {
        references.reversed().reduce(data) { recording($1, in: $0) }
    }
}
