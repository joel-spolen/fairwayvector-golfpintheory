import CryptoKit
import Foundation

private extension Array where Element: Hashable {
    var nilIfDuplicates: [Element]? {
        Set(self).count == count ? self : nil
    }
}

/// Portable account-owned records. Preferences, active drafts, downloaded course catalogs,
/// and course geometry are intentionally excluded.
enum AccountSyncDomainAdapter {
    private struct CustomClubPayload: Codable {
        let name: String
        let city: String
        let country: String
    }

    private struct CustomCoursePayload: Codable {
        let clubRecordID: UUID
        let clubName: String
        let name: String
    }

    private struct CustomTeePayload: Codable {
        let clubRecordID: UUID
        let courseRecordID: UUID
        let clubName: String
        let courseName: String
        let name: String
        let holes: Int
        let par: Int
        let courseRating: Double
        let slopeRating: Int
        let ratingSex: String?
        let holePars: [Int]?
        let holeHandicapIndices: [Int]?
    }

    private struct GolferProfilePayload: Codable {
        let name: String
        let lowHandicapIndex: Double?
    }

    private struct ClubOverridePayload: Codable {
        let club: String
        let carryDistanceM: Double?
        let ballSpeedMps: Double?
        let launchAngleDeg: Double?
        let spinRateRpm: Double?
        let spinAxisDeg: Double?
    }

    private struct ClubProfilePayload: Codable {
        let clientUpdatedAt: String?
        let schemaVersion: Int
        let isSetupComplete: Bool
        let detailLevel: String
        let handicapBand: String
        let exactHandicap: Double?
        let driverCarryM: Double?
        let sevenIronCarryM: Double?
        let availableClubs: [String]
        let clubOverrides: [ClubOverridePayload]
    }

    private struct ScorecardPayload: Codable {
        struct TeeReference: Codable {
            let clubName: String
            let courseName: String
            let city: String
            let region: String
            let holeCount: Int
            let totalPar: Int
            let teeName: String
            let teeSex: String
            let courseRating: Double
            let slopeRating: Int
        }

        struct Hole: Codable {
            let number: Int
            let par: Int?
            let strokeIndex: Int?
        }

        struct Player: Codable {
            let id: UUID
            let name: String
            let isOwner: Bool
            let handicapIndex: Double?
            let keepsDetailedScore: Bool?
        }

        struct Score: Codable {
            let strokes: Int
            let putts: Int?
            let fairway: String
            let bunkerShots: Int?
            let penalties: Int?
        }

        let version: Int
        let date: String
        let reference: TeeReference
        let holes: [Hole]
        let players: [Player]
        let game: String
        let detailMode: String
        let allowance: Int
        let scores: [String: Score]
        let notes: String?
    }

    private struct WedgePayload: Codable {
        let clientUpdatedAt: String?
        let name: String
        let brand: String
        let notes: String
        let fullCarry: Double
        let isInBag: Bool
        let fullCarryUserProvided: Bool
        let carryOverrides: [String: Double]
    }

    private struct HandicapRoundPayload: Codable {
        let date: String
        let clubName: String
        let courseName: String
        let teeName: String
        let holes: Int
        let inputMode: String
        let adjustedGrossScore: Int?
        let stablefordPoints: Int?
        let handicapDifferential: Double?
        let par: Int
        let courseRating: Double
        let slopeRating: Int
        let pcc: Double
        let notes: String
        let holeScores: [Int]?
        let holePars: [Int]?
        let holeHandicapIndices: [Int]?
        let sourceSavedRoundID: String?
    }

    struct CustomRecords {
        let mutations: [AccountSyncMutation]
        let clubsByID: [UUID: GolfClub]
        let coursesByID: [UUID: GolfCourse]
        let teesByID: [UUID: TeeSet]
    }

    static func golferProfileRecordID(ownerID: UUID) -> UUID {
        deterministicID(ownerID: ownerID, namespace: "golfer-profile-v1")
    }

    static func clubProfileRecordID(ownerID: UUID) -> UUID {
        deterministicID(ownerID: ownerID, namespace: "trajectory-club-profile-v1")
    }

