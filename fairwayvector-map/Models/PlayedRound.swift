import Foundation

enum RoundGame: String, Codable, CaseIterable, Identifiable {
    case strokePlay = "Stroke play"
    case stableford = "Stableford"
    var id: String { rawValue }
}

enum RoundDetailMode: String, Codable, CaseIterable, Identifiable {
    case detailed = "Detailed"
    case strokesOnly = "Strokes only"
    var id: String { rawValue }
}

enum RoundFairway: String, Codable, CaseIterable, Identifiable {
    case unknown = "Not recorded"
    case hit = "Yes"
    case missed = "No"
    case left = "Left"
    case right = "Right"
    case long = "Long"
    case short = "Short"
    case notApplicable = "N/A"
    var id: String { rawValue }
    var label: String { self == .hit ? "Fairway" : rawValue }
}

struct RoundPlayer: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var isOwner: Bool
    var handicapIndex: Double?
}

struct PlayedHole: Codable, Identifiable, Equatable {
    var number: Int
    var par: Int?
    var strokeIndex: Int?
    var id: Int { number }
}

struct PlayedHoleScore: Codable, Equatable {
    /// Total strokes INCLUDE putts and penalties. Detail fields never add strokes.
    var strokes: Int
    var putts: Int?
    var fairway: RoundFairway = .unknown
    var bunkerShots: Int?
    var penalties: Int?

    var isValid: Bool {
        (1...30).contains(strokes)
        && [putts, bunkerShots, penalties].allSatisfy { $0.map { (0...strokes).contains($0) } ?? true }
        && (putts ?? 0) + (penalties ?? 0) <= strokes
    }
}

struct PlayedRound: Codable, Identifiable {
    var id = UUID()
    var date = Date.now
    var reference: CourseReference
    /// A local geometry snapshot makes resume independent of another provider load.
    var course: Course
    var holes: [PlayedHole]
    var players: [RoundPlayer]
    var game: RoundGame
    var detailMode: RoundDetailMode
    var allowance: Int = 100
    var currentHole: Int = 0
    var scores: [String: PlayedHoleScore] = [:]

    var owner: RoundPlayer? { players.first(where: \.isOwner) }
    var isComplete: Bool {
        !holes.isEmpty && players.allSatisfy { player in
            holes.allSatisfy { score(player: player.id, hole: $0.number)?.isValid == true }
        }
    }

    static func key(player: UUID, hole: Int) -> String { "\(player.uuidString):\(hole)" }
    func score(player: UUID, hole: Int) -> PlayedHoleScore? { scores[Self.key(player: player, hole: hole)] }
    mutating func setScore(_ score: PlayedHoleScore, player: UUID, hole: Int) {
        scores[Self.key(player: player, hole: hole)] = score
    }

    var tee: TeeSnapshot? {
        guard [9, 18].contains(holes.count), reference.holeCount == holes.count,
              reference.courseRating.isFinite, reference.courseRating > 0,
              (55...155).contains(reference.slopeRating),
              holes.allSatisfy({ $0.par.map { (3...6).contains($0) } ?? false }),
              holes.compactMap(\.par).reduce(0, +) == reference.totalPar else { return nil }
        return TeeSnapshot(clubName: reference.clubName, courseName: reference.courseName,
            teeName: reference.teeName, holes: holes.count, par: reference.totalPar,
            courseRating: reference.courseRating, slopeRating: reference.slopeRating)
    }

    /// Actual SI values may be odd/even 1...18 on a nine-hole side. Rank that side;
    /// never manufacture SI from hole number, and reject duplicates/missing values.
    var strokeRanks: [Int: Int]? {
        let indices = holes.compactMap(\.strokeIndex)
        guard [9, 18].contains(holes.count), indices.count == holes.count,
              Set(indices).count == holes.count, indices.allSatisfy({ (1...18).contains($0) }) else { return nil }
        let sorted = holes.sorted { $0.strokeIndex! < $1.strokeIndex! }
        return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($0.element.number, $0.offset + 1) })
    }
}

struct PlayedRoundTotals {
    var scoredHoles = 0
    var gross = 0
    var net: Int?
    var stableford: Int?
    var adjustedGross: Int?
    var courseHandicap: Int?
    var playingHandicap: Int?
    var differential: Double?
    var putts = 0
    var puttHoles = 0
    var fairwaysHit = 0
    var fairwaysAnswered = 0
    var estimatedGIR = 0
    var girHoles = 0
    var bunkerHoles = 0
    var bunkerAnswered = 0
    var bunkerShots = 0
    var penalties = 0
    var penaltyHoles = 0
}

enum PlayedRoundCalculator {
    static func courseHandicap(round: PlayedRound, player: RoundPlayer) -> Int? {
        guard let index = player.handicapIndex, index.isFinite, (-10...54).contains(index),
              let tee = round.tee else { return nil }
          return WHSCalculator.courseHandicap(handicapIndex: index, tee: tee)
    }

