import Foundation

enum GettingStartedProgress {
    /// Own carry or launch data for any club, or an entered full-swing carry for a wedge in the bag.
    static func clubDistancesEntered(profile: TrajectoryPlayerProfile, wedges: [Wedge]) -> Bool {
        let clubData = profile.clubOverrides.values.contains { override in
            [override.carryDistanceM, override.ballSpeedMps, override.launchAngleDeg,
             override.spinRateRpm, override.spinAxisDeg].contains { $0?.isFinite == true }
        }
        let wedgeData = wedges.contains {
            $0.isInBag && ($0.fullCarryUserProvided || $0.overrideCarry(for: .stock, swing: .full) != nil)
        }
        return clubData || wedgeData
    }
}
