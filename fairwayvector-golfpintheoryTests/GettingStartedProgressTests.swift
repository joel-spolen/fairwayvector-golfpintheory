import Foundation
import Testing
@testable import fairwayvector_golfpintheory

@MainActor
struct GettingStartedProgressTests {
    @Test func defaultProfileHasNoClubDistances() {
        #expect(!GettingStartedProgress.clubDistancesEntered(profile: TrajectoryPlayerProfile(), wedges: Wedge.defaults))
    }

    @Test func enteredCarryOrLaunchDataCounts() {
        let carry = TrajectoryPlayerProfile(clubOverrides: [.sevenIron: ClubLaunchOverride(carryDistanceM: 140)])
        let launch = TrajectoryPlayerProfile(clubOverrides: [.driver: ClubLaunchOverride(ballSpeedMps: 65)])
        #expect(GettingStartedProgress.clubDistancesEntered(profile: carry, wedges: []))
        #expect(GettingStartedProgress.clubDistancesEntered(profile: launch, wedges: []))
    }

    @Test func onlyEnteredWedgesInTheBagCount() {
        var entered = Wedge(name: "56", fullCarry: 90, isInBag: true, fullCarryUserProvided: true)
        #expect(GettingStartedProgress.clubDistancesEntered(profile: TrajectoryPlayerProfile(), wedges: [entered]))
        entered.isInBag = false
        #expect(!GettingStartedProgress.clubDistancesEntered(profile: TrajectoryPlayerProfile(), wedges: [entered]))
        var matrixCell = Wedge(name: "52", fullCarry: 100)
        matrixCell.setCarry(98, for: .stock, swing: .full)
        #expect(GettingStartedProgress.clubDistancesEntered(profile: TrajectoryPlayerProfile(), wedges: [matrixCell]))
    }
}
