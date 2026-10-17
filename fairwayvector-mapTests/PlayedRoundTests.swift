import Foundation
import SwiftData
import Testing
@testable import fairwayvector_map

/// Offline regression SOURCE. Compile-only validation; do not execute without authorization.
@MainActor
struct PlayedRoundTests {
    private func fixture(count: Int = 18, index: Double? = 18,
                         mode: RoundDetailMode = .detailed, secondPlayer: Bool = false) -> PlayedRound {
        var reference = CourseReference(osmRelationID: 42, name: "Offline rated fixture")
        reference.holeCount = count; reference.totalPar = count * 4
        reference.courseRating = Double(count * 4); reference.slopeRating = 113
        reference.teeName = "Fixture tee"
        let holes = (1...count).map { number in
            Hole(number: number, par: 4, handicapIndex: count == 9 ? number * 2 - 1 : number,
                path: [], green: [])
        }
        let course = Course(osmRelationID: 42, name: reference.courseName, holes: holes, fetchedAt: .now)
        var players = [RoundPlayer(name: "You", isOwner: true, handicapIndex: index)]
        if secondPlayer { players.append(RoundPlayer(name: "Alex", isOwner: false, handicapIndex: nil)) }
        return PlayedRound(reference: reference, course: course,
            holes: holes.map { PlayedHole(number: $0.number, par: $0.par, strokeIndex: $0.handicapIndex) },
            players: players, game: .stableford, detailMode: mode)
    }

    private func complete(_ input: PlayedRound, strokes: Int = 5) -> PlayedRound {
        var round = input
        for player in round.players {
            for hole in round.holes {
                round.setScore(PlayedHoleScore(strokes: strokes), player: player.id, hole: hole.number)
            }
        }
        return round
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("rounds.json")
    }

