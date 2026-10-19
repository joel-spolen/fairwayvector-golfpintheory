import Foundation

/// Immutable reference launch specifications. Wedge Matrix has carry only, not
/// measured low/high launch or partial-shot spin. These assumptions stay explicit.
nonisolated struct ScoringShotSpec: Equatable, Sendable, Identifiable {
    let id: String
    let club: TrajectoryGolfClub
    let title: String
    let nominalCarryM: Double
    let launchAngleDeg: Double
    let spinRateRpm: Double
    let spinAxisDeg: Double
    let source: String
}

struct ScoringShotPlan: Equatable {
    let shots: [ScoringShotSpec]
    let maxFullCarryM: Double?
    let guidance: String

    func isScoring(distanceM: Double) -> Bool {
        guard let maxFullCarryM else { return false }
        return distanceM.isFinite && distanceM > 0 && distanceM <= maxFullCarryM
    }

    static let wedgeClubs: [TrajectoryGolfClub] = TrajectoryGolfClub.allCases.filter(\.isWedge)

    static func club(named name: String) -> TrajectoryGolfClub? {
        TrajectoryGolfClub.wedge(named: name)
    }

    static func make(profile: TrajectoryPlayerProfile, wedges: [Wedge]) -> Self {
        let matrixBag = wedges.filter(\.isInBag)
        guard matrixBag.count <= 14 else {
            return Self(shots: [], maxFullCarryM: nil, guidance: "Scoring supports at most 14 in-bag wedges. Reduce the Wedge Matrix bag.")
        }
        guard Set(matrixBag.map(\.id)).count == matrixBag.count else {
            return Self(shots: [], maxFullCarryM: nil, guidance: "Duplicate Wedge Matrix identities: recreate duplicate entries before scoring. Shot identities must be unique.")
        }
        var shots: [ScoringShotSpec] = []
        var fullCarries: [Double] = []
        var issues: [String] = []
        // Explicit out-of-bag matrix entries are authoritative; unverified
        // defaults must not hide a valid effective Practice calibration.
        let mapped = Set(wedges.filter {
            !$0.isInBag || $0.fullCarryUserProvided || $0.overrideCarry(for: .stock, swing: .full) != nil
        }.compactMap { club(named: $0.name) })

        func append(id: String, name: String, club: TrajectoryGolfClub, fullM: Double, matrix: Wedge?) {
            let launch = ClubProfileDefaults.effectiveProfile(for: club, playerProfile: profile)
            guard fullM.isFinite, fullM > 0,
                  launch.launchAngleDeg.value.isFinite, (0...75).contains(launch.launchAngleDeg.value),
                  launch.spinRateRpm.value.isFinite, launch.spinRateRpm.value >= 0,
                  launch.spinAxisDeg.value.isFinite else { return }
            let validCells = WedgeTrajectory.allCases.allSatisfy { trajectory in
                SwingLength.allCases.allSatisfy { swing in
                    let carry = matrix?.overrideCarry(for: trajectory, swing: swing).map { $0 * 0.9144 }
                        ?? trajectory.adjustedDistance(for: fullM * swing.factor)
                    return carry.isFinite && carry > 0
                }
            }
            guard validCells else {
                issues.append("Review invalid carry cells for \(name); this wedge is excluded, not replaced by defaults.")
                return
            }
            fullCarries.append(fullM)
            for trajectory in WedgeTrajectory.allCases {
                for swing in SwingLength.allCases {
                    let entered = matrix?.overrideCarry(for: trajectory, swing: swing)
                    let nominal = entered.map { $0 * 0.9144 }
                        ?? trajectory.adjustedDistance(for: fullM * swing.factor)
                    guard nominal.isFinite, nominal > 0 else { continue }
                    let label = trajectory == .stock ? "Mid" : trajectory.title
                    let strength = swing == .full ? "100%" : swing.title
                    // No existing measured transformation exists: ±6° is an
                    // explicitly modeled shape, NOT a launch-monitor calibration.
                    let delta = trajectory == .knockdown ? -6.0 : (trajectory == .high ? 6.0 : 0)
                    let angle = min(80, max(5, launch.launchAngleDeg.value + delta))
                    let carrySource = entered != nil ? "Entered Wedge Matrix cell carry"
                        : (matrix != nil ? "User Wedge Matrix full carry" : "Effective user-calibrated Practice wedge carry")
                    shots.append(ScoringShotSpec(id: "\(id).\(trajectory.rawValue).\(swing.rawValue)",
                        club: club, title: "\(name) · \(label) · \(strength)", nominalCarryM: nominal,
                        launchAngleDeg: angle, spinRateRpm: launch.spinRateRpm.value,
                        spinAxisDeg: launch.spinAxisDeg.value,
                        source: "\(carrySource)\(entered == nil ? "; estimated cell: swing ×\(swing.factor), flight ×\(trajectory.adjustedDistance(for: 1))" : ""). Launch: effective profile \(launch.launchAngleDeg.source.rawValue), Low/Mid/High −6°/0°/+6° (clamped 5–80°); spin/axis retained from effective profile (\(launch.spinRateRpm.source.rawValue)/\(launch.spinAxisDeg.source.rawValue)), not measured partial-shot data."))
                }
            }
        }

        for wedge in matrixBag {
            guard let club = club(named: wedge.name) else {
                issues.append("Map \(wedge.name) to PW, AW/48, GW/50, 52, SW/54, 56, 58 or LW/60; unknown loft is not guessed.")
                continue
            }
            let entered = wedge.overrideCarry(for: .stock, swing: .full)
            guard entered != nil || wedge.fullCarryUserProvided else {
                issues.append("Enter Mid/Stock Full carry for \(wedge.name) in Wedge Matrix; legacy/default full carries are unverified.")
                continue
            }
            append(id: wedge.id.uuidString, name: wedge.name, club: club,
                   fullM: (entered ?? wedge.fullCarry) * 0.9144, matrix: wedge)
        }
        for club in wedgeClubs where profile.availableClubs.contains(club) && !mapped.contains(club) {
            let effective = ClubProfileDefaults.effectiveProfile(for: club, playerProfile: profile)
            guard effective.carryDistanceM.source != .baseline else { continue }
            append(id: club.rawValue, name: club.label, club: club,
                   fullM: effective.carryDistanceM.value, matrix: nil)
        }
        // Fail closed instead of an unbounded user-created bag or silent truncation.
        if fullCarries.count > 14 {
            return Self(shots: [], maxFullCarryM: nil, guidance: "Scoring supports at most 14 in-bag wedges. Reduce the Wedge Matrix bag.")
        }
        if fullCarries.isEmpty {
            issues.insert("Scoring range unavailable: enter a personal full wedge carry in Wedge Matrix or calibrate a Practice wedge. Ordinary full-bag advice remains available; no stock distance threshold is assumed.", at: 0)
        }
        return Self(shots: shots, maxFullCarryM: fullCarries.max(), guidance: issues.joined(separator: " "))
    }
}

