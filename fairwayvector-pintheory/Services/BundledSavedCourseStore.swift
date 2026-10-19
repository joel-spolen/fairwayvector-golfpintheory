import Foundation

/// Reviewed public course data only. Never installs, migrates or writes provider/live caches.
struct BundledSavedCourseStore {
    static let hillsCourseID = "0121161534832877"
    private let bundle: Bundle

    init(bundle: Bundle = .main) { self.bundle = bundle }

    private func data(_ name: String) -> Data? {
        // Xcode synchronized resources may be flattened; also support preserved folders.
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Resources/SavedCourses/Hills")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "SavedCourses/Hills")
            ?? bundle.url(forResource: name, withExtension: "json")
        return url.flatMap { try? Data(contentsOf: $0) }
    }

    func detail(id: String) -> Data? {
        guard id == Self.hillsCourseID else { return nil }
        return data("course-\(id)-detail")
    }

    func coordinates(id: String) -> Data? {
        guard id == Self.hillsCourseID else { return nil }
        return data("course-\(id)-coordinates")
    }

    var clubData: Data? { data("hills-club") }

    func course(reference: CourseReference) -> Course? {
        // Exported geometry belongs to EXACTLY this provider tee/sex, not every tee.
        guard reference.golfAPICourseID == Self.hillsCourseID,
              reference.golfAPITeeID == "185072", reference.teeName == "62", reference.teeSex == "male",
              let bytes = data("course-0121161534832877-hills-golf---sports-club-hills-62-male-golfapi-v1"),
              let course = try? JSONDecoder().decode(Course.self, from: bytes),
              course.golfAPICourseID == Self.hillsCourseID, course.holes.count == 18,
              Set(course.holes.map(\.number)) == Set(1...18),
              course.holes.allSatisfy({ $0.path.count >= 2 && $0.path.allSatisfy(TerrainGeometry.valid) }) else { return nil }
        return course
    }
}