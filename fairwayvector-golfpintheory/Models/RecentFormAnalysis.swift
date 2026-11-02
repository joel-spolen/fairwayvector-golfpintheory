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
            guard rounds.count >= recentRounds + minimumEarlierRounds else { continue }
            let recent = rounds.suffix(recentRounds)
            let earlier = rounds.dropLast(recentRounds)
            let recentHoles = recent.reduce(0) { $0 + $1.holes }
            let earlierHoles = earlier.reduce(0) { $0 + $1.holes }
            guard recentHoles >= minimumHoles(area), earlierHoles >= minimumHoles(area) else { continue }
            let recentValue = value(area, total: recent.reduce(0) { $0 + $1.total }, holes: recentHoles)
            let earlierValue = value(area, total: earlier.reduce(0) { $0 + $1.total }, holes: earlierHoles)
            let direction = lowerIsBetter(area) ? -1.0 : 1.0
            changes.append(Change(area: area, recent: recentValue, earlier: earlierValue,
                                  steps: (recentValue - earlierValue) / step(area) * direction))
        }
        guard !changes.isEmpty else {
            return .notEnoughData(roundsNeeded: max(1, recentRounds + minimumEarlierRounds - mostRoundsWithData))
        }
        let workOn = changes.filter { $0.steps <= -1 }.min { $0.steps < $1.steps }
        let goingWell = changes.filter { $0.steps >= 1 }.max { $0.steps < $1.steps }
        return workOn == nil && goingWell == nil ? .steady : .changes(workOn: workOn, goingWell: goingWell)
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
