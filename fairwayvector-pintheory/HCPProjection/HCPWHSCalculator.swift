//
//  WHSCalculator.swift
//  fairwayvector-hcp-projection
//

import Foundation

enum WHSCalculator {
    static func scoreDifferential(adjustedGrossScore: Int, courseRating: Double, slopeRating: Int, pcc: Double = 0) -> Double {
        let raw = (Double(adjustedGrossScore) - courseRating - pcc) * 113 / Double(slopeRating)
        return roundToTenth(raw)
    }

    static func expectedNineHoleScoreDifferential(handicapIndex: Double) -> Double? {
        guard handicapIndex.isFinite, (-10...54).contains(handicapIndex) else { return nil }
        // This reproduces the published WHS expected-differential lookup values
        // to one decimal across the full Handicap Index range.
        return roundToTenth(0.52 * handicapIndex + 1.2)
    }

    static func nineHoleScoreDifferential(
        adjustedGrossScore: Int,
        courseRating: Double,
        slopeRating: Int,
        pcc: Double = 0,
        handicapIndex: Double
    ) -> Double? {
        guard slopeRating > 0,
              let expected = expectedNineHoleScoreDifferential(handicapIndex: handicapIndex) else { return nil }
        let playedNineRaw = (Double(adjustedGrossScore) - courseRating - pcc) * 113 / Double(slopeRating)
        return roundToTenth(playedNineRaw + expected)
    }

    static func stablefordAdjustedGrossScore(points: Int, par: Int, courseHandicap: Int, holes: Int) -> Int {
        let basePoints = holes == 9 ? 18 : 36
        return par + courseHandicap + basePoints - points
    }

    static func courseHandicap(handicapIndex: Double, tee: TeeSnapshot) -> Int {
        let indexContribution = handicapIndex * Double(tee.slopeRating) / 113 * (tee.holes == 9 ? 0.5 : 1)
        let raw = indexContribution + (tee.courseRating - Double(tee.par))
        // WHS rounds half values upward, including negative / plus handicaps.
        return Int(floor(raw + 0.5))
    }

    static func calculateHoleByHole(
        holeScores: [Int],
        holePars: [Int],
        holeHandicapIndices: [Int],
        courseHandicap: Int
    ) -> (totalGrossScore: Int, netDoubleBogeyAdjustedScore: Int, totalStablefordPoints: Int, holePoints: [Int]) {
        let holeCount = min(holeScores.count, min(holePars.count, holeHandicapIndices.count))
        guard holeCount > 0 else { return (0, 0, 0, []) }

        var totalGross = 0
        var adjustedGross = 0
        var totalPoints = 0
        var holePointsList: [Int] = []

        for i in 0..<holeCount {
            let gross = holeScores[i]
            let par = holePars[i]
            let hcpIndex = holeHandicapIndices[i]
            // Rank actual indexes within the played set (nine-hole sides may use
            // odd/even indexes from the full 18). Plus handicaps give back strokes
            // on the easiest / highest-index holes, not the hardest ones.
            let rank = holeHandicapIndices.prefix(holeCount).filter { $0 < hcpIndex }.count + 1

            // Calculate handicap strokes allocated to this hole
            // Standard WHS allocation: base strokes + extra stroke if remainder covers this hole index
            var strokesReceived = 0
            if courseHandicap >= 0 {
                let base = courseHandicap / holeCount
                let remainder = courseHandicap % holeCount
                strokesReceived = base + (rank <= remainder ? 1 : 0)
            } else {
                let absHcp = abs(courseHandicap)
                let base = absHcp / holeCount
                let remainder = absHcp % holeCount
                let minusStrokes = base + (rank > holeCount - remainder ? 1 : 0)
                strokesReceived = -minusStrokes
            }

            // Net Double Bogey maximum for WHS adjusted gross score = Par + 2 + strokesReceived
            let netDoubleBogey = max(1, par + 2 + strokesReceived)
            let adjustedHoleScore = min(gross, netDoubleBogey)

            // Net score for Stableford
            let netScore = gross - strokesReceived
            // Stableford points: 2 for Net Par, 3 for Net Birdie, 1 for Net Bogey, 0 for Net Double Bogey or worse
            let points = max(0, par - netScore + 2)

            totalGross += gross
            adjustedGross += adjustedHoleScore
            totalPoints += points
            holePointsList.append(points)
        }

        return (totalGross, adjustedGross, totalPoints, holePointsList)
    }

