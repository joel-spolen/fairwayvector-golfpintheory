import Foundation

nonisolated struct RecommendationLaunch: Sendable {
    let club: TrajectoryGolfClub
    let shot: ShotInputs
}

/// Shared Practice/map pipeline. Only immutable launch snapshots cross actors;
/// no profile stores, calculator inputs, persistence or network providers live here.
actor ClubRecommendationEngine {
    private var predictor: HybridPredictor?

    @MainActor static func launches(profile: TrajectoryPlayerProfile,
                                   conditions: ClubRecommendationConditions) throws -> [RecommendationLaunch] {
        let pressure = try conditions.effectivePressureHpa()
        return TrajectoryGolfClub.allCases.filter { ClubProfileDefaults.isAvailable(for: $0, playerProfile: profile) }.map { club in
            let launch = ClubProfileDefaults.effectiveProfile(for: club, playerProfile: profile)
            return RecommendationLaunch(club: club, shot: ShotInputs(
                ballSpeedMps: launch.ballSpeedMps.value,
                launchAngleDeg: launch.launchAngleDeg.value,
                launchDirectionDeg: 0,
                spinRateRpm: launch.spinRateRpm.value,
                spinAxisDeg: launch.spinAxisDeg.value,
                temperatureC: conditions.temperatureC,
                pressureHpa: pressure,
                relativeHumidityPct: conditions.humidityPct,
                windXMps: conditions.tailwindMps,
                windYMps: conditions.crosswindMps,
                targetElevationDeltaM: conditions.elevationDeltaM))
        }
    }

    func recommend(for targetCarryM: Double, launches: [RecommendationLaunch]) throws -> [ClubRecommendation] {
        guard targetCarryM.isFinite, targetCarryM > 0 else { return [] }
        try Task.checkCancellation()
        if predictor == nil { predictor = try HybridPredictor() }
        guard let predictor else { throw HybridPredictorError.nonFiniteOutput("Prediction models failed to load.") }
        var recommendations: [ClubRecommendation] = []
        var highestApexM = 0.0
        for launch in launches {
            try Task.checkCancellation()
            let shot = launch.shot
            guard shot.ballSpeedMps.isFinite, shot.ballSpeedMps > 0,
                  shot.launchAngleDeg.isFinite, shot.spinRateRpm.isFinite, shot.spinRateRpm >= 0,
                  shot.spinAxisDeg.isFinite else {
                throw HybridPredictorError.nonFiniteOutput("Invalid club launch profile; configure Clubs & launch profile.")
            }
            do {
                let prediction = try predictor.predict(shot)
                guard let carryM = prediction.hybrid["carry_m"], carryM.isFinite, carryM > 0 else {
                    throw HybridPredictorError.nonFiniteOutput("Missing or invalid predicted carry; no yardage fallback is used.")
                }
                recommendations.append(ClubRecommendation(
                    club: launch.club, estimatedCarryM: carryM, differenceM: abs(carryM - targetCarryM),
                    trajectory: prediction.physics.trajectory, targetElevationM: shot.targetElevationDeltaM,
                    heightAtTargetDistanceM: Self.value(at: targetCarryM, x: prediction.physics.trajectory.xM,
                                                      values: prediction.physics.trajectory.zM, clamp: false),
                    lateralAtTargetDistanceM: Self.value(at: targetCarryM, x: prediction.physics.trajectory.xM,
                                                       values: prediction.physics.trajectory.yM, clamp: true),
                    prediction: prediction))
            } catch let error as HybridPredictorError {
                if case let .targetElevationExceedsApex(_, apexM) = error {
                    highestApexM = max(highestApexM, apexM)
                    continue
                }
                throw error
            }
        }
        let elevation = launches.first?.shot.targetElevationDeltaM ?? 0
        if recommendations.isEmpty, elevation > 0 {
            throw HybridPredictorError.noClubCanReachTargetElevation(targetM: elevation, highestApexM: highestApexM)
        }
        try Task.checkCancellation()
        // Same absolute hybrid-carry error as Practice; deterministic bag-order ties.
        return recommendations.sorted {
            if $0.differenceM == $1.differenceM {
                return (TrajectoryGolfClub.allCases.firstIndex(of: $0.club) ?? 0)
                    < (TrajectoryGolfClub.allCases.firstIndex(of: $1.club) ?? 0)
            }
            return $0.differenceM < $1.differenceM
        }
    }

    private static func value(at distance: Double, x: [Double], values: [Double], clamp: Bool) -> Double? {
        guard distance >= 0, x.count == values.count, let last = x.last else { return nil }
        guard clamp || distance <= last else { return nil }
        let sampled = min(distance, last)
        for index in 1..<x.count where sampled <= x[index] {
            guard x[index] != x[index - 1] else { return values[index] }
            let fraction = (sampled - x[index - 1]) / (x[index] - x[index - 1])
            return values[index - 1] + (values[index] - values[index - 1]) * fraction
        }
        return values.last
    }
}