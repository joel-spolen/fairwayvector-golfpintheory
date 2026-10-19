//
//  TestDataStore.swift
//  fairwayvector-hcp-projection
//
//  Snapshot import/export of profile + course + round data.
//  Never runs automatically — callers must invoke it explicitly.
//

import Foundation
import SwiftData

struct TestDataSnapshot: Codable {
    struct Profile: Codable {
        var name: String
        var lowHandicapIndex: Double?
        var selectedCountry: String?
        var defaultInputMode: String?
        var sex: String?
        var createdAt: Date?
    }

    struct Club: Codable {
        var name: String
        var city: String
        var country: String
        var isCustom: Bool?
    }

    struct Course: Codable {
        var clubName: String
        var name: String
        var isCustom: Bool?
    }

    struct Tee: Codable {
        var clubName: String
        var courseName: String
        var name: String
        var holes: Int
        var par: Int
        var courseRating: Double
        var slopeRating: Int
        var ratingSex: String?
        var isCustom: Bool?
        var holePars: [Int]?
        var holeHandicapIndices: [Int]?
    }

    struct Round: Codable {
        var date: Date
        var clubName: String
        var courseName: String
        var teeName: String
        var holes: Int
        var inputMode: String
        var adjustedGrossScore: Int?
        var stablefordPoints: Int?
        var handicapDifferential: Double?
        var par: Int
        var courseRating: Double
        var slopeRating: Int
        var pcc: Double
        var notes: String
        var holeScores: [Int]?
        var holePars: [Int]?
        var holeHandicapIndices: [Int]?
    }

    var schemaVersion: Int
    var name: String
    var profile: Profile?
    var clubs: [Club]
    var courses: [Course]
    var tees: [Tee]
    var rounds: [Round]
}

enum TestDataStore {
    static let bundledResourceName = "hcp-testdata"

    enum ImportError: LocalizedError {
        case resourceMissing
        case unsupportedSchemaVersion(Int)

