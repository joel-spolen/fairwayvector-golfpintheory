#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import fairwayvector_golfpintheory

@MainActor
struct ShowcaseDataTests {
    @Test func showcaseInstallerPopulatesOnlyTheLocalDemoAccount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("showcase-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let account = try PinTheoryAccountData(projectHost: "showcase.local", userID: UUID(), root: root)
        let rounds = PlayedRoundStore(url: account.roundsURL)
        let profile = PlayerProfileStore(userDefaults: account.defaults)
        let context = ModelContext(account.modelContainer)

        try ShowcaseDataInstaller.install(accountData: account, roundStore: rounds, profileStore: profile, context: context)
        #expect(rounds.saved.count == 40)
        #expect(try context.fetch(FetchDescriptor<GolfRound>()).count == 30)
        #expect(try context.fetch(FetchDescriptor<GolfCourse>()).filter { $0.isCustom == true }.count == 2)
        #expect(profile.profile.detailLevel == .expert && profile.profile.exactHandicap == 6)
        #expect(!account.defaults.bool(forKey: "accountSync.savedRecordsOptIn.v1"))

        try ShowcaseDataInstaller.install(accountData: account, roundStore: rounds, profileStore: profile, context: context)
        #expect(rounds.saved.count == 40)
        #expect(try context.fetch(FetchDescriptor<GolfRound>()).count == 30)
    }

    @Test func showcaseHasFortyFictionalRoundsWithOnlyThirtyHCPEntries() throws {
        let rounds = ShowcaseDataInstaller.makeRounds(startDate: Date(timeIntervalSince1970: 1_767_225_600))
        let repeated = ShowcaseDataInstaller.makeRounds(startDate: Date(timeIntervalSince1970: 1_767_225_600))
        #expect(rounds.count == 40)
        #expect(rounds.map(\.id) == repeated.map(\.id))
        #expect(rounds.allSatisfy(PlayedRoundStore.validStructure))
        #expect(rounds.allSatisfy { $0.reference.golfAPICourseID == nil })
        #expect(Set(rounds.map(\.reference.courseName)) == ["Pine Ridge", "Silver Creek"])
        #expect(rounds.allSatisfy(PlayedRoundHandicapBridge.isEligible))
        let handicapEntries = try rounds.prefix(30).map(PlayedRoundHandicapBridge.makeHandicapRound)
        #expect(handicapEntries.count == 30)
        #expect(handicapEntries.allSatisfy { $0.holeScores?.count == 18 && $0.holePars?.count == 18 })
        #expect(rounds.suffix(10).allSatisfy { round in
            !handicapEntries.contains { $0.sourceSavedRoundID == round.id.uuidString }
        })
    }

    @Test func showcaseBagHasCompleteAdvancedProfilesAndWedgeMatrix() {
        let profile = ShowcaseDataInstaller.makeProfile()
        #expect(profile.detailLevel == .expert)
        #expect(profile.exactHandicap == 6)
        #expect(profile.availableClubs.count == 14)
        #expect(profile.availableClubs.allSatisfy { club in
            let value = profile.override(for: club)
            return value.carryDistanceM != nil && value.ballSpeedMps != nil && value.launchAngleDeg != nil
                && value.spinRateRpm != nil && value.spinAxisDeg != nil
        })
        let wedges = ShowcaseDataInstaller.makeWedges()
        #expect(wedges.count == 5 && wedges.allSatisfy(\.isInBag))
        #expect(wedges.allSatisfy { wedge in
            WedgeTrajectory.allCases.allSatisfy { trajectory in
                SwingLength.allCases.allSatisfy { wedge.overrideCarry(for: trajectory, swing: $0) != nil }
            }
        })
    }
}
#endif
