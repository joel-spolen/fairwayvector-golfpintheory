//
//  Models.swift
//  fairwayvector-hcp-projection
//

import Foundation
import SwiftData

nonisolated enum PlayerSex: String, CaseIterable, Identifiable, Codable, Sendable {
    case male
    case female

    var id: String { rawValue }

    var label: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        }
    }
}

@Model
final class PlayerProfile {
    var name: String
    var lowHandicapIndex: Double?
    var selectedCountry: String?
    var defaultInputModeRawValue: String?
    var sexRawValue: String?
    var createdAt: Date

    init(
        name: String,
        lowHandicapIndex: Double? = nil,
        selectedCountry: String? = "Sweden",
        defaultInputModeRawValue: String? = RoundInputMode.adjustedGrossScore.rawValue,
        sexRawValue: String? = PlayerSex.male.rawValue,
        createdAt: Date = .now
    ) {
        self.name = name
        self.lowHandicapIndex = lowHandicapIndex
        self.selectedCountry = selectedCountry
        self.defaultInputModeRawValue = defaultInputModeRawValue
        self.sexRawValue = sexRawValue
        self.createdAt = createdAt
    }

    var countryOrDefault: String {
        selectedCountry ?? "Sweden"
    }

    var defaultInputMode: RoundInputMode {
        get {
            guard let raw = defaultInputModeRawValue, let mode = RoundInputMode(rawValue: raw) else {
                return .adjustedGrossScore
            }
            return mode
        }
        set {
            defaultInputModeRawValue = newValue.rawValue
        }
    }

    var sexOrDefault: PlayerSex {
        get { PlayerSex(rawValue: sexRawValue ?? "") ?? .male }
        set { sexRawValue = newValue.rawValue }
    }
}

@Model
final class GolfClub {
    var name: String
    var city: String
    var country: String
    var isCustom: Bool?

    init(name: String, city: String, country: String = "Sweden", isCustom: Bool? = false) {
        self.name = name
        self.city = city
        self.country = country
        self.isCustom = isCustom
    }
}

@Model
final class GolfCourse {
    var clubName: String
    var name: String
    var isCustom: Bool?

    init(clubName: String, name: String, isCustom: Bool? = false) {
        self.clubName = clubName
        self.name = name
        self.isCustom = isCustom
    }
}

@Model
final class TeeSet {
    var clubName: String
    var courseName: String
    var name: String
    var holes: Int
    var par: Int
    var courseRating: Double
    var slopeRating: Int
    var ratingSexRawValue: String?
    var isCustom: Bool?
    var holeParsData: [Int]?
    var holeHandicapIndicesData: [Int]?

    init(
        clubName: String,
        courseName: String,
        name: String,
        holes: Int = 18,
        par: Int,
        courseRating: Double,
        slopeRating: Int,
        ratingSexRawValue: String? = nil,
        isCustom: Bool? = false,
        holeParsData: [Int]? = nil,
        holeHandicapIndicesData: [Int]? = nil
    ) {
        self.clubName = clubName
        self.courseName = courseName
        self.name = name
        self.holes = holes
        self.par = par
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.ratingSexRawValue = ratingSexRawValue
        self.isCustom = isCustom
        self.holeParsData = holeParsData
        self.holeHandicapIndicesData = holeHandicapIndicesData
    }

    var holePars: [Int] {
        if let pars = holeParsData, pars.count == holes {
            return pars
        }
        return TeeSet.defaultPars(for: holes, totalPar: par)
    }

    var holeHandicapIndices: [Int] {
        if let indices = holeHandicapIndicesData, indices.count == holes {
            return indices
        }
        return Array(1...max(holes, 1))
    }

    var ratingSex: PlayerSex? {
        guard let ratingSexRawValue else { return nil }
        return PlayerSex(rawValue: ratingSexRawValue)
    }

    func isAvailable(for sex: PlayerSex) -> Bool {
        ratingSex == nil || ratingSex == sex
    }