nonisolated struct CourseClubRecommendation: Identifiable, Sendable {
    let id: String
    let title: String
    let recommendation: ClubRecommendation
    let scoringShot: ScoringShotSpec?
    let calibratedLaunch: ShotInputs?
}

nonisolated struct UnavailableScoringShot: Identifiable, Sendable {
    let spec: ScoringShotSpec
    let reason: String
    var id: String { spec.id }
}

nonisolated struct ScoringEvaluation: Sendable {
    let recommendations: [CourseClubRecommendation]
    let unavailable: [UnavailableScoringShot]
}

/// Bounded inverse calibration on a background actor; never touches Practice.
actor ScoringRecommendationEngine {
    private var predictor: HybridPredictor?
    private var calibrated: [String: (ScoringShotSpec, ShotInputs)] = [:]
    private let engine = ClubRecommendationEngine()

    func referenceLaunch(for spec: ScoringShotSpec) throws -> ShotInputs {
        try Task.checkCancellation()
        if let cached = calibrated[spec.id], cached.0 == spec { return cached.1 }
        if predictor == nil { predictor = try HybridPredictor() }
        guard let predictor else { throw HybridPredictorError.nonFiniteOutput("Scoring models unavailable") }
        var shot = ShotInputs(ballSpeedMps: 2, launchAngleDeg: spec.launchAngleDeg,
            launchDirectionDeg: 0, spinRateRpm: spec.spinRateRpm, spinAxisDeg: spec.spinAxisDeg)
        // Reference: 20°C, 1013.25 hPa, 50% RH, calm, level. Solve speed,
        // never multiply ball speed by swing percentage or weather-adjust twice.
        func carry(_ speed: Double) throws -> Double {
            try Task.checkCancellation()
            shot.ballSpeedMps = speed
            guard let value = try predictor.predict(shot).hybrid["carry_m"], value.isFinite else {
                throw HybridPredictorError.nonFiniteOutput("Invalid scoring reference carry")
            }
            return value
        }
        var low = 2.0
        var lowCarry = try carry(low)
        var high = low
        var highCarry = lowCarry
        // First crossing within a bounded 2–90 m/s search; does not assume HGB
        // corrections are smooth or globally monotonic.
        for step in 1...16 {
            high = 2 + Double(step) * 5.5
            highCarry = try carry(high)
            if lowCarry <= spec.nominalCarryM && highCarry >= spec.nominalCarryM { break }
            low = high
            lowCarry = highCarry
        }
        guard lowCarry <= spec.nominalCarryM, highCarry >= spec.nominalCarryM else {
            throw HybridPredictorError.nonFiniteOutput("\(spec.title): reference carry cannot be calibrated within 2–90 m/s. Review wedge carry/launch data.")
        }
        var bestSpeed = abs(lowCarry - spec.nominalCarryM) < abs(highCarry - spec.nominalCarryM) ? low : high
        var bestError = min(abs(lowCarry - spec.nominalCarryM), abs(highCarry - spec.nominalCarryM))
        for _ in 0..<14 {
            let speed = (low + high) / 2
            let value = try carry(speed)
            let error = abs(value - spec.nominalCarryM)
            if error < bestError { bestSpeed = speed; bestError = error }
            if value < spec.nominalCarryM { low = speed } else { high = speed }
        }
        guard bestError <= 0.5 else {
            throw HybridPredictorError.nonFiniteOutput("\(spec.title): residual model cannot match entered carry within 0.5 m; no fabricated exact calibration is shown.")
        }
        shot.ballSpeedMps = bestSpeed
        if calibrated.count >= 126 { calibrated.removeAll(keepingCapacity: true) }
        calibrated[spec.id] = (spec, shot)
        return shot
    }

    func recommend(targetM: Double, specs: [ScoringShotSpec], conditions: ShotInputs) async throws -> ScoringEvaluation {
        guard specs.count <= 126 else { throw HybridPredictorError.nonFiniteOutput("Scoring bag exceeds 126 combinations") }
        var results: [(Int, CourseClubRecommendation)] = []
        var unavailable: [UnavailableScoringShot] = []
        for (index, spec) in specs.enumerated() {
            try Task.checkCancellation()
            var shot: ShotInputs
            do {
                shot = try referenceLaunch(for: spec)
            } catch let error as HybridPredictorError {
                guard case .nonFiniteOutput = error else { throw error }
                unavailable.append(UnavailableScoringShot(spec: spec, reason: error.localizedDescription))
                continue
            }
            shot.temperatureC = conditions.temperatureC
            shot.pressureHpa = conditions.pressureHpa
            shot.relativeHumidityPct = conditions.relativeHumidityPct
            shot.windXMps = conditions.windXMps
            shot.windYMps = conditions.windYMps
            shot.targetElevationDeltaM = conditions.targetElevationDeltaM
            do {
                if let recommendation = try await engine.recommend(for: targetM,
                    launches: [RecommendationLaunch(club: spec.club, shot: shot)]).first {
                    results.append((index, CourseClubRecommendation(id: spec.id, title: spec.title,
                        recommendation: recommendation, scoringShot: spec, calibratedLaunch: shot)))
                }
            } catch let error as HybridPredictorError {
                guard case .noClubCanReachTargetElevation = error else { throw error }
                unavailable.append(UnavailableScoringShot(spec: spec, reason: error.localizedDescription))
            }
        }
        try Task.checkCancellation()
        let ranked = results.sorted {
            let left = $0.1.recommendation.differenceM, right = $1.1.recommendation.differenceM
            return left == right ? $0.0 < $1.0 : left < right
        }.map(\.1)
        return ScoringEvaluation(recommendations: ranked, unavailable: unavailable)
    }
}