import SwiftData
import SwiftUI

struct SharedHandicapSync: View {
    @Query private var profiles: [PlayerProfile]
    @Query(sort: \GolfRound.date, order: .reverse) private var rounds: [GolfRound]
    @ObservedObject var trajectoryModel: TrajectoryCalculatorViewModel
    private var handicapIndex: Double? {
        let entries = WHSCalculator.scoringEntries(from: rounds, lowHandicapIndex: profiles.first?.lowHandicapIndex)
        return WHSCalculator.handicapIndex(from: entries, lowHandicapIndex: profiles.first?.lowHandicapIndex)
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: sync)
            .onChange(of: handicapIndex) { _, _ in sync() }
    }

    private func sync() {
        guard let handicapIndex else { return }
        let band = HandicapBand.forHandicap(handicapIndex)
        let profileStore = trajectoryModel.playerProfileStore
        guard profileStore.profile.exactHandicap != handicapIndex || profileStore.profile.handicapBand != band || !profileStore.profile.isSetupComplete else { return }
        profileStore.update {
            $0.handicapBand = band
            $0.exactHandicap = handicapIndex
            $0.isSetupComplete = true
        }
    }
}

extension HandicapBand {
    static func forHandicap(_ value: Double) -> HandicapBand {
        switch value {
        case ..<0: .plusToZero
        case ..<5: .zeroToFive
        case ..<10: .fiveToTen
        case ..<15: .tenToFifteen
        case ..<20: .fifteenToTwenty
        case ..<25: .twentyToTwentyFive
        case ..<35: .twentyFiveToThirtyFive
        default: .thirtyFivePlus
        }
    }
}
