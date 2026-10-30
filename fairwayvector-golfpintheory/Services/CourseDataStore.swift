import Foundation
import CryptoKit

nonisolated enum AccountCourseStorage {
    private static let directoryKey = "providerCourseStorage.accountDirectory.v1"

    static var accountDirectory: URL? {
        guard let value = UserDefaults.standard.string(forKey: directoryKey), !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    static func configure(accountDirectory: URL?) {
        if let accountDirectory {
            UserDefaults.standard.set(accountDirectory.path, forKey: directoryKey)
        } else {
            UserDefaults.standard.removeObject(forKey: directoryKey)
        }
    }
}

/// Durable shared directory, keyed by provider course identity, NEVER by tee/name.
nonisolated enum CourseDataStore {
    static var root: URL {
        if let accountDirectory = AccountCourseStorage.accountDirectory {
            return accountDirectory.appendingPathComponent("CourseData", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CourseData", isDirectory: true)
    }
    static func directory(courseID: String, root: URL = root) -> URL {
        let digest = SHA256.hash(data: Data(courseID.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(digest, isDirectory: true)
    }

    /// Keep a five-course rolling local cache for the active account. Only live
    /// selected-course data calls this; catalog search summaries are never saved.
    @MainActor static func retainRecentCourse(id: String, maximum: Int = 5) -> [String] {
        guard AccountCourseStorage.accountDirectory != nil, !id.isEmpty, maximum > 0 else { return [] }
        let file = root.appendingPathComponent("saved-provider-courses-v1.json")
        var dates = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        dates[id] = .now
        let removed = dates.sorted { $0.value < $1.value }
            .prefix(max(0, dates.count - maximum)).map(\.key)
        removed.forEach { dates.removeValue(forKey: $0) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(dates).write(to: file, options: .atomic)
        } catch { return [] }
        return removed
    }

    static func removeCourseData(id: String) {
        guard !id.isEmpty else { return }
        let folder = directory(courseID: "golfapi:\(id)")
        try? FileManager.default.removeItem(at: folder)
    }

    static func clearLegacyUnscopedProviderCourses() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacyRoot = support.appendingPathComponent("CourseData", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: legacyRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                let hasProviderGeometry = (try? FileManager.default.contentsOfDirectory(atPath: entry.path))?
                    .contains { $0.hasSuffix("-golfapi-v1.json") } ?? false
                if hasProviderGeometry { try? FileManager.default.removeItem(at: entry) }
            } else if entry.lastPathComponent.hasPrefix("course-")
                && entry.lastPathComponent.hasSuffix("-golfapi-v1.json") {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    static func savedProviderCourseIDs() -> Set<String> {
        guard AccountCourseStorage.accountDirectory != nil else { return [] }
        let file = root.appendingPathComponent("saved-provider-courses-v1.json")
        guard let data = try? Data(contentsOf: file),
              let dates = try? JSONDecoder().decode([String: Date].self, from: data) else { return [] }
        return Set(dates.keys)
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
            if let id = course.golfAPICourseID {
                for evictedID in retainRecentCourse(id: id, maximum: 5) {
                    GolfAPICache().removeCourse(id: evictedID)
                    removeCourseData(id: evictedID)
                }
            }
            return course
        }
        return nil
    }
}