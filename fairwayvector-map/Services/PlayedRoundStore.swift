import Foundation
import Observation
import SwiftData

@Observable
final class PlayedRoundStore {
    private struct Archive: Codable {
        var version = 1
        var saved: [PlayedRound] = []
        var draft: PlayedRound?
    }
    private(set) var saved: [PlayedRound] = []
    private(set) var active: PlayedRound?
    private(set) var draftNeedsRetry = false
    var errorMessage: String?
    private let url: URL
    private var loadFailed = false

    init(url: URL? = nil) {
        self.url = url ?? URL.applicationSupportDirectory
            .appendingPathComponent("FairwayVectorRounds", isDirectory: true)
            .appendingPathComponent("rounds-v1.json")
        load()
    }

    func load() {
        guard !draftNeedsRetry else {
            errorMessage = "The latest draft is still in memory. Retry saving it before reloading; reloading must not erase unsaved edits."
            return
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
                guard archive.version == 1 else { throw RoundStorageError.invalidArchive }
                guard Set(archive.saved.map(\.id)).count == archive.saved.count,
                      archive.saved.allSatisfy({ $0.isComplete && Self.validStructure($0) }),
                        archive.draft.map({ Self.validStructure($0) }) ?? true else { throw RoundStorageError.invalidArchive }
                                if let draft = archive.draft, archive.saved.contains(where: { $0.id == draft.id }) { throw RoundStorageError.invalidArchive }
                saved = archive.saved.sorted { $0.date > $1.date }; active = archive.draft
            }
            loadFailed = false; errorMessage = nil
        } catch {
            loadFailed = true
            errorMessage = "Round storage could not be read. Existing files are preserved; no overwrite is allowed. Retry loading after restoring storage."
        }
    }

    static func validStructure(_ round: PlayedRound) -> Bool {
        !round.holes.isEmpty && round.holes.count <= 18
        && Set(round.holes.map(\.number)).count == round.holes.count
        && round.holes.allSatisfy { (1...18).contains($0.number) }
        && round.players.filter(\.isOwner).count == 1
        && !round.players.isEmpty && round.players.count <= 8
        && Set(round.players.map(\.id)).count == round.players.count
        && round.players.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ($0.handicapIndex.map { $0.isFinite && (-10...54).contains($0) } ?? true) }
        && (0...100).contains(round.allowance)
        && round.scores.values.allSatisfy(\.isValid)
        && round.holes == round.course.holes.map { PlayedHole(number: $0.number, par: $0.par, strokeIndex: $0.handicapIndex) }
        && round.reference.courseRating.isFinite
        && Set(round.scores.keys).isSubset(of: Set(round.players.flatMap { player in
            round.holes.map { PlayedRound.key(player: player.id, hole: $0.number) }
        }))
        && round.currentHole >= 0 && round.currentHole < round.holes.count
    }

    private func persist(saved: [PlayedRound], draft: PlayedRound?) throws {
        guard !loadFailed else { throw RoundStorageError.invalidArchive }
        let archive = Archive(saved: saved, draft: draft)
        let data = try JSONEncoder().encode(archive)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func start(_ round: PlayedRound) throws {
        guard active == nil, round.players.count <= 4, Self.validStructure(round) else { throw RoundStorageError.activeDraft }
        try persist(saved: saved, draft: round)
        active = round
        draftNeedsRetry = false; errorMessage = nil
    }

    /// Keep the latest draft in memory even if disk fails, so an explicit retry can recover it.
    func updateDraft(_ round: PlayedRound) throws {
        guard active?.id == round.id, Self.validStructure(round) else { throw RoundStorageError.invalidArchive }
        active = round
        do {
            try persist(saved: saved, draft: round)
            draftNeedsRetry = false; errorMessage = nil
        } catch {
            draftNeedsRetry = true
            errorMessage = "Draft storage failed. Latest edits are retained in memory only; retry saving before quitting the app. The prior disk archive is preserved."
            throw error
        }
    }

    func retryDraft() throws {
        try persist(saved: saved, draft: active)
        draftNeedsRetry = false; errorMessage = nil
    }

    func saveActive() throws {
        guard let round = active, round.isComplete else { throw RoundStorageError.incomplete }
        var updated = saved.filter { $0.id != round.id }
        updated.append(round); updated.sort { $0.date > $1.date }
        try persist(saved: updated, draft: nil)
        saved = updated; active = nil
        draftNeedsRetry = false; errorMessage = nil
    }

    func discardDraft() throws {
        try persist(saved: saved, draft: nil)
        active = nil
        draftNeedsRetry = false; errorMessage = nil
    }

    func delete(_ id: UUID) throws {
        let updated = saved.filter { $0.id != id }
        try persist(saved: updated, draft: active)
        saved = updated
        draftNeedsRetry = false; errorMessage = nil
    }
}

