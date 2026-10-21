import Foundation
import CryptoKit

/// Durable shared directory, keyed by provider course identity, NEVER by tee/name.
nonisolated enum CourseDataStore {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CourseData", isDirectory: true)
    }
    static func directory(courseID: String, root: URL = root) -> URL {
        let digest = SHA256.hash(data: Data(courseID.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(digest, isDirectory: true)
    }

    /// Exact tee-specific geometry, read-only even for flat pre-CourseData caches.
    @MainActor static func readCourse(reference: CourseReference, applicationSupport: URL? = nil) -> Course? {
        let support = applicationSupport ?? root.deletingLastPathComponent()
        let identity = reference.golfAPICourseID.map { "golfapi:\($0)" }
            ?? reference.osmRelationID.map { "osm:\($0)" }
        let version = reference.golfAPICourseID == nil ? "v5" : "golfapi-v1"
        let filename = "course-\(reference.cacheKey)-\(version).json"
        var urls: [URL] = []
        if let identity {
            urls.append(directory(courseID: identity, root: support.appendingPathComponent("CourseData"))
                .appendingPathComponent(filename))
        }
        urls.append(support.appendingPathComponent(filename))
        for url in urls {
            guard let data = try? Data(contentsOf: url), let course = try? JSONDecoder().decode(Course.self, from: data),
                  course.golfAPICourseID == reference.golfAPICourseID,
                  reference.golfAPICourseID != nil || course.osmRelationID == reference.osmRelationID,
                  !course.holes.isEmpty, course.holes.allSatisfy({ !$0.path.isEmpty && $0.path.allSatisfy(TerrainGeometry.valid) }) else { continue }
            return course
        }
        return nil
    }
}