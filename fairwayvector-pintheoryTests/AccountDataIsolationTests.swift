import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import fairwayvector_pintheory

/// Offline regression SOURCE ONLY. No provider access or test execution authorized.
@MainActor
struct AccountDataIsolationTests {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("account-data-\(UUID().uuidString)", isDirectory: true)
    }

    private func clean(_ accounts: [PinTheoryAccountData], root: URL) {
        for account in accounts {
            account.defaults.removePersistentDomain(forName: account.defaultsSuiteName)
        }
        try? FileManager.default.removeItem(at: root)
    }

    @Test func identityAndAllContentStoresSeparateUsersAndProjects() throws {
        let root = root()
        let user = UUID()
        let a = try PinTheoryAccountData(projectHost: "a.example.test", userID: user, root: root)
        let b = try PinTheoryAccountData(projectHost: "a.example.test", userID: UUID(), root: root)
        let otherProject = try PinTheoryAccountData(projectHost: "b.example.test", userID: user, root: root)
        defer { clean([a, b, otherProject], root: root) }
        #expect(Set([a.id, b.id, otherProject.id]).count == 3)
        #expect(Set([a.directory, b.directory, otherProject.directory]).count == 3)
        #expect(Set([a.defaultsSuiteName, b.defaultsSuiteName, otherProject.defaultsSuiteName]).count == 3)
        #expect(a.roundsURL.deletingLastPathComponent() == a.directory)

        let profile = PlayerProfileStore(userDefaults: a.defaults)
        profile.update { $0.isSetupComplete = true; $0.exactHandicap = 7.2 }
        a.defaults.set("A flags", forKey: "customFlagPositions")
        a.defaults.set(Data("A recent".utf8), forKey: "map.recentCourseReference")
        let context = ModelContext(a.modelContainer)
        context.autosaveEnabled = false
        context.insert(PlayerProfile(name: "Account A"))
        try context.save()

        for account in [b, otherProject] {
            #expect(!PlayerProfileStore(userDefaults: account.defaults).profile.isSetupComplete)
            #expect(account.defaults.string(forKey: "customFlagPositions") == "")
            #expect(account.defaults.data(forKey: "map.recentCourseReference") == Data())
            #expect(try ModelContext(account.modelContainer).fetchCount(FetchDescriptor<PlayerProfile>()) == 0)
            #expect(PlayedRoundStore(url: account.roundsURL).saved.isEmpty)
        }

        let reopened = try PinTheoryAccountData(projectHost: " A.EXAMPLE.TEST ", userID: user, root: root)
        #expect(reopened.id == a.id)
        #expect(reopened.directory == a.directory)
        #expect(PlayerProfileStore(userDefaults: reopened.defaults).profile.exactHandicap == 7.2)
        #expect(reopened.defaults.string(forKey: "customFlagPositions") == "A flags")
        #expect(try ModelContext(reopened.modelContainer).fetch(FetchDescriptor<PlayerProfile>()).first?.name == "Account A")
    }

    @Test func freshAccountsMaskEveryLegacyContentKeyWithoutModifyingLegacyOrPreferences() throws {
        let legacy: [String: Any] = [
            "playerProfile.active": try JSONEncoder().encode(TrajectoryPlayerProfile(isSetupComplete: true)),
            "wedgeMatrix.wedges": String(decoding: try JSONEncoder().encode([
                Wedge(name: "PW", fullCarry: 999, fullCarryUserProvided: true),
            ]), as: UTF8.self),
            "customFlagPositions": "legacy flags",
            "map.recentCourseReference": Data("legacy map".utf8),
            "map.development.recentCourseReference.v1": Data("legacy development".utf8),
            "hcp.provider.recentCourseReference.v1": Data("legacy HCP".utf8),
        ]
        let keys = Array(legacy.keys) + ["distanceUnit", "wedgeMatrix.distanceUnit", "unitPreferences.overrides"]
        let standard = UserDefaults.standard
        let old = Dictionary(uniqueKeysWithValues: keys.map { ($0, standard.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = old[key] ?? nil { standard.set(value, forKey: key) }
                else { standard.removeObject(forKey: key) }
            }
        }
        for (key, value) in legacy { standard.set(value, forKey: key) }
        standard.set("yards", forKey: "distanceUnit")
        standard.set("yards", forKey: "wedgeMatrix.distanceUnit")
        standard.set("{\"distance\":\"imperial\"}", forKey: "unitPreferences.overrides")

        let root = root()
        let account = try PinTheoryAccountData(projectHost: "legacy.example.test", userID: UUID(), root: root)
        defer { clean([account], root: root) }
        #expect(account.defaults.data(forKey: "playerProfile.active") == Data())
        #expect(!PlayerProfileStore(userDefaults: account.defaults).profile.isSetupComplete)
        let club = try #require(TrajectoryGolfClub.wedge(named: "PW"))
        let baseline = ClubProfileDefaults.effectiveProfile(for: club, playerProfile: TrajectoryPlayerProfile())
        #expect(baseline.carryDistanceM.value != Units.metersFromYards(999))
        for key in ["wedgeMatrix.wedges", "customFlagPositions"] {
            #expect(account.defaults.string(forKey: key) == "")
        }
        for key in ["map.recentCourseReference", "map.development.recentCourseReference.v1", "hcp.provider.recentCourseReference.v1"] {
            #expect(account.defaults.data(forKey: key) == Data())
        }
        let domain = try #require(account.defaults.persistentDomain(forName: account.defaultsSuiteName))
        #expect(legacy.keys.allSatisfy { domain[$0] != nil })
        #expect(domain["distanceUnit"] == nil)
        #expect(domain["wedgeMatrix.distanceUnit"] == nil)
        #expect(domain["unitPreferences.overrides"] == nil)
        for (key, value) in legacy {
            #expect((standard.object(forKey: key) as? NSObject) == (value as? NSObject))
        }
        #expect(standard.string(forKey: "distanceUnit") == "yards")
        #expect(standard.string(forKey: "unitPreferences.overrides") == "{\"distance\":\"imperial\"}")
    }

    @Test func profileAndWedgeCalculationsUseOnlyTheInjectedAccount() throws {
        let root = root()
        let a = try PinTheoryAccountData(projectHost: "wedge.example.test", userID: UUID(), root: root)
        let b = try PinTheoryAccountData(projectHost: "wedge.example.test", userID: UUID(), root: root)
        defer { clean([a, b], root: root) }
        let wedgeA = Wedge(name: "PW", fullCarry: 120, fullCarryUserProvided: true)
        let wedgeB = Wedge(name: "PW", fullCarry: 70, isInBag: false, fullCarryUserProvided: true)
        a.defaults.set(String(decoding: try JSONEncoder().encode([wedgeA]), as: UTF8.self), forKey: "wedgeMatrix.wedges")
        b.defaults.set(String(decoding: try JSONEncoder().encode([wedgeB]), as: UTF8.self), forKey: "wedgeMatrix.wedges")
        let storeA = PlayerProfileStore(userDefaults: a.defaults)
        let storeB = PlayerProfileStore(userDefaults: b.defaults)
        let club = try #require(TrajectoryGolfClub.wedge(named: "PW"))
        #expect(storeA.isAvailable(for: club))
        #expect(!storeB.isAvailable(for: club))
        #expect(abs(storeA.effectiveProfile(for: club).carryDistanceM.value - Units.metersFromYards(120)) < 0.0001)
        storeA.update { $0.isSetupComplete = true; $0.exactHandicap = 3 }
        #expect(storeB.profile.exactHandicap == nil)
        // Injection remains compatible with the existing VM initializer; last
        // calculator conditions can use a separate device/test defaults store.
        let model = TrajectoryCalculatorViewModel(playerProfileStore: storeA, userDefaults: b.defaults)
        #expect(model.playerProfileStore === storeA)
        model.playerProfileStore.update { $0.exactHandicap = 4 }
        #expect(PlayerProfileStore(userDefaults: a.defaults).profile.exactHandicap == 4)
        #expect(PlayerProfileStore(userDefaults: b.defaults).profile.exactHandicap == nil)
    }

    @Test func savedRoundsAndDraftsReopenOnlyForTheirOwner() throws {
        let root = root()
        let a = try PinTheoryAccountData(projectHost: "rounds.example.test", userID: UUID(), root: root)
        let b = try PinTheoryAccountData(projectHost: "rounds.example.test", userID: UUID(), root: root)
        defer { clean([a, b], root: root) }
        var reference = CourseReference(osmRelationID: 42, name: "Offline isolation fixture")
        reference.holeCount = 9; reference.totalPar = 36
        reference.courseRating = 36; reference.slopeRating = 113
        let holes = (1...9).map { Hole(number: $0, par: 4, handicapIndex: $0, path: [], green: []) }
        let course = Course(osmRelationID: 42, name: reference.courseName, holes: holes, fetchedAt: .now)
        let round = PlayedRound(reference: reference, course: course,
            holes: holes.map { PlayedHole(number: $0.number, par: $0.par, strokeIndex: $0.handicapIndex) },
            players: [RoundPlayer(name: "You", isOwner: true, handicapIndex: 10)], game: .stableford, detailMode: .detailed)
        let store = PlayedRoundStore(url: a.roundsURL)
        try store.start(round)
        #expect(PlayedRoundStore(url: a.roundsURL).active?.id == round.id)
        #expect(PlayedRoundStore(url: b.roundsURL).active == nil)
        try store.saveActive(allowIncomplete: true)
        #expect(PlayedRoundStore(url: a.roundsURL).saved.first?.id == round.id)
        #expect(PlayedRoundStore(url: b.roundsURL).saved.isEmpty)
    }

    @Test func invalidOrUnavailableStorageFailsClosedAndPreservesBytes() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: PinTheoryAccountData.StorageError.self) {
            try PinTheoryAccountData(projectHost: "../legacy", userID: UUID(), root: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocker = root.appendingPathComponent("blocked")
        let preserved = Data("preserve this file".utf8)
        try preserved.write(to: blocker)
        #expect(throws: (any Error).self) {
            try PinTheoryAccountData(projectHost: "storage.example.test", userID: UUID(), root: blocker)
        }
        #expect(try Data(contentsOf: blocker) == preserved)

        let user = UUID()
        let host = "corrupt.example.test"
        let hash = SHA256.hash(data: Data(host.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = root.appendingPathComponent(hash).appendingPathComponent(user.uuidString.lowercased())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("hcp.store")
        try preserved.write(to: storeURL)
        #expect(throws: (any Error).self) {
            try PinTheoryAccountData(projectHost: host, userID: user, root: root)
        }
        #expect(try Data(contentsOf: storeURL) == preserved)
    }
}