    static func handicapIndex(
        from entries: [ScoringRecordEntry],
        lowHandicapIndex: Double? = nil,
        applyCaps: Bool = true
    ) -> Double? {
        let recent = entries
            .sorted { $0.date > $1.date }
            .prefix(20)
            .map(\.scoreDifferential)

        guard let base = rawHandicapIndex(from: Array(recent)) else {
            return nil
        }

        let capped = applyCaps ? applyCap(to: base, lowHandicapIndex: lowHandicapIndex) : base
        return roundToTenth(capped)
    }

    static func targetResults(
        currentEntries: [ScoringRecordEntry],
        tee: TeeSnapshot,
        inputMode: RoundInputMode,
        lowHandicapIndex: Double? = nil,
        pcc: Double = 0
    ) -> [TargetResult] {
        guard let currentHandicap = handicapIndex(from: currentEntries, lowHandicapIndex: lowHandicapIndex) else {
            return []
        }

        let courseHandicap = courseHandicap(handicapIndex: currentHandicap, tee: tee)
        let candidateValues: ClosedRange<Int>
        switch inputMode {
        case .adjustedGrossScore, .holeByHole:
            let lowScore = max(tee.holes, 1)
            let highScore = tee.par + max(50, courseHandicap + 28)
            candidateValues = lowScore...highScore
        case .stablefordPoints:
            candidateValues = tee.holes == 9 ? 0...45 : 0...90
        }

        return candidateValues.compactMap { candidate in
            let adjustedGrossScore: Int
            switch inputMode {
            case .adjustedGrossScore, .holeByHole:
                adjustedGrossScore = candidate
            case .stablefordPoints:
                adjustedGrossScore = stablefordAdjustedGrossScore(
                    points: candidate,
                    par: tee.par,
                    courseHandicap: courseHandicap,
                    holes: tee.holes
                )
            }

            let differential: Double
            if tee.holes == 9 {
                guard let converted = nineHoleScoreDifferential(
                    adjustedGrossScore: adjustedGrossScore,
                    courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating,
                    pcc: pcc,
                    handicapIndex: currentHandicap
                ) else { return nil }
                differential = converted
            } else {
                differential = scoreDifferential(
                    adjustedGrossScore: adjustedGrossScore,
                    courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating,
                    pcc: pcc
                )
            }
            let newEntry = ScoringRecordEntry(date: .now, scoreDifferential: differential)
            let projectedEntries = applyExceptionalScoreAdjustment(
                to: currentEntries + [newEntry],
                currentHandicapIndex: currentHandicap,
                newDifferential: differential
            )
            let projected = handicapIndex(from: projectedEntries, lowHandicapIndex: lowHandicapIndex) ?? currentHandicap
            let change = roundToTenth(projected - currentHandicap)

            return TargetResult(
                inputMode: inputMode,
                value: candidate,
                adjustedGrossScore: adjustedGrossScore,
                scoreDifferential: differential,
                projectedHandicapIndex: projected,
                change: change,
                adjustmentNotes: exceptionalAdjustment(for: differential, currentHandicapIndex: currentHandicap).map { ["Exceptional score \($0.formatted(.number.precision(.fractionLength(1))))"] } ?? []
            )
        }
    }

    static func scoringEntry(for round: GolfRound, currentHandicapIndex: Double? = nil) -> ScoringRecordEntry? {
        if let handicapDifferential = round.handicapDifferential {
            return ScoringRecordEntry(date: round.date, scoreDifferential: roundToTenth(handicapDifferential))
        }

        let adjustedGrossScore: Int
        if let storedScore = round.adjustedGrossScore {
            adjustedGrossScore = storedScore
        } else {
            switch round.inputMode {
            case .adjustedGrossScore, .holeByHole:
                return nil
            case .stablefordPoints:
                guard let points = round.stablefordPoints else { return nil }
                let courseHandicap = courseHandicap(handicapIndex: currentHandicapIndex ?? 0, tee: round.teeSnapshot)
                adjustedGrossScore = stablefordAdjustedGrossScore(
                    points: points,
                    par: round.par,
                    courseHandicap: courseHandicap,
                    holes: round.holes
                )
            }
        }

        let differential: Double
        if round.holes == 9 {
            guard let currentHandicapIndex,
                  let converted = nineHoleScoreDifferential(
                    adjustedGrossScore: adjustedGrossScore,
                    courseRating: round.courseRating,
                    slopeRating: round.slopeRating,
                    pcc: round.pcc,
                    handicapIndex: currentHandicapIndex
                  ) else { return nil }
            differential = converted
        } else {
            differential = scoreDifferential(
                adjustedGrossScore: adjustedGrossScore,
                courseRating: round.courseRating,
                slopeRating: round.slopeRating,
                pcc: round.pcc
            )
        }

        return ScoringRecordEntry(
            date: round.date,
            scoreDifferential: differential
        )
    }