    static func defaultPars(for holes: Int, totalPar: Int) -> [Int] {
        if holes == 9 {
            // typical 9-hole par: 4,4,3,4,5,4,3,4,5 = 36
            return [4, 4, 3, 4, 5, 4, 3, 4, 5]
        }
        // typical 18-hole par 72: front 36, back 36
        return [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5]
    }
}

@Model
final class GolfRound {
    var date: Date
    var clubName: String
    var courseName: String
    var teeName: String
    var holes: Int
    var inputModeRawValue: String
    var adjustedGrossScore: Int?
    var stablefordPoints: Int?
    var handicapDifferential: Double?
    var par: Int
    var courseRating: Double
    var slopeRating: Int
    var pcc: Double
    var notes: String
    var holeScoresData: [Int]?
    var holeParsData: [Int]?
    var holeHandicapIndicesData: [Int]?
    /// Optional additive field for existing SwiftData stores; nil for manual/legacy rounds.
    var sourceSavedRoundID: String? = nil

    init(
        date: Date = .now,
        clubName: String,
        courseName: String,
        teeName: String,
        holes: Int,
        inputMode: RoundInputMode,
        adjustedGrossScore: Int? = nil,
        stablefordPoints: Int? = nil,
        handicapDifferential: Double? = nil,
        par: Int,
        courseRating: Double,
        slopeRating: Int,
        pcc: Double = 0,
        notes: String = "",
        holeScoresData: [Int]? = nil,
        holeParsData: [Int]? = nil,
        holeHandicapIndicesData: [Int]? = nil
    ) {
        self.date = date
        self.clubName = clubName
        self.courseName = courseName
        self.teeName = teeName
        self.holes = holes
        self.inputModeRawValue = inputMode.rawValue
        self.adjustedGrossScore = adjustedGrossScore
        self.stablefordPoints = stablefordPoints
        self.handicapDifferential = handicapDifferential
        self.par = par
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.pcc = pcc
        self.notes = notes
        self.holeScoresData = holeScoresData
        self.holeParsData = holeParsData
        self.holeHandicapIndicesData = holeHandicapIndicesData
    }

    var inputMode: RoundInputMode {
        RoundInputMode(rawValue: inputModeRawValue) ?? .adjustedGrossScore
    }

    var holeScores: [Int]? {
        holeScoresData
    }

    var holePars: [Int]? {
        holeParsData
    }

    var holeHandicapIndices: [Int]? {
        holeHandicapIndicesData
    }

    var teeSnapshot: TeeSnapshot {
        TeeSnapshot(
            clubName: clubName,
            courseName: courseName,
            teeName: teeName,
            holes: holes,
            par: par,
            courseRating: courseRating,
            slopeRating: slopeRating
        )
    }

    var scoreSummaryText: String {
        var parts: [String] = []

        if let handicapDifferential {
            parts.append("HCP score: \(WHSCalculator.formatHCPScore(handicapDifferential))")
        }

        if let adjustedGrossScore {
            parts.append("Score: \(adjustedGrossScore)")
        }

        if let stablefordPoints {
            parts.append("Stableford: \(stablefordPoints)")
        }

        return parts.isEmpty ? "Score: —" : parts.joined(separator: " · ")
    }
}

enum RoundInputMode: String, CaseIterable, Identifiable, Codable {
    case adjustedGrossScore
    case stablefordPoints
    case holeByHole

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adjustedGrossScore:
            "Total Score"
        case .stablefordPoints:
            "Points"
        case .holeByHole:
            "Hole by Hole"
        }
    }
}

nonisolated struct TeeSnapshot: Hashable, Codable, Sendable {
    var clubName: String
    var courseName: String
    var teeName: String
    var holes: Int
    var par: Int
    var courseRating: Double
    var slopeRating: Int
}

struct ScoringRecordEntry: Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var scoreDifferential: Double
}

struct TargetResult: Hashable, Identifiable {
    var id = UUID()
    var inputMode: RoundInputMode
    var value: Int
    var adjustedGrossScore: Int
    var scoreDifferential: Double
    var projectedHandicapIndex: Double
    var change: Double
    var adjustmentNotes: [String]
}

struct HCPTrendPoint: Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var handicapIndex: Double
    var roundIndex: Int
}