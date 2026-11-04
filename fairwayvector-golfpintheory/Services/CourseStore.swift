import Foundation
import Observation

@Observable
final class CourseStore {
    let reference: CourseReference
    private(set) var course: Course?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var terrain: CourseTerrain?
    private(set) var terrainMessage: String?
    private(set) var isLoadingTerrain = false

    private let client: OverpassClient
    private let golfAPIClient: GolfAPIClient
    private let terrainMode: DevelopmentAPIConfiguration.Mode
    private let maxCacheAge: TimeInterval = 24 * 60 * 60
    private var resolvedRelationID: Int?
    private var bundledTerrain: CourseTerrainManifest?
    private var greenOutlinesRequested = false

    init(
        reference: CourseReference,
        client: OverpassClient = OverpassClient(),
        golfAPIClient: GolfAPIClient = .shared,
        initialCourse: Course? = nil,
        terrainMode: DevelopmentAPIConfiguration.Mode = DevelopmentAPIConfiguration.current.gpxz
    ) {
        self.reference = reference
        self.client = client
        self.golfAPIClient = golfAPIClient
        self.course = initialCourse
        self.terrainMode = terrainMode
    }

    func load() async {
        if course == nil {
            course = readCache()
        }
        if golfAPIClient.mode == .mock {
            if course == nil { await refresh() }
        } else if !(reference.golfAPICourseID != nil && course != nil),
                  !(course.map { Date.now.timeIntervalSince($0.fetchedAt) < maxCacheAge } ?? false) {
            await refresh()
        }
        preloadGreenOutlines()
        await loadTerrain()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if golfAPIClient.mode == .mock {
                if let saved = readCache() { course = saved; return }
                if reference.golfAPICourseID == nil {
                    throw GolfAPIError.savedCourseUnavailable(reference.courseName)
                }
            }
            if let courseID = reference.golfAPICourseID {
                let payload: GolfAPICoursePayload
                if course == nil, golfAPIClient.mode == .live, golfAPIClient.cachedPayload(id: courseID) == nil {
                    let bundle = try await golfAPIClient.loadCourseBundle(id: courseID)
                    payload = bundle.payload
                    bundledTerrain = bundle.terrain
                } else {
                    payload = try await (course == nil
                        ? golfAPIClient.loadCourse(id: courseID)
                        : golfAPIClient.refreshCourse(id: courseID))
                }
                var built = try GolfAPICourseBuilder.build(reference: reference, payload: payload)
                if let previous = course {
                    for index in built.holes.indices {
                        built.holes[index].greenOutline = previous.holes
                            .first { $0.number == built.holes[index].number }?.greenOutline ?? []
                    }
                    built.greenOutlinesCheckedAt = previous.greenOutlinesCheckedAt
                }
                course = built
                writeCache(built)
                return
            }

            let relationID: Int
            if let cachedID = course?.osmRelationID {
                relationID = cachedID
            } else if let knownID = reference.osmRelationID {
                relationID = knownID
            } else if let resolvedRelationID {
                relationID = resolvedRelationID
            } else {
                relationID = try await client.findCourseRelationID(for: reference)
                resolvedRelationID = relationID
            }
            let elements = try await client.fetchGolfFeatures(courseRelationID: relationID)
            let built = try CourseBuilder.build(reference: reference, elements: elements, osmRelationID: relationID)
            course = built
            writeCache(built)
        } catch {
            errorMessage = UserFacingError.message(error)
        }
    }

    private var cacheURL: URL? {
        guard let id = terrainCourseID else { return legacyCacheURL }
        let version = reference.golfAPICourseID == nil ? "v5" : "golfapi-v1"
        return CourseDataStore.directory(courseID: id).appendingPathComponent("course-\(reference.cacheKey)-\(version).json")
    }

    var terrainCourseID: String? {
        if let id = reference.golfAPICourseID { return "golfapi:\(id)" }
        if let id = course?.osmRelationID ?? reference.osmRelationID ?? resolvedRelationID { return "osm:\(id)" }
        return nil
    }

    private var legacyCacheURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let version = reference.golfAPICourseID == nil ? "v5" : "golfapi-v1"
        return dir.appending(path: "course-\(reference.cacheKey)-\(version).json")
    }

    private func readCache() -> Course? {
        guard let saved = CourseDataStore.readCourse(reference: reference)
            ?? (golfAPIClient.mode == .mock ? golfAPIClient.bundledCourse(reference: reference) : nil) else { return nil }
        resolvedRelationID = saved.osmRelationID
        writeCache(saved) // Migration is permitted ONLY in live mode; paused reads are read-only.
        return saved
    }

    private func writeCache(_ course: Course) {
        // Demo geometry is inexpensive to reconstruct and must never migrate/write live caches.
        guard golfAPIClient.mode == .live else { return }
        guard let url = cacheURL, let data = try? JSONEncoder().encode(course) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Point-only courses borrow OpenStreetMap green outlines so the slope heatmap follows the real green.
    /// The data service fetches and caches them per course; the app never calls the public map servers.
    /// Runs in the background so a slow map server never delays opening the course.
    func preloadGreenOutlines() {
        Task { await loadGreenOutlines() }
    }

    private func loadGreenOutlines() async {
        guard !greenOutlinesRequested, golfAPIClient.mode == .live, let courseID = reference.golfAPICourseID,
              var current = course,
              current.holes.contains(where: { $0.green.count < 3 && $0.greenOutline.isEmpty }) else { return }
        greenOutlinesRequested = true
        // A round keeps the course as it was when it started; the saved course may have outlines since.
        if let saved = CourseDataStore.readCourse(reference: reference), saved.greenOutlinesCheckedAt != nil {
            for index in current.holes.indices where current.holes[index].greenOutline.isEmpty {
                current.holes[index].greenOutline = saved.holes
                    .first { $0.number == current.holes[index].number }?.greenOutline ?? []
            }
            current.greenOutlinesCheckedAt = saved.greenOutlinesCheckedAt
            course = current
        }
        // Saved with the course once received and never fetched again, so the heatmap works offline.
        guard current.greenOutlinesCheckedAt == nil else { return }
        // The first course download starts the fetch on the server; poll while it talks to the map servers.
        var outlines: [[GeoPoint]]?
        for attempt in 0..<10 where outlines == nil {
            if attempt > 0 { try? await Task.sleep(for: .seconds(15)) }
            outlines = try? await golfAPIClient.loadGreenOutlines(id: courseID)
        }
        guard let outlines, var updated = course else { return }
        for index in updated.holes.indices where updated.holes[index].green.count < 3 {
            if let outline = GreenSlopeMap.outline(for: updated.holes[index], among: outlines) {
                updated.holes[index].greenOutline = outline
            }
        }
        updated.greenOutlinesCheckedAt = .now
        course = updated
        writeCache(updated)
    }

    /// Saved elevation first; otherwise the course bundle's manifest and its tiles.
    /// Never blocks the course: failures leave `terrain` nil with a message.
    func loadTerrain() async {
        guard course != nil, terrain == nil else { return }
        if terrainMode == .mock {
            terrain = CourseTerrain(source: .synthetic)
            terrainMessage = nil
            return
        }
        guard let courseID = reference.golfAPICourseID, golfAPIClient.mode == .live,
              let identity = terrainCourseID else {
            terrainMessage = L("Elevation isn't available for this course.")
            return
        }
        let directory = CourseDataStore.directory(courseID: identity)
        CourseTerrainStore.removeLegacyFiles(directory: directory, accountRoot: CourseDataStore.root)
        if let saved = CourseTerrainStore.read(directory: directory) {
            terrain = saved
            terrainMessage = nil
            return
        }
        isLoadingTerrain = true
        defer { isLoadingTerrain = false }
        do {
            let manifest: CourseTerrainManifest
            if let bundledTerrain {
                manifest = bundledTerrain
            } else {
                manifest = try await golfAPIClient.loadCourseBundle(id: courseID).terrain
            }
            bundledTerrain = nil
            terrain = try await CourseTerrainStore.download(manifest, directory: directory) { tile in
                try await self.golfAPIClient.downloadTerrainTile(id: tile.id, source: tile.source)
            }
            terrainMessage = manifest.isReady ? nil
                : L("Course elevation couldn't be downloaded right now. It will be tried again the next time you open the course.")
        } catch CourseTerrainError.unavailable(let temporary) {
            terrainMessage = temporary
                ? L("Course elevation couldn't be downloaded right now. It will be tried again the next time you open the course.")
                : L("Elevation isn't available for this course.")
        } catch {
            terrainMessage = L("Course elevation couldn't be downloaded right now. It will be tried again the next time you open the course.")
        }
    }
}