    static func clubProfileMutation(_ profile: TrajectoryPlayerProfile, ownerID: UUID,
                                    modifiedAt: Date = Date()) throws -> AccountSyncMutation {
        let overrides = profile.clubOverrides.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { club -> ClubOverridePayload? in
            guard let value = profile.clubOverrides[club], !value.isEmpty else { return nil }
            return ClubOverridePayload(club: club.rawValue, carryDistanceM: value.carryDistanceM,
                ballSpeedMps: value.ballSpeedMps, launchAngleDeg: value.launchAngleDeg,
                spinRateRpm: value.spinRateRpm, spinAxisDeg: value.spinAxisDeg)
        }
        let payload = ClubProfilePayload(clientUpdatedAt: isoTimestamp(modifiedAt),
            schemaVersion: profile.schemaVersion,
            isSetupComplete: profile.isSetupComplete, detailLevel: profile.detailLevel.rawValue,
            handicapBand: profile.handicapBand == .twentyFivePlus ? HandicapBand.twentyFiveToThirtyFive.rawValue : profile.handicapBand.rawValue,
            exactHandicap: profile.exactHandicap, driverCarryM: profile.driverCarryM,
            sevenIronCarryM: profile.sevenIronCarryM,
            availableClubs: profile.availableClubs.map(\.rawValue).sorted(), clubOverrides: overrides)
        try validateClubProfile(profile)
        return try AccountSyncMutation(recordID: clubProfileRecordID(ownerID: ownerID),
            kind: .clubProfile, expectedRevision: .zero, payload: encodePayload(payload))
    }

    static func isDefaultClubProfile(_ profile: TrajectoryPlayerProfile) -> Bool {
        profile == TrajectoryPlayerProfile()
    }

    static func clubProfile(from record: AccountSyncLocalRecord) throws -> TrajectoryPlayerProfile {
        guard record.kind == .clubProfile, !record.isDeleted else { throw AccountSyncError.invalidWire }
        let payload = try decodePayload(ClubProfilePayload.self, from: record.payload)
          let decodedClubs = payload.availableClubs.compactMap(TrajectoryGolfClub.init(rawValue:))
        guard payload.schemaVersion == 1,
              let detail = ProfileDetailLevel(rawValue: payload.detailLevel),
              let band = HandicapBand(rawValue: payload.handicapBand),
              decodedClubs.count == payload.availableClubs.count,
              decodedClubs.nilIfDuplicates != nil,
              payload.clubOverrides.map(\.club).nilIfDuplicates != nil else { throw AccountSyncError.invalidWire }
        var overrides: [TrajectoryGolfClub: ClubLaunchOverride] = [:]
        for item in payload.clubOverrides {
            guard let club = TrajectoryGolfClub(rawValue: item.club) else { throw AccountSyncError.invalidWire }
            overrides[club] = ClubLaunchOverride(carryDistanceM: item.carryDistanceM,
                ballSpeedMps: item.ballSpeedMps, launchAngleDeg: item.launchAngleDeg,
                spinRateRpm: item.spinRateRpm, spinAxisDeg: item.spinAxisDeg)
        }
        let profile = TrajectoryPlayerProfile(schemaVersion: payload.schemaVersion,
            isSetupComplete: payload.isSetupComplete, detailLevel: detail, handicapBand: band,
            exactHandicap: payload.exactHandicap, driverCarryM: payload.driverCarryM,
            sevenIronCarryM: payload.sevenIronCarryM, clubOverrides: overrides,
            availableClubs: Set(decodedClubs))
        try validateClubProfile(profile)
        return profile
    }

    static func clubProfileModifiedAt(from record: AccountSyncRecord) -> Date {
        if let payload = try? decodePayload(ClubProfilePayload.self, from: record.payload),
           let timestamp = payload.clientUpdatedAt, let date = parseDate(timestamp) {
            return date
        }
        return parseDate(record.updatedAt) ?? .distantPast
    }

    static func clubProfileModifiedAt(in payload: [String: JSONValue]) -> Date? {
        bagModifiedAt(in: payload)
    }

