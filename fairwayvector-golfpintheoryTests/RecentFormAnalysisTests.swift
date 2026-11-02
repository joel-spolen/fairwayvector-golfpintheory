import Foundation
import Testing
@testable import fairwayvector_golfpintheory

@MainActor
struct RecentFormAnalysisTests {
    private func round(_ day: Int, putts: Int? = nil, greens: Int? = nil, fairways: Int? = nil,
                       penalties: Int? = nil, scrambles: [Bool] = [], holes: Int = 18) -> RoundPerformanceRecord {
        var record = RoundPerformanceRecord(id: "round-\(day)", date: Date(timeIntervalSince1970: Double(day) * 86_400),
            title: "Course", holes: holes, gross: nil, adjustedGross: nil, differential: nil, played: nil, handicap: nil)
        if let putts { record.putts = putts; record.puttHoles = holes }
        if let greens { record.greens = greens; record.greenHoles = holes }
        if let fairways { record.fairways = fairways; record.fairwayHoles = 14 }
        if let penalties { record.penalties = penalties; record.penaltyHoles = holes }
        // Missed green (strokes − putts > par − 2); par saved only when strokes ≤ par.
        record.holeDetails = scrambles.map {
            HolePerformanceSample(par: 4, score: PlayedHoleScore(strokes: $0 ? 4 : 5, putts: 1))
        }
        return record
    }

    @Test func fewerThanEightRoundsAsksForMoreRounds() {
        let rounds = (1...7).map { round($0, putts: 36) }
        #expect(RecentFormAnalysis.analyze(rounds) == .notEnoughData(roundsNeeded: 1))
        #expect(RecentFormAnalysis.analyze([]) == .notEnoughData(roundsNeeded: 8))
    }

    @Test func roundsWithoutDetailsDoNotCount() {
        let handicapOnly = (1...10).map { round($0) }
        #expect(RecentFormAnalysis.analyze(handicapOnly) == .notEnoughData(roundsNeeded: 8))
    }

    @Test func morePuttsIsADecline() throws {
        let rounds = (1...3).map { round($0, putts: 36) } + (4...8).map { round($0, putts: 40) }
        guard case .changes(let workOn, let goingWell) = RecentFormAnalysis.analyze(rounds) else {
            Issue.record("Expected a change"); return
        }
        let change = try #require(workOn)
        #expect(change.area == .putting)
        #expect(abs(change.recent - 40.0 / 18) < 1e-9)
        #expect(abs(change.earlier - 2.0) < 1e-9)
        #expect(goingWell == nil)
    }

    @Test func picksTheLargestDeclineAndImprovement() {
        let earlier = (1...3).map { round($0, greens: 6, fairways: 5, penalties: 1) }
        // GIR 33% → 28% (−1 step), fairways 36% → 64% (+5.7 steps), penalties 1 → 3 per 18 (−4 steps).
        let recent = (4...8).map { round($0, greens: 5, fairways: 9, penalties: 3) }
        guard case .changes(let workOn, let goingWell) = RecentFormAnalysis.analyze(earlier + recent) else {
            Issue.record("Expected changes"); return
        }
        #expect(workOn?.area == .penalties)
        #expect(goingWell?.area == .driving)
    }

    @Test func smallChangesAreSteady() {
        let rounds = (1...3).map { round($0, putts: 36) } + (4...8).map { round($0, putts: 37) }
        #expect(RecentFormAnalysis.analyze(rounds) == .steady)
    }

    @Test func eachAreaUsesItsOwnLastFiveRounds() throws {
        let withPutts = (1...3).map { round($0, putts: 36) } + (4...8).map { round($0, putts: 40) }
        let withoutPutts = (9...10).map { round($0, fairways: 7) }
        guard case .changes(let workOn, _) = RecentFormAnalysis.analyze(withPutts + withoutPutts) else {
            Issue.record("Expected a change"); return
        }
        let change = try #require(workOn)
        #expect(change.area == .putting)
        #expect(abs(change.recent - 40.0 / 18) < 1e-9)
    }

    @Test func scramblingComesFromMissedGreens() {
        let earlier = (1...3).map { round($0, scrambles: [true, true, false, false]) }
        let recent = (4...8).map { round($0, scrambles: [false, false, false, true]) }
        guard case .changes(let workOn, _) = RecentFormAnalysis.analyze(earlier + recent) else {
            Issue.record("Expected a change"); return
        }
        #expect(workOn?.area == .shortGame)
        #expect(workOn?.recent == 25)
        #expect(workOn?.earlier == 50)
    }
}
