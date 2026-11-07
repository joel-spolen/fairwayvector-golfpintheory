#if DEBUG
import Foundation
import SwiftData

@MainActor
enum ShowcaseDataInstaller {
    static let launchArgument = "-install-showcase-data"
    static let installedKey = "showcase.demoDataInstalled.v1"
    private static let showcaseNote = "Showcase sample · fictional course and score"

    private struct Venue {
        let club: String
        let course: String
        let city: String
        let rating: Double
        let slope: Int
        let pars: [Int]
        let frontLatitude: Double
        let longitude: Double
    }

    private static let pars = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5]
    private static let indices = [5, 13, 17, 1, 7, 11, 15, 3, 9, 6, 14, 18, 2, 8, 12, 16, 4, 10]
    private static let venues = [
        Venue(club: "Northstar Golf Club", course: "Pine Ridge", city: "Demo City", rating: 72.0, slope: 130,
              pars: pars, frontLatitude: 39.74, longitude: -104.98),
        Venue(club: "Silver Creek Golf Club", course: "Silver Creek", city: "Demo City", rating: 71.4, slope: 126,
              pars: [4, 4, 5, 3, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4], frontLatitude: 39.76, longitude: -104.93)
    ]

    static let clubsInBag: Set<TrajectoryGolfClub> = [
        .driver, .threeWood, .fiveWood, .fourHybrid, .fiveIron, .sixIron, .sevenIron, .eightIron, .nineIron,
        .pitchingWedge, .approachWedge, .gapWedge, .sandWedge, .lobWedge
    ]

    static func makeRounds(startDate: Date = Date(timeIntervalSince1970: 1_767_225_600), ownerName: String = "Alex Morgan") -> [PlayedRound] {
        (0..<40).map { index in
            let venue = venues[index % venues.count]
            let grossOffset = [12, 9, 15, 7, 11, 8, 14, 10, 6, 13][index % 10] + (index / 10 - 1)
            let course = makeCourse(venue)
            var reference = CourseReference(osmRelationID: 0, name: venue.course)
            reference.clubName = venue.club
            reference.courseName = venue.course
            reference.city = venue.city
            reference.region = "Colorado (showcase data)"
            reference.location = GeoPoint(lat: venue.frontLatitude, lon: venue.longitude)
            reference.holeCount = 18
            reference.totalPar = venue.pars.reduce(0, +)
            reference.teeName = "Blue · Demo"
            reference.teeSex = "male"
            reference.courseRating = venue.rating
            reference.slopeRating = venue.slope

            let owner = RoundPlayer(id: deterministicID(index: index), name: ownerName, isOwner: true, handicapIndex: 6.0,
                                    keepsDetailedScore: true)
            var round = PlayedRound(id: deterministicID(index: index),
                date: startDate.addingTimeInterval(Double(index) * 8 * 86_400),
                reference: reference, course: course,
                holes: course.holes.map { PlayedHole(number: $0.number, par: $0.par, strokeIndex: $0.handicapIndex) },
                players: [owner], game: index.isMultiple(of: 3) ? .stableford : .strokePlay,
                detailMode: .detailed, displayOptions: .courseViewDefault,
                notes: showcaseNote)

            var adjustments = (0..<18).map { hole in
                let pattern = (hole * 7 + index * 3) % 13
                return pattern == 0 ? -1 : pattern < 5 ? 0 : pattern < 10 ? 1 : 2
            }
            let difference = grossOffset - adjustments.reduce(0, +)
            if difference > 0 {
                for n in 0..<difference {
                    adjustments[(n * 5 + index) % 18] += 1
                }
            } else if difference < 0 {
                for n in 0..<(-difference) {
                    adjustments[(n * 5 + index) % 18] -= 1
                }
            }
            for hole in 0..<18 {
                let par = venue.pars[hole]
                let strokes = min(9, max(1, par + adjustments[hole]))
                let fairway: RoundFairway = par == 3 ? .notApplicable : ((hole + index) % 5 == 0 ? .missed : .hit)
                let penalties = (hole + index * 2) % 17 == 0 ? 1 : 0
                let putts = min(strokes - penalties, [1, 2, 2, 2, 3, 2][(hole + index) % 6])
                round.setScore(PlayedHoleScore(strokes: strokes, putts: putts, fairway: fairway,
                                               bunkerShots: (hole * 3 + index) % 11 == 0 ? 1 : 0,
                                               penalties: penalties), player: owner.id, hole: hole + 1)
            }
            return round
        }
    }

    static func makeProfile() -> TrajectoryPlayerProfile {
        let carry: [TrajectoryGolfClub: Double] = [
            .driver: 220, .threeWood: 205, .fiveWood: 190, .fourHybrid: 180,
            .fiveIron: 170, .sixIron: 160, .sevenIron: 150, .eightIron: 140, .nineIron: 130,
            .pitchingWedge: 115, .approachWedge: 103, .gapWedge: 92, .sandWedge: 80, .lobWedge: 65
        ]
        var overrides: [TrajectoryGolfClub: ClubLaunchOverride] = [:]
        for club in clubsInBag {
            let distance = carry[club] ?? 100
            let ratio = distance / 220
            let launch: Double
            let spin: Double
            if club == .driver { launch = 12.5; spin = 2_500 }
            else if club.isWedge { launch = 29 - (115 - distance) * 0.13; spin = 8_500 + (115 - distance) * 18 }
            else { launch = 17 + (220 - distance) * 0.07; spin = 3_000 + (220 - distance) * 35 }
            overrides[club] = ClubLaunchOverride(carryDistanceM: distance,
                ballSpeedMps: 65 * ratio.squareRoot(), launchAngleDeg: launch,
                spinRateRpm: spin, spinAxisDeg: Double((club.rawValue.count % 3) - 1) * 0.4)
        }
        return TrajectoryPlayerProfile(isSetupComplete: true, detailLevel: .expert, handicapBand: .fiveToTen,
            exactHandicap: 6.0, driverCarryM: 220, sevenIronCarryM: 150,
            clubOverrides: overrides, availableClubs: clubsInBag)
    }

    static func makeWedges() -> [Wedge] {
        let distances: [(String, Double)] = [("PW", 115), ("AW", 103), ("GW", 92), ("SW", 80), ("LW", 65)]
        return distances.map { name, base in
            var wedge = Wedge(name: name, brand: "Showcase", notes: "Fictional 6-handicap sample",
                              fullCarry: base, isInBag: true, fullCarryUserProvided: true)
            for trajectory in WedgeTrajectory.allCases {
                for swing in SwingLength.allCases {
                    wedge.setCarry(trajectory.adjustedDistance(for: base * swing.factor), for: trajectory, swing: swing)
                }
            }
            return wedge
        }
    }

    static func install(accountData: PinTheoryAccountData, roundStore: PlayedRoundStore,
                        profileStore: PlayerProfileStore, context: ModelContext) throws {
        guard roundStore.active == nil else { throw RoundStorageError.activeDraft }
        let isFirstInstall = !accountData.defaults.bool(forKey: installedKey)
        let rounds = makeRounds()
        guard rounds.count == 40, rounds.allSatisfy(PlayedRoundStore.validStructure) else {
            throw RoundStorageError.invalidArchive
        }

        if isFirstInstall {
            for venue in venues {
                let clubName = venue.club
                let courseName = venue.course
                let teeName = "Blue · Demo"
                if try context.fetch(FetchDescriptor<GolfClub>(predicate: #Predicate { $0.name == clubName })).isEmpty {
                    context.insert(GolfClub(name: venue.club, city: venue.city, country: "United States", isCustom: true))
                }
                if try context.fetch(FetchDescriptor<GolfCourse>(predicate: #Predicate { $0.name == courseName })).isEmpty {
                    context.insert(GolfCourse(clubName: venue.club, name: venue.course, isCustom: true))
                }
                if try context.fetch(FetchDescriptor<TeeSet>(predicate: #Predicate { $0.courseName == courseName && $0.name == teeName })).isEmpty {
                    context.insert(TeeSet(clubName: venue.club, courseName: venue.course, name: teeName,
                        holes: 18, par: venue.pars.reduce(0, +), courseRating: venue.rating, slopeRating: venue.slope,
                        ratingSexRawValue: PlayerSex.male.rawValue, isCustom: true, holeParsData: venue.pars,
                        holeHandicapIndicesData: Self.indices))
                }
            }
            if try context.fetch(FetchDescriptor<PlayerProfile>()).isEmpty {
                context.insert(PlayerProfile(name: "Alex Morgan", lowHandicapIndex: 5.8,
                    selectedCountry: "United States", defaultInputModeRawValue: RoundInputMode.holeByHole.rawValue,
                    sexRawValue: PlayerSex.male.rawValue))
            }
            try context.save()
            try roundStore.addShowcaseRounds(rounds)
            profileStore.update { $0 = makeProfile() }
            profileStore.storedWedgeSetup = encode(makeWedges())
            for club in clubsInBag {
                profileStore.markWedgeSaved(name: club.label)
            }
            profileStore.markClubProfileSaved()
        }

        // Recreate only the 30 demo-derived handicap rows, never unrelated user history.
        let sourceIDs = Set(rounds.prefix(30).map { $0.id.uuidString })
        let handicapContext = ModelContext(accountData.modelContainer)
        let existingHCP = try handicapContext.fetch(FetchDescriptor<GolfRound>())
        for existing in existingHCP where existing.sourceSavedRoundID.map(sourceIDs.contains) == true
            || existing.notes == showcaseNote {
            handicapContext.delete(existing)
        }
        try handicapContext.save()
        for round in rounds.prefix(30) {
            handicapContext.insert(try PlayedRoundHandicapBridge.makeHandicapRound(round))
        }
        try handicapContext.save()
        let persistedShowcaseEntries = try handicapContext.fetch(FetchDescriptor<GolfRound>())
            .filter { $0.sourceSavedRoundID.map(sourceIDs.contains) == true }.count
        guard persistedShowcaseEntries == 30 else { throw RoundStorageError.saveFailed }

        accountData.defaults.set(false, forKey: "accountSync.savedRecordsOptIn.v1")
        accountData.defaults.set(true, forKey: installedKey)
    }

    private static func makeCourse(_ venue: Venue) -> Course {
        let holes = (1...18).map { number -> Hole in
            let column = Double((number - 1) % 6) * 0.0014
            let row = Double((number - 1) / 6) * 0.0015
            let tee = GeoPoint(lat: venue.frontLatitude - 0.012 - row, lon: venue.longitude + column)
            let green = GeoPoint(lat: venue.frontLatitude - 0.001 - row, lon: venue.longitude + column + 0.0002)
            return Hole(number: number, par: venue.pars[number - 1], handicapIndex: indices[number - 1],
                        path: [tee, green], green: [], greenCenterPoint: green, usesPointOnlyGeometry: true)
        }
        return Course(name: venue.course, holes: holes, fetchedAt: .now)
    }

    private static func deterministicID(index: Int) -> UUID {
        let tail = String(format: "%012d", index + 1)
        return UUID(uuidString: "d3e00000-0000-4000-8000-\(tail)")!
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