    static func bagModifiedAt(in payload: [String: JSONValue]) -> Date? {
        guard case .string(let value)? = payload["clientUpdatedAt"] else { return nil }
        return parseDate(value)
    }

    static func bagModifiedAt(from record: AccountSyncRecord) -> Date {
        if let deletedAt = record.deletedAt, let date = parseDate(deletedAt) { return date }
        if let payloadDate = bagModifiedAt(in: record.payload) { return payloadDate }
        return parseDate(record.updatedAt) ?? .distantPast
    }

    private static func validateClubProfile(_ profile: TrajectoryPlayerProfile) throws {
        let numbers = [profile.exactHandicap, profile.driverCarryM, profile.sevenIronCarryM]
            .compactMap { $0 }
        guard profile.schemaVersion == 1,
              profile.exactHandicap.map({ $0.isFinite && (-5...40).contains($0) }) ?? true,
              profile.driverCarryM.map({ $0.isFinite && (0...500).contains($0) }) ?? true,
              profile.sevenIronCarryM.map({ $0.isFinite && (0...300).contains($0) }) ?? true,
              numbers.allSatisfy(\.isFinite) else { throw AccountSyncError.invalidWire }
        for override in profile.clubOverrides.values {
            guard override.carryDistanceM.map({ $0.isFinite && (0...500).contains($0) }) ?? true,
                  override.ballSpeedMps.map({ $0.isFinite && (0...150).contains($0) }) ?? true,
                  override.launchAngleDeg.map({ $0.isFinite && (-20...60).contains($0) }) ?? true,
                  override.spinRateRpm.map({ $0.isFinite && (0...20_000).contains($0) }) ?? true,
                  override.spinAxisDeg.map({ $0.isFinite && (-180...180).contains($0) }) ?? true else {
                throw AccountSyncError.invalidWire
            }
        }
    }

    static func customClubRecordID(ownerID: UUID, club: GolfClub) -> UUID {
        deterministicID(ownerID: ownerID, namespace: "custom-club-v1|\(normalized(club.name))|\(normalized(club.city))|\(normalized(club.country))")
    }

    static func customCourseRecordID(ownerID: UUID, club: GolfClub, courseName: String) -> UUID {
        deterministicID(ownerID: ownerID, namespace: "custom-course-v1|\(customClubRecordID(ownerID: ownerID, club: club).uuidString)|\(normalized(courseName))")
    }

    static func customTeeRecordID(ownerID: UUID, club: GolfClub, courseName: String, teeName: String) -> UUID {
        deterministicID(ownerID: ownerID, namespace: "custom-tee-v1|\(customCourseRecordID(ownerID: ownerID, club: club, courseName: courseName).uuidString)|\(normalized(teeName))")
    }

    static func wedgeRecordID(ownerID: UUID, wedgeName: String) -> UUID {
        deterministicID(ownerID: ownerID, namespace: "wedge-v1|\(normalized(wedgeName))")
    }

    static func handicapRoundRecordID(_ round: GolfRound) -> UUID {
        if let syncID = round.syncID { return syncID }
        let syncID = UUID()
        round.syncID = syncID
        return syncID
    }