enum RoundStorageError: LocalizedError {
    case invalidArchive, activeDraft, incomplete, unavailableHandicap
    var errorDescription: String? {
        switch self {
        case .invalidArchive: "Round data is unavailable or invalid. Existing storage has not been replaced."
        case .activeDraft: "Resume or discard your existing round before starting another."
        case .incomplete: "Record valid strokes for every player on every hole before finishing."
        case .unavailableHandicap: "HCP import needs a completed, genuinely rated 9- or 18-hole round, a Handicap Index, par and all stroke indexes. Demo rounds cannot enter handicap history."
        }
    }
}

enum PlayedRoundHandicapBridge {
    static func isEligible(_ round: PlayedRound) -> Bool {
        guard round.isComplete, let owner = round.owner,
              !DevelopmentAPIConfiguration.isDemoCourse(round.reference.golfAPICourseID ?? "") else { return false }
        return PlayedRoundCalculator.totals(round: round, player: owner).differential != nil
    }

    @discardableResult
    static func add(_ round: PlayedRound, context: ModelContext) throws -> Bool {
        // Check the real shared SwiftData history, not a second flag/file that could drift.
        let sourceID = round.id.uuidString
        let descriptor = FetchDescriptor<GolfRound>(predicate: #Predicate { $0.sourceSavedRoundID == sourceID })
        if try context.fetch(descriptor).first != nil { return false }
        let copy = try makeHandicapRound(round)
        context.insert(copy)
        do { try context.save() } catch { context.delete(copy); throw error }
        return true
    }

    static func makeHandicapRound(_ round: PlayedRound) throws -> GolfRound {
        guard isEligible(round), let owner = round.owner, let tee = round.tee else { throw RoundStorageError.unavailableHandicap }
        let totals = PlayedRoundCalculator.totals(round: round, player: owner)
        let copy = GolfRound(date: round.date, clubName: tee.clubName, courseName: tee.courseName,
            teeName: tee.teeName, holes: tee.holes, inputMode: .holeByHole,
            adjustedGrossScore: totals.adjustedGross,
            stablefordPoints: round.allowance == 100 ? totals.stableford : nil,
            handicapDifferential: totals.differential, par: tee.par, courseRating: tee.courseRating,
            slopeRating: tee.slopeRating, pcc: 0,
            notes: "Copied explicitly from saved scorecard. Total strokes include putts and penalties. PCC 0; local estimate, not an official submission. Index at play: \(owner.handicapIndex ?? 0).",
            holeScoresData: round.holes.compactMap { round.score(player: owner.id, hole: $0.number)?.strokes },
            holeParsData: round.holes.compactMap(\.par), holeHandicapIndicesData: round.holes.compactMap(\.strokeIndex))
        copy.sourceSavedRoundID = round.id.uuidString
        return copy
    }

    static func projectedIndex(_ round: PlayedRound, history: [GolfRound], lowHandicapIndex: Double?) -> Double? {
        guard !history.contains(where: { $0.sourceSavedRoundID == round.id.uuidString }),
              let copy = try? makeHandicapRound(round) else { return nil }
        let existing = WHSCalculator.scoringEntries(from: history, lowHandicapIndex: lowHandicapIndex)
        // Only project from an established calculable record. Preserve chronological
        // exceptional-score adjustments and caps through the shared calculator.
        guard existing.count >= 3, WHSCalculator.handicapIndex(from: existing, lowHandicapIndex: lowHandicapIndex) != nil else { return nil }
        let projected = WHSCalculator.scoringEntries(from: history + [copy], lowHandicapIndex: lowHandicapIndex)
        return WHSCalculator.handicapIndex(from: projected, lowHandicapIndex: lowHandicapIndex)
    }
}