    static func strokes(handicap: Int, rank: Int, holeCount: Int) -> Int {
        guard holeCount > 0, (1...holeCount).contains(rank) else { return 0 }
        if handicap >= 0 { return handicap / holeCount + (rank <= handicap % holeCount ? 1 : 0) }
        // Plus handicaps give strokes back on the highest SI / easiest holes first.
        let magnitude = abs(handicap)
        return -(magnitude / holeCount + (rank > holeCount - magnitude % holeCount ? 1 : 0))
    }

    static func totals(round: PlayedRound, player: RoundPlayer) -> PlayedRoundTotals {
        var result = PlayedRoundTotals()
        let ranks = round.strokeRanks
        let courseHCP = courseHandicap(round: round, player: player)
        let playingHCP = courseHCP.map { Int(floor(Double($0) * Double(round.allowance) / 100 + 0.5)) }
        result.courseHandicap = courseHCP
        result.playingHandicap = playingHCP
        if ranks != nil, courseHCP != nil { result.adjustedGross = 0; result.net = 0; result.stableford = 0 }
        for hole in round.holes {
            guard let score = round.score(player: player.id, hole: hole.number), score.isValid else { continue }
            result.scoredHoles += 1
            result.gross += score.strokes
            if let rank = ranks?[hole.number], let par = hole.par, let ch = courseHCP, let ph = playingHCP {
                let received = strokes(handicap: ph, rank: rank, holeCount: round.holes.count)
                result.net? += score.strokes - received
                result.stableford? += max(0, 2 + par - (score.strokes - received))
                let whsStrokes = strokes(handicap: ch, rank: rank, holeCount: round.holes.count)
                result.adjustedGross? += min(score.strokes, max(1, par + 2 + whsStrokes))
            }
            if let putts = score.putts {
                result.putts += putts; result.puttHoles += 1
                if let par = hole.par {
                    result.girHoles += 1
                    if score.strokes - putts <= par - 2 { result.estimatedGIR += 1 }
                }
            }
            if hole.par.map({ $0 > 3 }) == true, [.hit, .missed, .left, .right, .long, .short].contains(score.fairway) {
                result.fairwaysAnswered += 1
                if score.fairway == .hit { result.fairwaysHit += 1 }
            }
            if let bunkerShots = score.bunkerShots {
                result.bunkerAnswered += 1; result.bunkerShots += bunkerShots
                if bunkerShots > 0 { result.bunkerHoles += 1 }
            }
            if let penalties = score.penalties { result.penalties += penalties; result.penaltyHoles += 1 }
        }
        if result.scoredHoles == round.holes.count,
           let adjusted = result.adjustedGross, let tee = round.tee {
            if round.holes.count == 18 {
                result.differential = WHSCalculator.scoreDifferential(adjustedGrossScore: adjusted,
                    courseRating: tee.courseRating, slopeRating: tee.slopeRating, pcc: 0)
            } else if round.holes.count == 9, let index = player.handicapIndex {
                result.differential = WHSCalculator.nineHoleScoreDifferential(adjustedGrossScore: adjusted,
                    courseRating: tee.courseRating, slopeRating: tee.slopeRating, pcc: 0, handicapIndex: index)
            }
        }
        return result
    }
}

struct RoundStatistics {
    var rounds: Int = 0
    var holes: Int = 0
    var gross: Int = 0
    var net = 0
    var netHoles = 0
    var putts = 0
    var puttHoles = 0
    var fairwaysHit = 0
    var fairwaysAnswered = 0
    var gir = 0
    var girHoles = 0
    var bunkerHoles = 0
    var bunkerAnswered = 0
    var penalties = 0
    var penaltyHoles = 0

    init(rounds records: [PlayedRound]) {
        for round in records where round.isComplete {
            guard let owner = round.owner else { continue }
            let t = PlayedRoundCalculator.totals(round: round, player: owner)
            rounds += 1; holes += t.scoredHoles; gross += t.gross
            if let n = t.net { net += n; netHoles += t.scoredHoles }
            putts += t.putts; puttHoles += t.puttHoles
            fairwaysHit += t.fairwaysHit; fairwaysAnswered += t.fairwaysAnswered
            gir += t.estimatedGIR; girHoles += t.girHoles
            bunkerHoles += t.bunkerHoles; bunkerAnswered += t.bunkerAnswered
            penalties += t.penalties; penaltyHoles += t.penaltyHoles
        }
    }
    static func rate(_ numerator: Int, _ denominator: Int, scale: Double = 1) -> Double? {
        denominator > 0 ? Double(numerator) / Double(denominator) * scale : nil
    }
}