    static func customMutations(ownerID: UUID, clubs: [GolfClub], courses: [GolfCourse],
                                tees: [TeeSet]) throws -> CustomRecords {
        let customClubs = clubs.filter { $0.isCustom == true }
        let clubLookup = Dictionary(customClubs.map {
            ("\(normalized($0.name))|\(normalized($0.country))", $0)
        }, uniquingKeysWith: { first, _ in first })
        var clubsByID: [UUID: GolfClub] = [:]
        var coursesByID: [UUID: GolfCourse] = [:]
        var teesByID: [UUID: TeeSet] = [:]
        var mutations: [AccountSyncMutation] = []

        for club in customClubs {
            let id = customClubRecordID(ownerID: ownerID, club: club)
            club.syncID = id
            clubsByID[id] = club
            let payload = CustomClubPayload(name: club.name, city: club.city, country: club.country)
            mutations.append(try AccountSyncMutation(recordID: id, kind: .customClub,
                expectedRevision: .zero, payload: encodePayload(payload)))
        }

        for course in courses where course.isCustom == true {
            guard let club = clubLookup["\(normalized(course.clubName))|\(normalized(clubs.first(where: { normalized($0.name) == normalized(course.clubName) })?.country ?? ""))"]
                    ?? customClubs.first(where: { normalized($0.name) == normalized(course.clubName) }) else { continue }
            let id = customCourseRecordID(ownerID: ownerID, club: club, courseName: course.name)
            course.syncID = id
            coursesByID[id] = course
            let parentID = customClubRecordID(ownerID: ownerID, club: club)
            mutations.append(try AccountSyncMutation(recordID: id, kind: .customCourse,
                expectedRevision: .zero, payload: encodePayload(CustomCoursePayload(
                    clubRecordID: parentID, clubName: club.name, name: course.name))))
        }

        for tee in tees where tee.isCustom == true {
            guard let club = customClubs.first(where: { normalized($0.name) == normalized(tee.clubName) }),
                  let course = courses.first(where: {
                      $0.isCustom == true && normalized($0.clubName) == normalized(tee.clubName)
                          && normalized($0.name) == normalized(tee.courseName)
                  }) else { continue }
            let courseID = customCourseRecordID(ownerID: ownerID, club: club, courseName: course.name)
            let id = customTeeRecordID(ownerID: ownerID, club: club, courseName: course.name, teeName: tee.name)
            tee.syncID = id
            teesByID[id] = tee
            mutations.append(try AccountSyncMutation(recordID: id, kind: .customTee,
                expectedRevision: .zero, payload: encodePayload(CustomTeePayload(
                    clubRecordID: customClubRecordID(ownerID: ownerID, club: club),
                    courseRecordID: courseID, clubName: club.name, courseName: course.name,
                    name: tee.name, holes: tee.holes, par: tee.par, courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating, ratingSex: tee.ratingSexRawValue,
                    holePars: tee.holeParsData, holeHandicapIndices: tee.holeHandicapIndicesData))))
        }
        return CustomRecords(mutations: mutations, clubsByID: clubsByID,
                             coursesByID: coursesByID, teesByID: teesByID)
    }

    static func customClub(from record: AccountSyncLocalRecord) throws -> (id: UUID, name: String, city: String, country: String) {
        guard record.kind == .customClub, !record.isDeleted else { throw AccountSyncError.invalidWire }
        let value = try decodePayload(CustomClubPayload.self, from: record.payload)
        guard !value.name.isEmpty, !value.country.isEmpty else { throw AccountSyncError.invalidWire }
        return (record.recordID, value.name, value.city, value.country)
    }

    static func customCourse(from record: AccountSyncLocalRecord) throws -> (id: UUID, clubID: UUID, clubName: String, name: String) {
        guard record.kind == .customCourse, !record.isDeleted else { throw AccountSyncError.invalidWire }
        let value = try decodePayload(CustomCoursePayload.self, from: record.payload)
        guard !value.name.isEmpty else { throw AccountSyncError.invalidWire }
        return (record.recordID, value.clubRecordID, value.clubName, value.name)
    }

    static func customTee(from record: AccountSyncLocalRecord) throws -> (id: UUID, clubID: UUID, courseID: UUID, payload: (clubName: String, courseName: String, name: String, holes: Int, par: Int, courseRating: Double, slopeRating: Int, ratingSex: String?, holePars: [Int]?, holeHandicapIndices: [Int]?)) {
        guard record.kind == .customTee, !record.isDeleted else { throw AccountSyncError.invalidWire }
        let value = try decodePayload(CustomTeePayload.self, from: record.payload)
        guard (9...18).contains(value.holes), value.par > 0,
              value.courseRating.isFinite, value.slopeRating > 0,
              value.holePars.map({ $0.count == value.holes && $0.allSatisfy { (3...6).contains($0) } }) ?? true,
              value.holeHandicapIndices.map({ $0.count == value.holes && Set($0).count == $0.count && $0.allSatisfy { (1...18).contains($0) } }) ?? true else {
            throw AccountSyncError.invalidWire
        }
        return (record.recordID, value.clubRecordID, value.courseRecordID,
            (value.clubName, value.courseName, value.name, value.holes, value.par,
             value.courseRating, value.slopeRating, value.ratingSex, value.holePars, value.holeHandicapIndices))
    }