    @Test func explicitlySavedPartialRoundSurvivesReloadWithoutHCP() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlayedRoundStore(url: url)
        var round = fixture()
        round.setScore(PlayedHoleScore(strokes: 5), player: round.owner!.id, hole: 1)
        try store.start(round)
        #expect(!PlayedRoundHandicapBridge.isEligible(round))
        try store.saveActive(allowIncomplete: true)
        let reloaded = PlayedRoundStore(url: url)
        #expect(reloaded.active == nil)
        #expect(reloaded.saved.count == 1)
        #expect(reloaded.saved.first?.scores.count == 1)
        #expect(reloaded.saved.first?.isComplete == false)
    }

    @Test func scatteredNineScoresOnEighteenHoleLayoutAreNotHCPEligible() {
        var round = fixture()
        for number in stride(from: 1, through: 17, by: 2) {
            round.setScore(PlayedHoleScore(strokes: 4), player: round.owner!.id, hole: number)
        }
        #expect(!PlayedRoundHandicapBridge.isEligible(round))
        #expect(PlayedRoundHandicapBridge.isEligible(complete(fixture(count: 9))))
    }

    @Test func positiveAndPlusAllocationConserveStrokesAndUseCorrectEnds() {
        for handicap in -54...90 {
            let allocated = (1...18).map { PlayedRoundCalculator.strokes(handicap: handicap, rank: $0, holeCount: 18) }
            #expect(allocated.reduce(0, +) == handicap)
        }
        #expect(PlayedRoundCalculator.strokes(handicap: 2, rank: 1, holeCount: 18) == 1)
        #expect(PlayedRoundCalculator.strokes(handicap: 2, rank: 18, holeCount: 18) == 0)
        #expect(PlayedRoundCalculator.strokes(handicap: -2, rank: 1, holeCount: 18) == 0)
        #expect(PlayedRoundCalculator.strokes(handicap: -2, rank: 18, holeCount: 18) == -1)
        let plus = WHSCalculator.calculateHoleByHole(holeScores: Array(repeating: 4, count: 18),
            holePars: Array(repeating: 4, count: 18), holeHandicapIndices: Array(1...18), courseHandicap: -2)
        #expect(plus.holePoints.first == 2)
        #expect(plus.holePoints.last == 1)
    }

    @Test func courseHandicapHalfValuesRoundUpIncludingPlus() {
        let tee = TeeSnapshot(clubName: "", courseName: "", teeName: "", holes: 18,
            par: 72, courseRating: 72, slopeRating: 113)
        #expect(WHSCalculator.courseHandicap(handicapIndex: 1.5, tee: tee) == 2)
        #expect(WHSCalculator.courseHandicap(handicapIndex: -1.5, tee: tee) == -1)
        var nine = tee
        nine.holes = 9; nine.par = 36; nine.courseRating = 36
        #expect(WHSCalculator.courseHandicap(handicapIndex: 18, tee: nine) == 9)
    }

    @Test func grossNetPointsAndWHSAdjustmentAreDistinctAndPenaltiesIncluded() {
        var round = complete(fixture())
        let owner = round.owner!
        round.setScore(PlayedHoleScore(strokes: 10, putts: 2, fairway: .missed, bunkerShots: 1, penalties: 2),
            player: owner.id, hole: 1)
        round.allowance = 50
        let t = PlayedRoundCalculator.totals(round: round, player: owner)
        #expect(t.gross == 95) // not 97: penalties already in 10.
        #expect(t.net == 86) // full CH 18, playing HCP 9.
        #expect(t.adjustedGross == 92) // cap 10 at par4 +2 +1 =7.
        #expect(t.differential == 20)
        #expect(t.courseHandicap == 18)
        #expect(t.playingHandicap == 9)
        #expect(t.penalties == 2)
        #expect(t.stableford == 25) // hole1 zero +8*2 +9*1.
    }

    @Test func nineHoleOddIndexesRankWithinSideAndUseExpectedDifferential() {
        let round = complete(fixture(count: 9))
        let t = PlayedRoundCalculator.totals(round: round, player: round.owner!)
        #expect(round.strokeRanks?[9] == 9)
        #expect(t.courseHandicap == 9)
        #expect(t.net == 36)
        #expect(t.stableford == 18)
        #expect(t.differential == 19.6)
        #expect(PlayedRoundHandicapBridge.isEligible(round))
        let existing = WHSCalculator.calculateHoleByHole(holeScores: Array(repeating: 5, count: 9),
            holePars: Array(repeating: 4, count: 9), holeHandicapIndices: stride(from: 1, through: 17, by: 2).map { $0 },
            courseHandicap: 9)
        #expect(existing.totalStablefordPoints == 18)
    }

    @Test func whsExpectedNineHoleDifferentialMatchesPublishedValues() {
        #expect(WHSCalculator.expectedNineHoleScoreDifferential(handicapIndex: -6.0) == -1.9)
        #expect(WHSCalculator.expectedNineHoleScoreDifferential(handicapIndex: 14.0) == 8.5)
        #expect(WHSCalculator.expectedNineHoleScoreDifferential(handicapIndex: 54.0) == 29.3)
        #expect(WHSCalculator.nineHoleScoreDifferential(adjustedGrossScore: 41,
            courseRating: 36.5, slopeRating: 113, handicapIndex: 14.0) == 13.0)
        #expect(WHSCalculator.expectedNineHoleScoreDifferential(handicapIndex: 55.0) == nil)
    }

    @Test func missingAndDuplicateStrokeIndexesAndRatingsDoNotProduceNetOrHCP() {
        var round = complete(fixture())
        round.holes[0].strokeIndex = nil
        #expect(PlayedRoundCalculator.totals(round: round, player: round.owner!).net == nil)
        round = complete(fixture())
        round.holes[0].strokeIndex = round.holes[1].strokeIndex
        #expect(round.strokeRanks == nil)
        #expect(!PlayedRoundHandicapBridge.isEligible(round))
        round = complete(fixture())
        round.reference.courseRating = 0
        #expect(PlayedRoundCalculator.totals(round: round, player: round.owner!).differential == nil)
        round = complete(fixture(index: nil))
        #expect(PlayedRoundCalculator.totals(round: round, player: round.owner!).gross == 90)
        #expect(PlayedRoundCalculator.totals(round: round, player: round.owner!).stableford == nil)
    }

    @Test func nullableDetailsAndDenominatorsExcludeUnknownParThreeAndOtherPlayers() {
        var round = complete(fixture(secondPlayer: true))
        let owner = round.owner!
        round.holes[0].par = 3
        round.course.holes[0].par = 3
        round.reference.totalPar -= 1; round.reference.courseRating -= 1
        round.setScore(PlayedHoleScore(strokes: 3, putts: 2, fairway: .hit, bunkerShots: 0, penalties: 0), player: owner.id, hole: 1)
        round.setScore(PlayedHoleScore(strokes: 5, putts: 2, fairway: .hit, bunkerShots: 1, penalties: 2), player: owner.id, hole: 2)
        let other = round.players[1]
        round.setScore(PlayedHoleScore(strokes: 20, putts: 10, fairway: .missed, bunkerShots: 5, penalties: 5), player: other.id, hole: 2)
        let s = RoundStatistics(rounds: [round])
        #expect(s.rounds == 1 && s.holes == 18)
        #expect(s.gross == 88)
        #expect(s.putts == 4 && s.puttHoles == 2)
        #expect(s.fairwaysHit == 1 && s.fairwaysAnswered == 1)
        #expect(s.gir == 1 && s.girHoles == 2)
        #expect(s.bunkerHoles == 1 && s.bunkerAnswered == 2)
        #expect(s.penalties == 2 && s.penaltyHoles == 2)
        #expect(RoundStatistics.rate(s.penalties, s.penaltyHoles, scale: 18) == 18)
        let strokesOnly = RoundStatistics(rounds: [complete(fixture(mode: .strokesOnly))])
        #expect(strokesOnly.puttHoles == 0 && strokesOnly.girHoles == 0)
        #expect(RoundStatistics.rate(strokesOnly.putts, strokesOnly.puttHoles) == nil)
    }

    @Test func validationRequiresEveryPlayerEveryHoleAndIndependentBoundedScores() {
        var round = fixture(secondPlayer: true)
        let owner = round.owner!
        round.setScore(PlayedHoleScore(strokes: 5), player: owner.id, hole: 18)
        #expect(!round.isComplete)
        #expect(round.score(player: owner.id, hole: 1) == nil)
        #expect(!PlayedHoleScore(strokes: 0).isValid)
        #expect(!PlayedHoleScore(strokes: 31).isValid)
        #expect(!PlayedHoleScore(strokes: 4, putts: 5).isValid)
        #expect(!PlayedHoleScore(strokes: 4, putts: 3, penalties: 2).isValid)
        round = complete(round)
        #expect(round.isComplete)
    }

    @Test func durableDraftResumeExplicitSaveAndDeletePreserveRoundIdentity() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlayedRoundStore(url: url)
        let round = fixture(secondPlayer: true)
        try store.start(round)
        #expect(store.saved.isEmpty)
        let resumed = PlayedRoundStore(url: url)
        #expect(resumed.active?.id == round.id)
        #expect(resumed.active?.reference == round.reference)
        #expect(resumed.active?.players.count == 2)
        #expect(resumed.saved.isEmpty)
        var finished = complete(round)
        finished.currentHole = 17
        try resumed.updateDraft(finished)
        try resumed.saveActive()
        let reopened = PlayedRoundStore(url: url)
        #expect(reopened.active == nil && reopened.saved.count == 1)
        #expect(reopened.saved.first?.id == round.id)
        #expect(reopened.saved.first?.currentHole == 17)
        try reopened.delete(round.id)
        #expect(PlayedRoundStore(url: url).saved.isEmpty)
    }

    @Test func corruptArchiveIsNotOverwrittenAndStartFailureIsExplicit() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data("not a round archive".utf8)
        try bytes.write(to: url)
        let store = PlayedRoundStore(url: url)
        #expect(store.errorMessage != nil)
        #expect(throws: (any Error).self) { try store.start(fixture()) }
        #expect(store.active == nil && store.saved.isEmpty)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func failedDraftWriteRetainsLatestMemoryForRetryWithoutPromotingToSaved() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlayedRoundStore(url: url)
        let round = fixture()
        try store.start(round)
        // Replace ONLY the fixture archive with a directory to force atomic-write failure.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let updated = complete(round)
        #expect(throws: (any Error).self) { try store.updateDraft(updated) }
        #expect(store.active?.isComplete == true && store.saved.isEmpty)
        #expect(store.draftNeedsRetry)
        store.load()
        #expect(store.active?.isComplete == true)
        try FileManager.default.removeItem(at: url)
        try store.retryDraft()
        #expect(!store.draftNeedsRetry)
        #expect(PlayedRoundStore(url: url).active?.isComplete == true)
    }

    @Test func HCPImportUsesSharedHistoryOwnerOnlyAndSurvivesDuplicateAndStatsDeletion() throws {
        let container = try ModelContainer(for: GolfRound.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let round = complete(fixture(secondPlayer: true))
        #expect(try PlayedRoundHandicapBridge.add(round, context: context))
        #expect(try !PlayedRoundHandicapBridge.add(round, context: context))
        let history = try context.fetch(FetchDescriptor<GolfRound>())
        #expect(history.count == 1)
        #expect(history.first?.sourceSavedRoundID == round.id.uuidString)
        #expect(history.first?.holeScoresData == Array(repeating: 5, count: 18))
        #expect(history.first?.handicapDifferential == 18)
        #expect(history.first?.adjustedGrossScore == 90)
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlayedRoundStore(url: url)
        try store.start(round); try store.saveActive(); try store.delete(round.id)
        #expect(try context.fetchCount(FetchDescriptor<GolfRound>()) == 1)
        var demo = round
        demo.reference.golfAPICourseID = "mock-hills-v1"
        #expect(!PlayedRoundHandicapBridge.isEligible(demo))
    }

    @Test func projectionRequiresEstablishedSharedHistoryAndNeverRepeatsImportedRound() throws {
        let round = complete(fixture())
        #expect(PlayedRoundHandicapBridge.projectedIndex(round, history: [], lowHandicapIndex: nil) == nil)
        let history = (1...3).map { offset in
            GolfRound(date: Date.now.addingTimeInterval(Double(-offset) * 86_400),
                clubName: "", courseName: "", teeName: "", holes: 18, inputMode: .adjustedGrossScore,
                handicapDifferential: 20, par: 72, courseRating: 72, slopeRating: 113)
        }
        #expect(PlayedRoundHandicapBridge.projectedIndex(round, history: history, lowHandicapIndex: nil) != nil)
        let imported = try PlayedRoundHandicapBridge.makeHandicapRound(round)
        #expect(PlayedRoundHandicapBridge.projectedIndex(round, history: history + [imported], lowHandicapIndex: nil) == nil)
    }
}