    static func scoringEntries(from rounds: [GolfRound], lowHandicapIndex: Double? = nil) -> [ScoringRecordEntry] {
        var entries: [ScoringRecordEntry] = []

        for round in rounds.sorted(by: { $0.date < $1.date }) {
            let currentHandicap = handicapIndex(from: entries, lowHandicapIndex: lowHandicapIndex)
            guard let entry = scoringEntry(for: round, currentHandicapIndex: currentHandicap) else { continue }
            entries = applyExceptionalScoreAdjustment(
                to: entries + [entry],
                currentHandicapIndex: currentHandicap ?? entry.scoreDifferential,
                newDifferential: entry.scoreDifferential
            )
        }

        return entries
    }

    static func handicapProgression(from rounds: [GolfRound], lowHandicapIndex: Double? = nil) -> [HCPTrendPoint] {
        var points: [HCPTrendPoint] = []
        var entries: [ScoringRecordEntry] = []
        var index = 0

        for round in rounds.sorted(by: { $0.date < $1.date }) {
            index += 1
            let currentHandicap = handicapIndex(from: entries, lowHandicapIndex: lowHandicapIndex)
            guard let entry = scoringEntry(for: round, currentHandicapIndex: currentHandicap) else { continue }
            entries = applyExceptionalScoreAdjustment(
                to: entries + [entry],
                currentHandicapIndex: currentHandicap ?? entry.scoreDifferential,
                newDifferential: entry.scoreDifferential
            )
            if let hcp = handicapIndex(from: entries, lowHandicapIndex: lowHandicapIndex) {
                points.append(HCPTrendPoint(date: round.date, handicapIndex: hcp, roundIndex: index))
            }
        }

        return points
    }

    static func applyExceptionalScoreAdjustment(
        to entries: [ScoringRecordEntry],
        currentHandicapIndex: Double,
        newDifferential: Double
    ) -> [ScoringRecordEntry] {
        guard let adjustment = exceptionalAdjustment(for: newDifferential, currentHandicapIndex: currentHandicapIndex) else {
            return entries
        }

        let recentIDs = Set(entries.sorted { $0.date > $1.date }.prefix(20).map(\.id))
        return entries.map { entry in
            guard recentIDs.contains(entry.id) else { return entry }
            var adjusted = entry
            adjusted.scoreDifferential = roundToTenth(entry.scoreDifferential + adjustment)
            return adjusted
        }
    }

    static func exceptionalAdjustment(for scoreDifferential: Double, currentHandicapIndex: Double) -> Double? {
        let difference = currentHandicapIndex - scoreDifferential
        if difference >= 10 {
            return -2
        }
        if difference >= 7 {
            return -1
        }
        return nil
    }

    static func rawHandicapIndex(from differentials: [Double]) -> Double? {
        guard differentials.count >= 3 else { return nil }

        let sorted = differentials.sorted()
        let rule = bestDifferentialRule(for: min(sorted.count, 20))
        let selected = sorted.prefix(rule.count)
        let average = selected.reduce(0, +) / Double(rule.count)
        return roundToTenth(average + rule.adjustment)
    }

    static func bestDifferentialRule(for scoreCount: Int) -> (count: Int, adjustment: Double) {
        switch scoreCount {
        case 3:
            (1, -2)
        case 4:
            (1, -1)
        case 5:
            (1, 0)
        case 6:
            (2, -1)
        case 7...8:
            (2, 0)
        case 9...11:
            (3, 0)
        case 12...14:
            (4, 0)
        case 15...16:
            (5, 0)
        case 17...18:
            (6, 0)
        case 19:
            (7, 0)
        default:
            (8, 0)
        }
    }

    static func applyCap(to handicapIndex: Double, lowHandicapIndex: Double?) -> Double {
        guard let lowHandicapIndex else { return handicapIndex }

        let increase = handicapIndex - lowHandicapIndex
        if increase <= 3 {
            return handicapIndex
        }

        let softCapped = lowHandicapIndex + 3 + ((increase - 3) * 0.5)
        return min(softCapped, lowHandicapIndex + 5)
    }

    static func roundToTenth(_ value: Double) -> Double {
        (value * 10).rounded(.toNearestOrAwayFromZero) / 10
    }

    static func formatHCPScore(_ value: Double) -> String {
        let rounded = roundToTenth(value)
        if rounded < 0 {
            let absValue = abs(rounded)
            return "+\(absValue.formatted(.number.precision(.fractionLength(1))))"
        }
        return rounded.formatted(.number.precision(.fractionLength(1)))
    }
}