    static func wedgeMutation(_ wedge: Wedge, ownerID: UUID,
                              modifiedAt: Date? = nil) throws -> AccountSyncMutation {
        guard wedge.fullCarry.isFinite, wedge.fullCarry >= 0,
              wedge.syncCarryOverrides.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw AccountSyncError.invalidWire
        }
        let payload = WedgePayload(clientUpdatedAt: modifiedAt.map(isoTimestamp),
            name: wedge.name, brand: wedge.brand, notes: wedge.notes,
            fullCarry: wedge.fullCarry, isInBag: wedge.isInBag,
            fullCarryUserProvided: wedge.fullCarryUserProvided, carryOverrides: wedge.syncCarryOverrides)
        return try AccountSyncMutation(recordID: wedgeRecordID(ownerID: ownerID, wedgeName: wedge.name),
            kind: .wedge, expectedRevision: .zero, payload: encodePayload(payload))
    }

    static func wedge(from record: AccountSyncLocalRecord, ownerID: UUID) throws -> Wedge {
        guard record.kind == .wedge, !record.isDeleted else { throw AccountSyncError.invalidWire }
        let payload = try decodePayload(WedgePayload.self, from: record.payload)
        guard record.recordID == wedgeRecordID(ownerID: ownerID, wedgeName: payload.name),
              payload.fullCarry.isFinite, payload.fullCarry >= 0,
              payload.carryOverrides.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw AccountSyncError.invalidWire
        }
        var wedge = Wedge(id: record.recordID, name: payload.name, brand: payload.brand, notes: payload.notes,
                          fullCarry: payload.fullCarry, isInBag: payload.isInBag,
                          fullCarryUserProvided: payload.fullCarryUserProvided)
        wedge.syncCarryOverrides = payload.carryOverrides
        return wedge
    }

    @MainActor
    static func handicapRoundMutation(_ round: GolfRound) throws -> AccountSyncMutation {
        let id = handicapRoundRecordID(round)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload = HandicapRoundPayload(date: formatter.string(from: round.date),
            clubName: round.clubName, courseName: round.courseName, teeName: round.teeName,
            holes: round.holes, inputMode: round.inputModeRawValue,
            adjustedGrossScore: round.adjustedGrossScore, stablefordPoints: round.stablefordPoints,
            handicapDifferential: round.handicapDifferential, par: round.par,
            courseRating: round.courseRating, slopeRating: round.slopeRating, pcc: round.pcc,
            notes: round.notes, holeScores: round.holeScoresData, holePars: round.holeParsData,
            holeHandicapIndices: round.holeHandicapIndicesData, sourceSavedRoundID: round.sourceSavedRoundID)
        return try AccountSyncMutation(recordID: id, kind: .handicapRound, expectedRevision: .zero,
                                       payload: encodePayload(payload))
    }

    static func handicapRound(from record: AccountSyncLocalRecord) throws -> (id: UUID, payload: HandicapRoundData) {
        guard record.kind == .handicapRound, !record.isDeleted else { throw AccountSyncError.invalidWire }
        let value = try decodePayload(HandicapRoundPayload.self, from: record.payload)
        guard let date = parseDate(value.date),
              (1...18).contains(value.holes), value.par > 0,
              value.courseRating.isFinite, value.pcc.isFinite,
              value.handicapDifferential.map(\.isFinite) ?? true,
              value.holeScores.map({ $0.count == value.holes && $0.allSatisfy { (1...30).contains($0) } }) ?? true,
              value.holePars.map({ $0.count == value.holes && $0.allSatisfy { $0 > 0 } }) ?? true,
              value.holeHandicapIndices.map({ $0.count == value.holes && Set($0).count == $0.count && $0.allSatisfy { (1...18).contains($0) } }) ?? true else {
            throw AccountSyncError.invalidWire
        }
        return (record.recordID, HandicapRoundData(date: date, clubName: value.clubName,
            courseName: value.courseName, teeName: value.teeName, holes: value.holes,
            inputMode: RoundInputMode(rawValue: value.inputMode) ?? .adjustedGrossScore,
            adjustedGrossScore: value.adjustedGrossScore, stablefordPoints: value.stablefordPoints,
            handicapDifferential: value.handicapDifferential, par: value.par,
            courseRating: value.courseRating, slopeRating: value.slopeRating, pcc: value.pcc,
            notes: value.notes, holeScores: value.holeScores, holePars: value.holePars,
            holeHandicapIndices: value.holeHandicapIndices, sourceSavedRoundID: value.sourceSavedRoundID))
    }

    struct HandicapRoundData {
        let date: Date
        let clubName: String
        let courseName: String
        let teeName: String
        let holes: Int
        let inputMode: RoundInputMode
        let adjustedGrossScore: Int?
        let stablefordPoints: Int?
        let handicapDifferential: Double?
        let par: Int
        let courseRating: Double
        let slopeRating: Int
        let pcc: Double
        let notes: String
        let holeScores: [Int]?
        let holePars: [Int]?
        let holeHandicapIndices: [Int]?
        let sourceSavedRoundID: String?
    }

    static func golferProfileMutation(_ profile: PlayerProfile, ownerID: UUID,
                                      expectedRevision: AccountSyncRevision) throws -> AccountSyncMutation {
        guard profile.lowHandicapIndex.map({ $0.isFinite && (-10...54).contains($0) }) ?? true else {
            throw AccountSyncError.invalidWire
        }
        return try AccountSyncMutation(recordID: golferProfileRecordID(ownerID: ownerID),
            kind: .golferProfile, expectedRevision: expectedRevision,
            payload: encodePayload(GolferProfilePayload(name: profile.name, lowHandicapIndex: profile.lowHandicapIndex)))
    }

    static func golferProfile(from record: AccountSyncRecord) throws -> (name: String, lowHandicapIndex: Double?) {
        guard record.kind == .golferProfile else { throw AccountSyncError.invalidWire }
        return try golferProfile(from: record.payload)
    }

    static func golferProfile(from record: AccountSyncLocalRecord) throws -> (name: String, lowHandicapIndex: Double?) {
        guard record.kind == .golferProfile, !record.isDeleted else { throw AccountSyncError.invalidWire }
        return try golferProfile(from: record.payload)
    }

    private static func golferProfile(from payloadValues: [String: JSONValue]) throws -> (name: String, lowHandicapIndex: Double?) {
        let payload = try decodePayload(GolferProfilePayload.self, from: payloadValues)
        guard !payload.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payload.lowHandicapIndex.map({ $0.isFinite && (-10...54).contains($0) }) ?? true else {
            throw AccountSyncError.invalidWire
        }
        return (payload.name, payload.lowHandicapIndex)
    }

    static func playedRoundMutation(_ round: PlayedRound, expectedRevision: AccountSyncRevision) throws -> AccountSyncMutation {
        guard PlayedRoundStore.validStructure(round) else { throw AccountSyncError.invalidWire }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload = ScorecardPayload(version: 1, date: formatter.string(from: round.date),
            reference: .init(clubName: round.reference.clubName, courseName: round.reference.courseName,
                city: round.reference.city, region: round.reference.region, holeCount: round.reference.holeCount,
                totalPar: round.reference.totalPar, teeName: round.reference.teeName,
                teeSex: round.reference.teeSex, courseRating: round.reference.courseRating,
                slopeRating: round.reference.slopeRating),
            holes: round.holes.map { .init(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex) },
            players: round.players.map { .init(id: $0.id, name: $0.name, isOwner: $0.isOwner,
                handicapIndex: $0.handicapIndex, keepsDetailedScore: $0.keepsDetailedScore) },
            game: round.game.rawValue, detailMode: round.detailMode.rawValue, allowance: round.allowance,
            scores: round.scores.mapValues { .init(strokes: $0.strokes, putts: $0.putts,
                fairway: $0.fairway.rawValue, bunkerShots: $0.bunkerShots, penalties: $0.penalties) },
            notes: round.notes)
        return try AccountSyncMutation(recordID: round.id, kind: .playedRound,
            expectedRevision: expectedRevision, payload: encodePayload(payload))
    }

    static func playedRound(from record: AccountSyncRecord) throws -> PlayedRound {
        guard record.kind == .playedRound, record.deletedAt == nil else { throw AccountSyncError.invalidWire }
        return try playedRound(recordID: record.recordID, payloadValues: record.payload)
    }

    static func playedRound(from record: AccountSyncLocalRecord) throws -> PlayedRound {
        guard record.kind == .playedRound, !record.isDeleted else { throw AccountSyncError.invalidWire }
        return try playedRound(recordID: record.recordID, payloadValues: record.payload)
    }

    private static func playedRound(recordID: UUID, payloadValues: [String: JSONValue]) throws -> PlayedRound {
        let payload = try decodePayload(ScorecardPayload.self, from: payloadValues)
        guard payload.version == 1,
              let game = RoundGame(rawValue: payload.game),
              let detailMode = RoundDetailMode(rawValue: payload.detailMode),
              let date = parseDate(payload.date) else { throw AccountSyncError.invalidWire }
        var reference = CourseReference(osmRelationID: 0, name: payload.reference.courseName)
        reference.osmRelationID = nil
        reference.golfAPICourseID = nil
        reference.golfAPITeeID = nil
        reference.clubName = payload.reference.clubName
        reference.courseName = payload.reference.courseName
        reference.city = payload.reference.city
        reference.region = payload.reference.region
        reference.location = nil
        reference.holeCount = payload.reference.holeCount
        reference.totalPar = payload.reference.totalPar
        reference.teeName = payload.reference.teeName
        reference.teeSex = payload.reference.teeSex
        reference.courseRating = payload.reference.courseRating
        reference.slopeRating = payload.reference.slopeRating
        let holes = payload.holes.map { PlayedHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex) }
        let courseHoles = holes.map {
            Hole(number: $0.number, par: $0.par, handicapIndex: $0.strokeIndex,
                 path: [], green: [], usesPointOnlyGeometry: true)
        }
        let course = Course(name: reference.courseName, holes: courseHoles, fetchedAt: date)
        var scores: [String: PlayedHoleScore] = [:]
        for (key, value) in payload.scores {
            guard let fairway = RoundFairway(rawValue: value.fairway) else { throw AccountSyncError.invalidWire }
            scores[key] = PlayedHoleScore(strokes: value.strokes, putts: value.putts,
                fairway: fairway, bunkerShots: value.bunkerShots, penalties: value.penalties)
        }
        let round = PlayedRound(id: recordID, date: date, reference: reference, course: course,
            holes: holes, players: payload.players.map {
                RoundPlayer(id: $0.id, name: $0.name, isOwner: $0.isOwner,
                    handicapIndex: $0.handicapIndex, keepsDetailedScore: $0.keepsDetailedScore)
            }, game: game, detailMode: detailMode, allowance: payload.allowance,
            scores: scores, displayOptions: nil, notes: payload.notes)
        guard PlayedRoundStore.validStructure(round) else { throw AccountSyncError.invalidWire }
        return round
    }

    private static func encodePayload<Value: Encodable>(_ value: Value) throws -> [String: JSONValue] {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch { throw AccountSyncError.invalidWire }
    }

    private static func decodePayload<Value: Decodable>(_ type: Value.Type,
                                                         from payload: [String: JSONValue]) throws -> Value {
        do { return try JSONDecoder().decode(type, from: JSONEncoder().encode(payload)) }
        catch { throw AccountSyncError.invalidWire }
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        return standard.date(from: value)
    }

    private static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func deterministicID(ownerID: UUID, namespace: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("\(ownerID.uuidString.lowercased()):\(namespace)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }
        let text = "\(hex[0...3].joined())-\(hex[4...5].joined())-\(hex[6...7].joined())-\(hex[8...9].joined())-\(hex[10...15].joined())"
        return UUID(uuidString: text)!
    }
}
