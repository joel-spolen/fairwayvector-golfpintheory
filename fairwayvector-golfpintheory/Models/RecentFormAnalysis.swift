import Foundation

/// Compares the last rounds with all earlier rounds per skill area, using only the golfer's own history.
enum RecentFormAnalysis {
    enum Area: CaseIterable {
        case putting, approach, driving, shortGame, penalties
    }

    struct Change: Equatable {
        let area: Area
        let recent: Double
        let earlier: Double
        /// Positive is better; 1 step is the smallest change worth mentioning.
        let steps: Double
    }

    enum Outcome: Equatable {
        case notEnoughData(roundsNeeded: Int)
        case steady
        case changes(workOn: Change?, goingWell: Change?)
    }

    static let recentRounds = 5
    static let minimumEarlierRounds = 3

    static func analyze(_ records: [RoundPerformanceRecord]) -> Outcome {
        let ordered = records.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        var changes: [Change] = []
        var mostRoundsWithData = 0
        for area in Area.allCases {
            let rounds = ordered.compactMap { sample(area, in: $0) }.filter { $0.holes > 0 }
            mostRoundsWithData = max(mostRoundsWithData, rounds.count)
            guard rounds.count >= recentRounds + minimumEarlierRounds,
                  let change = change(area, recent: Array(rounds.suffix(recentRounds)),
                                      earlier: Array(rounds.dropLast(recentRounds)),
                                      minimumRecentHoles: minimumHoles(area)) else { continue }
            changes.append(change)
        }
        guard !changes.isEmpty else {
            return .notEnoughData(roundsNeeded: max(1, recentRounds + minimumEarlierRounds - mostRoundsWithData))
        }
        let workOn = changes.filter { $0.steps <= -1 }.min { $0.steps < $1.steps }
        let goingWell = changes.filter { $0.steps >= 1 }.max { $0.steps < $1.steps }
        return workOn == nil && goingWell == nil ? .steady : .changes(workOn: workOn, goingWell: goingWell)
    }

    /// Up to three clear differences between one round and the golfer's earlier rounds, biggest first.
    /// Nil when no area has enough data to compare.
    static func roundHighlights(_ round: RoundPerformanceRecord, earlier: [RoundPerformanceRecord]) -> [Change]? {
        let changes = Area.allCases.compactMap { area -> Change? in
            guard let current = sample(area, in: round), current.holes > 0 else { return nil }
            let previous = earlier.compactMap { sample(area, in: $0) }.filter { $0.holes > 0 }
            // A single round has fewer fairways and missed greens than five rounds.
            return change(area, recent: [current], earlier: previous,
                          minimumRecentHoles: area == .driving || area == .shortGame ? 5 : 9)
        }
        guard !changes.isEmpty else { return nil }
        return Array(changes.filter { abs($0.steps) >= 1 }.sorted { abs($0.steps) > abs($1.steps) }.prefix(3))
    }

    private static func change(_ area: Area, recent: [(total: Int, holes: Int)], earlier: [(total: Int, holes: Int)],
                               minimumRecentHoles: Int) -> Change? {
        let recentHoles = recent.reduce(0) { $0 + $1.holes }
        let earlierHoles = earlier.reduce(0) { $0 + $1.holes }
        guard earlier.count >= minimumEarlierRounds, recentHoles >= minimumRecentHoles,
              earlierHoles >= minimumHoles(area) else { return nil }
        let recentValue = value(area, total: recent.reduce(0) { $0 + $1.total }, holes: recentHoles)
        let earlierValue = value(area, total: earlier.reduce(0) { $0 + $1.total }, holes: earlierHoles)
        let direction = lowerIsBetter(area) ? -1.0 : 1.0
        return Change(area: area, recent: recentValue, earlier: earlierValue,
                      steps: (recentValue - earlierValue) / step(area) * direction)
    }

    private static func sample(_ area: Area, in record: RoundPerformanceRecord) -> (total: Int, holes: Int)? {
        switch area {
        case .putting: (record.putts, record.puttHoles)
        case .approach: (record.greens, record.greenHoles)
        case .driving: (record.fairways, record.fairwayHoles)
        case .penalties: (record.penalties, record.penaltyHoles)
        case .shortGame:
            record.holeDetails.compactMap(\.scramble).reduce(into: (total: 0, holes: 0)) { result, saved in
                result.holes += 1
                if saved { result.total += 1 }
            }
        }
    }

    private static func value(_ area: Area, total: Int, holes: Int) -> Double {
        switch area {
        case .putting: Double(total) / Double(holes)
        case .penalties: Double(total) / Double(holes) * 18
        case .approach, .driving, .shortGame: Double(total) / Double(holes) * 100
        }
    }

    private static func lowerIsBetter(_ area: Area) -> Bool {
        area == .putting || area == .penalties
    }

    private static func step(_ area: Area) -> Double {
        switch area {
        case .putting: 0.1
        case .penalties: 0.5
        case .approach, .driving, .shortGame: 5
        }
    }

    // Fairways only exist on par 4s and 5s, and scrambling only on missed greens.
    private static func minimumHoles(_ area: Area) -> Int {
        area == .driving || area == .shortGame ? 10 : 18
    }
}

extension RecentFormAnalysis.Area {
    var title: String {
        switch self {
        case .putting: L("Putting")
        case .approach: L("Approach (GIR)")
        case .driving: L("Driving (fairways)")
        case .shortGame: L("Short game (scrambling)")
        case .penalties: L("Penalties")
        }
    }
}

extension RecentFormAnalysis.Change {
    /// "2.1 putts per hole (was 1.9)" for recent form, "… · your average 1.9" for a single round.
    func valueText(comparedWithAverage: Bool) -> String {
        let decimal: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(1))) }
        let percent: (Double) -> String = { "\(Int($0.rounded()))%" }
        switch (area, comparedWithAverage) {
        case (.putting, false): return L("%@ putts per hole (was %@)", decimal(recent), decimal(earlier))
        case (.putting, true): return L("%@ putts per hole · your average %@", decimal(recent), decimal(earlier))
        case (.penalties, false): return L("%@ per 18 holes (was %@)", decimal(recent), decimal(earlier))
        case (.penalties, true): return L("%@ per 18 holes · your average %@", decimal(recent), decimal(earlier))
        case (_, false): return L("%@ (was %@)", percent(recent), percent(earlier))
        case (_, true): return L("%@ · your average %@", percent(recent), percent(earlier))
        }
    }

    /// Extra strokes per 18 holes (negative = saved). Only putts and penalties are strokes themselves.
    var strokesPer18: Double? {
        switch area {
        case .putting: (recent - earlier) * 18
        case .penalties: recent - earlier
        case .approach, .driving, .shortGame: nil
        }
    }

    var strokesText: String? {
        guard let strokes = strokesPer18 else { return nil }
        let amount = abs(strokes).formatted(.number.precision(.fractionLength(1)))
        return strokes > 0 ? L("≈ %@ more strokes per 18 holes", amount) : L("≈ %@ fewer strokes per 18 holes", amount)
    }
}