        var errorDescription: String? {
            switch self {
            case .resourceMissing:
                "Bundled test data file \(bundledResourceName).json was not found."
            case let .unsupportedSchemaVersion(version):
                "Unsupported test data schema version \(version)."
            }
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func bundledSnapshot(bundle: Bundle = .main) throws -> TestDataSnapshot {
        guard let url = bundle.url(forResource: bundledResourceName, withExtension: "json") else {
            throw ImportError.resourceMissing
        }
        let snapshot = try decoder.decode(TestDataSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.schemaVersion == 1 else {
            throw ImportError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        return snapshot
    }

    /// Replaces all stored data with the bundled snapshot. Call only from an explicit user action.
    @discardableResult
    static func importBundledSnapshot(into modelContext: ModelContext, bundle: Bundle = .main) throws -> TestDataSnapshot {
        let snapshot = try bundledSnapshot(bundle: bundle)
        try replaceAll(with: snapshot, in: modelContext)
        return snapshot
    }

    static func replaceAll(with snapshot: TestDataSnapshot, in modelContext: ModelContext) throws {
        try modelContext.delete(model: GolfRound.self)
        try modelContext.delete(model: TeeSet.self)
        try modelContext.delete(model: GolfCourse.self)
        try modelContext.delete(model: GolfClub.self)
        try modelContext.delete(model: PlayerProfile.self)

        if let profile = snapshot.profile {
            modelContext.insert(
                PlayerProfile(
                    name: profile.name,
                    lowHandicapIndex: profile.lowHandicapIndex,
                    selectedCountry: profile.selectedCountry,
                    defaultInputModeRawValue: profile.defaultInputMode,
                    sexRawValue: profile.sex,
                    createdAt: profile.createdAt ?? .now
                )
            )
        }

        for club in snapshot.clubs {
            modelContext.insert(
                GolfClub(name: club.name, city: club.city, country: club.country, isCustom: club.isCustom)
            )
        }

        for course in snapshot.courses {
            modelContext.insert(
                GolfCourse(clubName: course.clubName, name: course.name, isCustom: course.isCustom)
            )
        }

        for tee in snapshot.tees {
            modelContext.insert(
                TeeSet(
                    clubName: tee.clubName,
                    courseName: tee.courseName,
                    name: tee.name,
                    holes: tee.holes,
                    par: tee.par,
                    courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating,
                    ratingSexRawValue: tee.ratingSex,
                    isCustom: tee.isCustom,
                    holeParsData: tee.holePars,
                    holeHandicapIndicesData: tee.holeHandicapIndices
                )
            )
        }

        for round in snapshot.rounds {
            modelContext.insert(
                GolfRound(
                    date: round.date,
                    clubName: round.clubName,
                    courseName: round.courseName,
                    teeName: round.teeName,
                    holes: round.holes,
                    inputMode: RoundInputMode(rawValue: round.inputMode) ?? .adjustedGrossScore,
                    adjustedGrossScore: round.adjustedGrossScore,
                    stablefordPoints: round.stablefordPoints,
                    handicapDifferential: round.handicapDifferential,
                    par: round.par,
                    courseRating: round.courseRating,
                    slopeRating: round.slopeRating,
                    pcc: round.pcc,
                    notes: round.notes,
                    holeScoresData: round.holeScores,
                    holeParsData: round.holePars,
                    holeHandicapIndicesData: round.holeHandicapIndices
                )
            )
        }

        try modelContext.save()
    }

    /// Serialises the current store so a device's data can be captured as a new fixture.
    static func exportSnapshotJSON(from modelContext: ModelContext, name: String) throws -> Data {
        let profile = try modelContext.fetch(FetchDescriptor<PlayerProfile>()).first
        let clubs = try modelContext.fetch(FetchDescriptor<GolfClub>())
        let courses = try modelContext.fetch(FetchDescriptor<GolfCourse>())
        let tees = try modelContext.fetch(FetchDescriptor<TeeSet>())
        let rounds = try modelContext.fetch(
            FetchDescriptor<GolfRound>(sortBy: [SortDescriptor(\.date)])
        )

        let snapshot = TestDataSnapshot(
            schemaVersion: 1,
            name: name,
            profile: profile.map {
                .init(
                    name: $0.name,
                    lowHandicapIndex: $0.lowHandicapIndex,
                    selectedCountry: $0.selectedCountry,
                    defaultInputMode: $0.defaultInputModeRawValue,
                    sex: $0.sexRawValue,
                    createdAt: $0.createdAt
                )
            },
            clubs: clubs.map { .init(name: $0.name, city: $0.city, country: $0.country, isCustom: $0.isCustom) },
            courses: courses.map { .init(clubName: $0.clubName, name: $0.name, isCustom: $0.isCustom) },
            tees: tees.map {
                .init(
                    clubName: $0.clubName,
                    courseName: $0.courseName,
                    name: $0.name,
                    holes: $0.holes,
                    par: $0.par,
                    courseRating: $0.courseRating,
                    slopeRating: $0.slopeRating,
                    ratingSex: $0.ratingSexRawValue,
                    isCustom: $0.isCustom,
                    holePars: $0.holeParsData,
                    holeHandicapIndices: $0.holeHandicapIndicesData
                )
            },
            rounds: rounds.map {
                .init(
                    date: $0.date,
                    clubName: $0.clubName,
                    courseName: $0.courseName,
                    teeName: $0.teeName,
                    holes: $0.holes,
                    inputMode: $0.inputModeRawValue,
                    adjustedGrossScore: $0.adjustedGrossScore,
                    stablefordPoints: $0.stablefordPoints,
                    handicapDifferential: $0.handicapDifferential,
                    par: $0.par,
                    courseRating: $0.courseRating,
                    slopeRating: $0.slopeRating,
                    pcc: $0.pcc,
                    notes: $0.notes,
                    holeScores: $0.holeScoresData,
                    holePars: $0.holeParsData,
                    holeHandicapIndices: $0.holeHandicapIndicesData
                )
            }
        )

        return try encoder.encode(snapshot)
    }
}
