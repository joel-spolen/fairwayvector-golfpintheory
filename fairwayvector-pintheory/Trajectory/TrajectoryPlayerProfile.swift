import Foundation

enum HandicapBand: String, Codable, Identifiable {
    case plusToZero
    case zeroToFive
    case fiveToTen
    case tenToFifteen
    case fifteenToTwenty
    case twentyToTwentyFive
    case twentyFiveToThirtyFive
    case thirtyFivePlus
    case twentyFivePlus

    static let allCases: [HandicapBand] = [
        .plusToZero,
        .zeroToFive,
        .fiveToTen,
        .tenToFifteen,
        .fifteenToTwenty,
        .twentyToTwentyFive,
        .twentyFiveToThirtyFive,
        .thirtyFivePlus
    ]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plusToZero: return "+5-0"
        case .zeroToFive: return "0-5"
        case .fiveToTen: return "5-10"
        case .tenToFifteen: return "10-15"
        case .fifteenToTwenty: return "15-20"
        case .twentyToTwentyFive: return "20-25"
        case .twentyFiveToThirtyFive: return "25-35"
        case .thirtyFivePlus: return "35+"
        case .twentyFivePlus: return "25+"
        }
    }

    var midpoint: Double {
        switch self {
        case .plusToZero: return -2.5
        case .zeroToFive: return 2.5
        case .fiveToTen: return 7.5
        case .tenToFifteen: return 12.5
        case .fifteenToTwenty: return 17.5
        case .twentyToTwentyFive: return 22.5
        case .twentyFiveToThirtyFive, .twentyFivePlus: return 30.0
        case .thirtyFivePlus: return 40.0
        }
    }
}

enum ProfileDetailLevel: String, CaseIterable, Codable, Identifiable {
    case easy
    case medium
    case expert

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy: return "Simple"
        case .medium: return "Medium"
        case .expert: return "Advanced"
        }
    }

    var description: String {
        switch self {
        case .easy: return "Use your handicap range."
        case .medium: return "Use driver and 7 iron carry distances."
        case .expert: return "Use per-club carry and launch data."
        }
    }
}

nonisolated enum TrajectoryGolfClub: String, CaseIterable, Codable, Identifiable, Sendable {
    case driver
    case threeWood
    case fourWood
    case fiveWood
    case sixWood
    case sevenWood
    case eightWood
    case nineWood
    case threeHybrid
    case fourHybrid
    case fiveHybrid
    case twoIron
    case threeIron
    case fourIron
    case fiveIron
    case sixIron
    case sevenIron
    case eightIron
    case nineIron
    case pitchingWedge
    case approachWedge
    case gapWedge
    case fiftyTwoWedge
    case sandWedge
    case fiftySixWedge
    case fiftyEightWedge
    case lobWedge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .driver: return "Driver"
        case .threeWood: return "3 Wood"
        case .fourWood: return "4 Wood"
        case .fiveWood: return "5 Wood"
        case .sixWood: return "6 Wood"
        case .sevenWood: return "7 Wood"
        case .eightWood: return "8 Wood"
        case .nineWood: return "9 Wood"
        case .threeHybrid: return "3 Hybrid"
        case .fourHybrid: return "4 Hybrid"
        case .fiveHybrid: return "5 Hybrid"
        case .twoIron: return "2 Iron"
        case .threeIron: return "3 Iron"
        case .fourIron: return "4 Iron"
        case .fiveIron: return "5 Iron"
        case .sixIron: return "6 Iron"
        case .sevenIron: return "7 Iron"
        case .eightIron: return "8 Iron"
        case .nineIron: return "9 Iron"
        case .pitchingWedge: return "PW"
        case .approachWedge: return "AW · 48° Wedge"
        case .gapWedge: return "GW · 50° Wedge"
        case .fiftyTwoWedge: return "52° Wedge"
        case .fiftySixWedge: return "56° Wedge"
        case .fiftyEightWedge: return "58° Wedge"
        case .sandWedge: return "54° Wedge"
        case .lobWedge: return "60° Wedge"
        }
    }

    var isWedge: Bool {
        switch self {
        case .pitchingWedge, .approachWedge, .gapWedge, .fiftyTwoWedge,
             .sandWedge, .fiftySixWedge, .fiftyEightWedge, .lobWedge:
            return true
        default:
            return false
        }
    }

    static func wedge(named name: String) -> TrajectoryGolfClub? {
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "pw", "pitchingwedge": return .pitchingWedge
        case "aw", "approachwedge", "48", "48wedge": return .approachWedge
        case "gw", "gapwedge", "50", "50wedge": return .gapWedge
        case "52", "52wedge": return .fiftyTwoWedge
        case "sw", "sandwedge", "54", "54wedge": return .sandWedge
        case "56", "56wedge": return .fiftySixWedge
        case "58", "58wedge": return .fiftyEightWedge
        case "lw", "lobwedge", "60", "60wedge": return .lobWedge
        default: return nil
        }
    }

    static let standardBag: Set<TrajectoryGolfClub> = [
        .driver,
        .threeWood,
        .fiveWood,
        .fourHybrid,
        .fiveIron,
        .sixIron,
        .sevenIron,
        .eightIron,
        .nineIron,
        .pitchingWedge,
        .fiftyTwoWedge,
        .fiftySixWedge,
        .lobWedge
    ]
}

enum ClubProfileField: String, CaseIterable, Codable, Identifiable {
    case carryDistanceM
    case ballSpeedMps
    case launchAngleDeg
    case spinRateRpm
    case spinAxisDeg

    var id: String { rawValue }
}

enum ProfileFieldSource: String, Codable {
    case baseline
    case calibrated
    case interpolated
    case userProvided
}

struct ProfileValue: Codable, Equatable {
    var value: Double
    var source: ProfileFieldSource
}

struct ClubLaunchProfile: Codable, Equatable {
    var carryDistanceM: ProfileValue
    var ballSpeedMps: ProfileValue
    var launchAngleDeg: ProfileValue
    var spinRateRpm: ProfileValue
    var spinAxisDeg: ProfileValue
}

struct ClubLaunchOverride: Codable, Equatable {
    var carryDistanceM: Double?
    var ballSpeedMps: Double?
    var launchAngleDeg: Double?
    var spinRateRpm: Double?
    var spinAxisDeg: Double?

    static let empty = ClubLaunchOverride()

    var isEmpty: Bool {
        carryDistanceM == nil &&
        ballSpeedMps == nil &&
        launchAngleDeg == nil &&
        spinRateRpm == nil &&
        spinAxisDeg == nil
    }
}

struct TrajectoryPlayerProfile: Codable, Equatable {
    var schemaVersion = 1
    var isSetupComplete = false
    var detailLevel: ProfileDetailLevel = .easy
    var handicapBand: HandicapBand = .tenToFifteen
    var exactHandicap: Double?
    var driverCarryM: Double?
    var sevenIronCarryM: Double?
    var clubOverrides: [TrajectoryGolfClub: ClubLaunchOverride] = [:]
    var availableClubs: Set<TrajectoryGolfClub> = TrajectoryGolfClub.standardBag

    init(
        schemaVersion: Int = 1,
        isSetupComplete: Bool = false,
        detailLevel: ProfileDetailLevel = .easy,
        handicapBand: HandicapBand = .tenToFifteen,
        exactHandicap: Double? = nil,
        driverCarryM: Double? = nil,
        sevenIronCarryM: Double? = nil,
        clubOverrides: [TrajectoryGolfClub: ClubLaunchOverride] = [:],
        availableClubs: Set<TrajectoryGolfClub> = TrajectoryGolfClub.standardBag
    ) {
        self.schemaVersion = schemaVersion
        self.isSetupComplete = isSetupComplete
        self.detailLevel = detailLevel
        self.handicapBand = handicapBand
        self.exactHandicap = exactHandicap
        self.driverCarryM = driverCarryM
        self.sevenIronCarryM = sevenIronCarryM
        self.clubOverrides = clubOverrides
        self.availableClubs = availableClubs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isSetupComplete
        case detailLevel
        case handicapBand
        case exactHandicap
        case driverCarryM
        case sevenIronCarryM
        case clubOverrides
        case clubsInBag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        isSetupComplete = try container.decodeIfPresent(Bool.self, forKey: .isSetupComplete) ?? false
        detailLevel = try container.decodeIfPresent(ProfileDetailLevel.self, forKey: .detailLevel) ?? .easy
        let decodedBand = try container.decodeIfPresent(HandicapBand.self, forKey: .handicapBand) ?? .tenToFifteen
        handicapBand = decodedBand == .twentyFivePlus ? .twentyFiveToThirtyFive : decodedBand
        exactHandicap = try container.decodeIfPresent(Double.self, forKey: .exactHandicap)
        driverCarryM = try container.decodeIfPresent(Double.self, forKey: .driverCarryM)
        sevenIronCarryM = try container.decodeIfPresent(Double.self, forKey: .sevenIronCarryM)
        clubOverrides = try container.decodeIfPresent([TrajectoryGolfClub: ClubLaunchOverride].self, forKey: .clubOverrides) ?? [:]
        availableClubs = try container.decodeIfPresent(Set<TrajectoryGolfClub>.self, forKey: .clubsInBag) ?? TrajectoryGolfClub.standardBag
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(isSetupComplete, forKey: .isSetupComplete)
        try container.encode(detailLevel, forKey: .detailLevel)
        try container.encode(handicapBand, forKey: .handicapBand)
        try container.encodeIfPresent(exactHandicap, forKey: .exactHandicap)
        try container.encodeIfPresent(driverCarryM, forKey: .driverCarryM)
        try container.encodeIfPresent(sevenIronCarryM, forKey: .sevenIronCarryM)
        try container.encode(clubOverrides, forKey: .clubOverrides)
        try container.encode(availableClubs, forKey: .clubsInBag)
    }

    func override(for club: TrajectoryGolfClub) -> ClubLaunchOverride {
        clubOverrides[club] ?? .empty
    }

    mutating func setOverride(_ override: ClubLaunchOverride, for club: TrajectoryGolfClub) {
        if override.isEmpty {
            clubOverrides.removeValue(forKey: club)
        } else {
            clubOverrides[club] = override
        }
    }
}

enum ClubProfileDefaults {
    private struct BaselineClubData {
        let carryYards: Double
        let ballSpeedMph: Double
        let launchAngleDeg: Double
        let spinRateRpm: Double
    }

    private struct BandBaseline {
        let driverCarryYards: Double
        let sevenIronCarryYards: Double
        let driverBallSpeedMph: Double
        let launchAdjustmentDeg: Double
        let spinAdjustmentRpm: Double
    }

    static func baselineProfile(for club: TrajectoryGolfClub, handicapBand: HandicapBand) -> ClubLaunchProfile {
        let values = calibratedValues(for: club, handicapBand: handicapBand, driverCarryM: nil, sevenIronCarryM: nil)
        return profile(from: values, source: .baseline)
    }

    static func effectiveProfile(for club: TrajectoryGolfClub, playerProfile: TrajectoryPlayerProfile) -> ClubLaunchProfile {
        let profile: ClubLaunchProfile
        switch playerProfile.detailLevel {
        case .easy:
            profile = simpleProfile(for: club, playerProfile: playerProfile)
        case .medium:
            profile = mediumProfile(for: club, playerProfile: playerProfile) ?? simpleProfile(for: club, playerProfile: playerProfile)
        case .expert:
            profile = expertProfile(for: club, playerProfile: playerProfile)
        }

        guard let wedgeCarryM = wedgeBagCarryMeters(for: club) else { return profile }
        var wedgeProfile = profile
        let carryScale = wedgeCarryM / max(profile.carryDistanceM.value, 1)
        wedgeProfile.carryDistanceM = ProfileValue(value: wedgeCarryM, source: .userProvided)
        wedgeProfile.ballSpeedMps = ProfileValue(
            value: profile.ballSpeedMps.value * (1 + (carryScale - 1) * 0.8),
            source: .userProvided
        )
        return wedgeProfile
    }

    static func isAvailable(for club: TrajectoryGolfClub, playerProfile: TrajectoryPlayerProfile) -> Bool {
        if club.isWedge, let wedge = wedgeEntry(for: club) {
            return wedge.isInBag
        }
        return playerProfile.availableClubs.contains(club)
    }

    private static func wedgeBagCarryMeters(for club: TrajectoryGolfClub) -> Double? {
        guard let wedge = wedgeEntry(for: club), wedge.isInBag else { return nil }
        let carryYards = wedge.overrideCarry(for: .stock, swing: .full)
            ?? (wedge.fullCarryUserProvided ? wedge.fullCarry : nil)
        guard let carryYards, carryYards.isFinite, carryYards > 0 else { return nil }
        return Units.metersFromYards(carryYards)
    }

    private static func wedgeEntry(for club: TrajectoryGolfClub) -> Wedge? {
        guard club.isWedge else { return nil }
        let stored = UserDefaults.standard.string(forKey: "wedgeMatrix.wedges") ?? ""
        return Wedge.catalog(from: stored).first { TrajectoryGolfClub.wedge(named: $0.name) == club }
    }

    private static func simpleProfile(for club: TrajectoryGolfClub, playerProfile: TrajectoryPlayerProfile) -> ClubLaunchProfile {
        let values = calibratedValues(
            for: club,
            baseline: bandBaseline(for: playerProfile.handicapBand),
            driverCarryM: nil,
            sevenIronCarryM: nil
        )
        return profile(from: values, source: .baseline)
    }

    private static func mediumProfile(for club: TrajectoryGolfClub, playerProfile: TrajectoryPlayerProfile) -> ClubLaunchProfile? {
        let carryAnchors = mediumCarryAnchors(for: playerProfile)
        guard !carryAnchors.isEmpty else { return nil }

        let fallback = referenceProfile(for: club)
        var effective = fallback
        let override = carryAnchors[club] ?? .empty

        if let carryDistanceM = override.carryDistanceM {
            effective.carryDistanceM = ProfileValue(value: carryDistanceM, source: .userProvided)
        } else if let driverCarryM = carryAnchors[.driver]?.carryDistanceM, carryAnchors.count == 1 {
            effective.carryDistanceM = ProfileValue(value: driverCarryM * driverOnlyCarryRatio(for: club), source: .interpolated)
        } else if let carryDistanceM = interpolatedScaledOverrideValue(
            in: carryAnchors,
            for: club,
            fallback: fallback,
            field: .carryDistanceM,
            anchorFallback: { referenceProfile(for: $0) }
        ) {
            effective.carryDistanceM = ProfileValue(value: carryDistanceM, source: .interpolated)
        }

        let carryScale = effective.carryDistanceM.value / fallback.carryDistanceM.value
        effective.ballSpeedMps = ProfileValue(value: fallback.ballSpeedMps.value * (1.0 + (carryScale - 1.0) * 0.8), source: .calibrated)
        effective.launchAngleDeg = ProfileValue(value: fallback.launchAngleDeg.value, source: .calibrated)
        effective.spinRateRpm = ProfileValue(value: fallback.spinRateRpm.value, source: .calibrated)
        effective.spinAxisDeg = ProfileValue(value: fallback.spinAxisDeg.value, source: .calibrated)
        return effective
    }

    private static func driverOnlyCarryRatio(for club: TrajectoryGolfClub) -> Double {
        switch club {
        case .driver: return 1.0
        case .threeWood: return 0.877
        case .fourWood: return 0.84
        case .fiveWood: return 0.805
        case .sixWood: return 0.78
        case .sevenWood: return 0.76
        case .eightWood: return 0.74
        case .nineWood: return 0.72
        case .threeHybrid: return 0.78
        case .fourHybrid: return 0.74
        case .fiveHybrid: return 0.70
        case .twoIron: return 0.80
        case .threeIron: return 0.78
        case .fourIron: return 0.751
        case .fiveIron: return 0.694
        case .sixIron: return 0.651
        case .sevenIron: return 0.609
        case .eightIron: return 0.567
        case .nineIron: return 0.525
        case .pitchingWedge: return 0.483
        case .approachWedge: return 0.46
        case .gapWedge: return 0.437
        case .fiftyTwoWedge: return 0.415
        case .fiftySixWedge: return 0.365
        case .fiftyEightWedge: return 0.348
        case .sandWedge: return 0.391
        case .lobWedge: return 0.333
        }
    }

    private static func expertProfile(for club: TrajectoryGolfClub, playerProfile: TrajectoryPlayerProfile) -> ClubLaunchProfile {
        let fallback = mediumProfile(for: club, playerProfile: playerProfile) ?? simpleProfile(for: club, playerProfile: playerProfile)
        let override = playerProfile.override(for: club)
        let expertValues = advancedLaunchAnchors(for: playerProfile)
        guard !expertValues.isEmpty else { return fallback }

        var effective = fallback

        if let ballSpeedMps = override.ballSpeedMps {
            effective.ballSpeedMps = ProfileValue(value: ballSpeedMps, source: .userProvided)
        } else if let ballSpeedMps = interpolatedScaledOverrideValue(
            in: expertValues,
            for: club,
            fallback: fallback,
            field: .ballSpeedMps,
            anchorFallback: { mediumProfile(for: $0, playerProfile: playerProfile) ?? simpleProfile(for: $0, playerProfile: playerProfile) }
        ) {
            effective.ballSpeedMps = ProfileValue(value: ballSpeedMps, source: .interpolated)
        }
        if let launchAngleDeg = override.launchAngleDeg {
            effective.launchAngleDeg = ProfileValue(value: launchAngleDeg, source: .userProvided)
        } else if let launchAngleDeg = interpolatedOverrideValue(in: expertValues, for: club, keyPath: \.launchAngleDeg) {
            effective.launchAngleDeg = ProfileValue(value: launchAngleDeg, source: .interpolated)
        }
        if let spinRateRpm = override.spinRateRpm {
            effective.spinRateRpm = ProfileValue(value: spinRateRpm, source: .userProvided)
        } else if let spinRateRpm = interpolatedOverrideValue(in: expertValues, for: club, keyPath: \.spinRateRpm) {
            effective.spinRateRpm = ProfileValue(value: spinRateRpm, source: .interpolated)
        }
        if let spinAxisDeg = override.spinAxisDeg {
            effective.spinAxisDeg = ProfileValue(value: spinAxisDeg, source: .userProvided)
        } else if let spinAxisDeg = interpolatedOverrideValue(in: expertValues, for: club, keyPath: \.spinAxisDeg) {
            effective.spinAxisDeg = ProfileValue(value: spinAxisDeg, source: .interpolated)
        }
        return effective
    }

    private static func referenceProfile(for club: TrajectoryGolfClub) -> ClubLaunchProfile {
        let values = calibratedValues(for: club, baseline: referenceBaseline, driverCarryM: nil, sevenIronCarryM: nil)
        return profile(from: values, source: .baseline)
    }

    private static func mediumCarryAnchors(for playerProfile: TrajectoryPlayerProfile) -> [TrajectoryGolfClub: ClubLaunchOverride] {
        var anchors: [TrajectoryGolfClub: ClubLaunchOverride] = [:]
        for (club, override) in playerProfile.clubOverrides where override.carryDistanceM != nil {
            anchors[club] = ClubLaunchOverride(carryDistanceM: override.carryDistanceM)
        }
        return anchors
    }

    private static func advancedLaunchAnchors(for playerProfile: TrajectoryPlayerProfile) -> [TrajectoryGolfClub: ClubLaunchOverride] {
        playerProfile.clubOverrides.reduce(into: [:]) { result, element in
            let override = element.value
            let launchOverride = ClubLaunchOverride(
                ballSpeedMps: override.ballSpeedMps,
                launchAngleDeg: override.launchAngleDeg,
                spinRateRpm: override.spinRateRpm,
                spinAxisDeg: override.spinAxisDeg
            )
            if !launchOverride.isEmpty {
                result[element.key] = launchOverride
            }
        }
    }

    private static func calibratedValues(
        for club: TrajectoryGolfClub,
        handicapBand: HandicapBand,
        exactHandicap: Double? = nil,
        driverCarryM: Double?,
        sevenIronCarryM: Double?
    ) -> (carryM: Double, ballSpeedMps: Double, launchAngleDeg: Double, spinRateRpm: Double, spinAxisDeg: Double) {
        let band = effectiveBandBaseline(selectedBand: handicapBand, exactHandicap: exactHandicap)
        return calibratedValues(for: club, baseline: band, driverCarryM: driverCarryM, sevenIronCarryM: sevenIronCarryM)
    }

    private static func calibratedValues(
        for club: TrajectoryGolfClub,
        baseline: BandBaseline,
        driverCarryM: Double?,
        sevenIronCarryM: Double?
    ) -> (carryM: Double, ballSpeedMps: Double, launchAngleDeg: Double, spinRateRpm: Double, spinAxisDeg: Double) {
        let normalized = normalizedPosition(for: club)
        let distanceScale = interpolatedDistanceScale(
            normalizedPosition: normalized,
            band: baseline,
            driverCarryM: driverCarryM,
            sevenIronCarryM: sevenIronCarryM
        )
        let base = baseClubData[club] ?? baseClubData[.sevenIron]!
        let carryYards = base.carryYards * bandDistanceScale(for: club, band: baseline) * distanceScale
        let ballSpeedMph = base.ballSpeedMph * ballSpeedScale(carryScale: distanceScale, band: baseline)

        return (
            carryM: Units.metersFromYards(carryYards),
            ballSpeedMps: Units.mpsFromMph(ballSpeedMph),
            launchAngleDeg: base.launchAngleDeg + baseline.launchAdjustmentDeg,
            spinRateRpm: max(500.0, base.spinRateRpm + baseline.spinAdjustmentRpm),
            spinAxisDeg: 0.0
        )
    }

    private static func profile(
        from values: (carryM: Double, ballSpeedMps: Double, launchAngleDeg: Double, spinRateRpm: Double, spinAxisDeg: Double),
        source: ProfileFieldSource
    ) -> ClubLaunchProfile {
        ClubLaunchProfile(
            carryDistanceM: ProfileValue(value: values.carryM, source: source),
            ballSpeedMps: ProfileValue(value: values.ballSpeedMps, source: source),
            launchAngleDeg: ProfileValue(value: values.launchAngleDeg, source: source),
            spinRateRpm: ProfileValue(value: values.spinRateRpm, source: source),
            spinAxisDeg: ProfileValue(value: values.spinAxisDeg, source: source)
        )
    }

    private static func effectiveBandBaseline(selectedBand: HandicapBand, exactHandicap: Double?) -> BandBaseline {
        guard let exactHandicap else {
            return bandBaseline(for: selectedBand)
        }
        let handicap = min(max(exactHandicap, -5.0), 40.0)
        let sortedBands = HandicapBand.allCases.sorted { $0.midpoint < $1.midpoint }
        guard let upper = sortedBands.first(where: { $0.midpoint >= handicap }) else {
            return bandBaseline(for: .thirtyFivePlus)
        }
        guard let lower = sortedBands.last(where: { $0.midpoint <= handicap }), lower != upper else {
            return bandBaseline(for: upper)
        }
        let lowerBaseline = bandBaseline(for: lower)
        let upperBaseline = bandBaseline(for: upper)
        let position = (handicap - lower.midpoint) / (upper.midpoint - lower.midpoint)
        return BandBaseline(
            driverCarryYards: interpolate(lowerBaseline.driverCarryYards, upperBaseline.driverCarryYards, position),
            sevenIronCarryYards: interpolate(lowerBaseline.sevenIronCarryYards, upperBaseline.sevenIronCarryYards, position),
            driverBallSpeedMph: interpolate(lowerBaseline.driverBallSpeedMph, upperBaseline.driverBallSpeedMph, position),
            launchAdjustmentDeg: interpolate(lowerBaseline.launchAdjustmentDeg, upperBaseline.launchAdjustmentDeg, position),
            spinAdjustmentRpm: interpolate(lowerBaseline.spinAdjustmentRpm, upperBaseline.spinAdjustmentRpm, position)
        )
    }

    private static func interpolate(_ lower: Double, _ upper: Double, _ position: Double) -> Double {
        lower + (upper - lower) * position
    }

    private static func interpolatedOverrideValue(
        in overrides: [TrajectoryGolfClub: ClubLaunchOverride],
        for club: TrajectoryGolfClub,
        keyPath: KeyPath<ClubLaunchOverride, Double?>
    ) -> Double? {
        let points = overrides.compactMap { club, override -> (position: Double, value: Double)? in
            guard let value = override[keyPath: keyPath] else { return nil }
            return (normalizedPosition(for: club), value)
        }
        .sorted { $0.position < $1.position }

        guard let first = points.first else { return nil }
        guard points.count > 1 else { return first.value }

        let target = normalizedPosition(for: club)
        if target <= first.position {
            return interpolate(from: points[0], to: points[1], target: target)
        }
        if let last = points.last, target >= last.position {
            return interpolate(from: points[points.count - 2], to: last, target: target)
        }
        for index in 0..<(points.count - 1) {
            let lower = points[index]
            let upper = points[index + 1]
            if target >= lower.position && target <= upper.position {
                return interpolate(from: lower, to: upper, target: target)
            }
        }
        return nil
    }

    private static func interpolate(from lower: (position: Double, value: Double), to upper: (position: Double, value: Double), target: Double) -> Double {
        guard lower.position != upper.position else { return lower.value }
        let position = (target - lower.position) / (upper.position - lower.position)
        return interpolate(lower.value, upper.value, position)
    }

    private static func interpolatedScaledOverrideValue(
        in overrides: [TrajectoryGolfClub: ClubLaunchOverride],
        for club: TrajectoryGolfClub,
        fallback: ClubLaunchProfile,
        field: ClubProfileField,
        anchorFallback: (TrajectoryGolfClub) -> ClubLaunchProfile
    ) -> Double? {
        let keyPath: KeyPath<ClubLaunchOverride, Double?>
        let fallbackValue: (ClubLaunchProfile) -> Double
        switch field {
        case .carryDistanceM:
            keyPath = \.carryDistanceM
            fallbackValue = { $0.carryDistanceM.value }
        case .ballSpeedMps:
            keyPath = \.ballSpeedMps
            fallbackValue = { $0.ballSpeedMps.value }
        case .launchAngleDeg, .spinRateRpm, .spinAxisDeg:
            return nil
        }

        let points = overrides.compactMap { anchorClub, override -> (position: Double, value: Double)? in
            guard let value = override[keyPath: keyPath] else { return nil }
            let anchorDefault = fallbackValue(anchorFallback(anchorClub))
            guard anchorDefault > 0 else { return nil }
            return (normalizedPosition(for: anchorClub), value / anchorDefault)
        }
        .sorted { $0.position < $1.position }

        guard let first = points.first else { return nil }
        let target = normalizedPosition(for: club)
        let scale: Double
        if points.count == 1 {
            scale = first.value
        } else if target <= first.position {
            scale = interpolate(from: points[0], to: points[1], target: target)
        } else if let last = points.last, target >= last.position {
            scale = interpolate(from: points[points.count - 2], to: last, target: target)
        } else {
            scale = points.indices.dropLast().compactMap { index -> Double? in
                let lower = points[index]
                let upper = points[index + 1]
                guard target >= lower.position && target <= upper.position else { return nil }
                return interpolate(from: lower, to: upper, target: target)
            }.first ?? first.value
        }

        return fallbackValue(fallback) * scale
    }

    private static func bandBaseline(for band: HandicapBand) -> BandBaseline {
        switch band {
        case .plusToZero:
            return BandBaseline(driverCarryYards: 275, sevenIronCarryYards: 175, driverBallSpeedMph: 165, launchAdjustmentDeg: -0.2, spinAdjustmentRpm: -100)
        case .zeroToFive:
            return BandBaseline(driverCarryYards: 260, sevenIronCarryYards: 165, driverBallSpeedMph: 157, launchAdjustmentDeg: 0.0, spinAdjustmentRpm: 0)
        case .fiveToTen:
            return BandBaseline(driverCarryYards: 245, sevenIronCarryYards: 155, driverBallSpeedMph: 148, launchAdjustmentDeg: 0.4, spinAdjustmentRpm: 100)
        case .tenToFifteen:
            return BandBaseline(driverCarryYards: 230, sevenIronCarryYards: 145, driverBallSpeedMph: 140, launchAdjustmentDeg: 0.8, spinAdjustmentRpm: 200)
        case .fifteenToTwenty:
            return BandBaseline(driverCarryYards: 215, sevenIronCarryYards: 135, driverBallSpeedMph: 132, launchAdjustmentDeg: 1.2, spinAdjustmentRpm: 300)
        case .twentyToTwentyFive:
            return BandBaseline(driverCarryYards: 200, sevenIronCarryYards: 125, driverBallSpeedMph: 124, launchAdjustmentDeg: 1.6, spinAdjustmentRpm: 400)
        case .twentyFiveToThirtyFive, .twentyFivePlus:
            return BandBaseline(driverCarryYards: 185, sevenIronCarryYards: 115, driverBallSpeedMph: 116, launchAdjustmentDeg: 2.0, spinAdjustmentRpm: 500)
        case .thirtyFivePlus:
            return BandBaseline(driverCarryYards: 165, sevenIronCarryYards: 100, driverBallSpeedMph: 105, launchAdjustmentDeg: 2.5, spinAdjustmentRpm: 650)
        }
    }

    private static let referenceBaseline = BandBaseline(
        driverCarryYards: 260,
        sevenIronCarryYards: 165,
        driverBallSpeedMph: 157,
        launchAdjustmentDeg: 0.0,
        spinAdjustmentRpm: 0
    )

    private static func interpolatedDistanceScale(
        normalizedPosition: Double,
        band: BandBaseline,
        driverCarryM: Double?,
        sevenIronCarryM: Double?
    ) -> Double {
        let driverScale = driverCarryM.map { Units.yardsFromMeters($0) / band.driverCarryYards }
        let sevenIronScale = sevenIronCarryM.map { Units.yardsFromMeters($0) / band.sevenIronCarryYards }

        switch (driverScale, sevenIronScale) {
        case let (driver?, sevenIron?):
            return driver + (sevenIron - driver) * normalizedPosition
        case let (driver?, nil):
            return driver
        case let (nil, sevenIron?):
            return sevenIron
        case (nil, nil):
            return 1.0
        }
    }

    private static func ballSpeedScale(carryScale: Double, band: BandBaseline) -> Double {
        let bandBallSpeedScale = band.driverBallSpeedMph / baseClubData[.driver]!.ballSpeedMph
        return bandBallSpeedScale * (1.0 + (carryScale - 1.0) * 0.8)
    }

    private static func bandDistanceScale(for club: TrajectoryGolfClub, band: BandBaseline) -> Double {
        let normalized = normalizedPosition(for: club)
        let driverScale = band.driverCarryYards / baseClubData[.driver]!.carryYards
        let sevenIronScale = band.sevenIronCarryYards / baseClubData[.sevenIron]!.carryYards
        return driverScale + (sevenIronScale - driverScale) * normalized
    }

    private static func normalizedPosition(for club: TrajectoryGolfClub) -> Double {
        switch club {
        case .driver: return 0.0
        case .threeWood: return 0.15
        case .fourWood: return 0.20
        case .fiveWood: return 0.25
        case .sixWood: return 0.28
        case .sevenWood: return 0.30
        case .eightWood: return 0.32
        case .nineWood: return 0.34
        case .threeHybrid: return 0.28
        case .fourHybrid: return 0.34
        case .fiveHybrid: return 0.39
        case .twoIron: return 0.34
        case .threeIron: return 0.38
        case .fourIron: return 0.40
        case .fiveIron: return 0.52
        case .sixIron: return 0.65
        case .sevenIron: return 1.0
        case .eightIron: return 1.18
        case .nineIron: return 1.36
        case .pitchingWedge: return 1.54
        case .approachWedge: return 1.63
        case .gapWedge: return 1.72
        case .fiftyTwoWedge: return 1.80
        case .fiftySixWedge: return 1.92
        case .fiftyEightWedge: return 1.97
        case .sandWedge: return 1.88
        case .lobWedge: return 2.02
        }
    }

    private static let baseClubData: [TrajectoryGolfClub: BaselineClubData] = [
        .driver: BaselineClubData(carryYards: 260, ballSpeedMph: 157, launchAngleDeg: 12.5, spinRateRpm: 2600),
        .threeWood: BaselineClubData(carryYards: 235, ballSpeedMph: 145, launchAngleDeg: 11.5, spinRateRpm: 3300),
        .fourWood: BaselineClubData(carryYards: 228, ballSpeedMph: 142, launchAngleDeg: 12.0, spinRateRpm: 3600),
        .fiveWood: BaselineClubData(carryYards: 220, ballSpeedMph: 137, launchAngleDeg: 12.5, spinRateRpm: 3900),
        .sixWood: BaselineClubData(carryYards: 212, ballSpeedMph: 134, launchAngleDeg: 13.0, spinRateRpm: 4200),
        .sevenWood: BaselineClubData(carryYards: 205, ballSpeedMph: 130, launchAngleDeg: 14.0, spinRateRpm: 4500),
        .eightWood: BaselineClubData(carryYards: 198, ballSpeedMph: 127, launchAngleDeg: 15.0, spinRateRpm: 4800),
        .nineWood: BaselineClubData(carryYards: 190, ballSpeedMph: 124, launchAngleDeg: 16.0, spinRateRpm: 5000),
        .threeHybrid: BaselineClubData(carryYards: 215, ballSpeedMph: 134, launchAngleDeg: 14.0, spinRateRpm: 4200),
        .fourHybrid: BaselineClubData(carryYards: 200, ballSpeedMph: 127, launchAngleDeg: 16.0, spinRateRpm: 4700),
        .fiveHybrid: BaselineClubData(carryYards: 185, ballSpeedMph: 120, launchAngleDeg: 18.0, spinRateRpm: 5200),
        .twoIron: BaselineClubData(carryYards: 215, ballSpeedMph: 132, launchAngleDeg: 12.5, spinRateRpm: 4000),
        .threeIron: BaselineClubData(carryYards: 195, ballSpeedMph: 126, launchAngleDeg: 14.0, spinRateRpm: 4500),
        .fourIron: BaselineClubData(carryYards: 205, ballSpeedMph: 129, launchAngleDeg: 13.5, spinRateRpm: 4300),
        .fiveIron: BaselineClubData(carryYards: 180, ballSpeedMph: 123, launchAngleDeg: 14.5, spinRateRpm: 4700),
        .sixIron: BaselineClubData(carryYards: 169, ballSpeedMph: 118, launchAngleDeg: 16.0, spinRateRpm: 5300),
        .sevenIron: BaselineClubData(carryYards: 158, ballSpeedMph: 112, launchAngleDeg: 17.0, spinRateRpm: 6000),
        .eightIron: BaselineClubData(carryYards: 147, ballSpeedMph: 106, launchAngleDeg: 18.5, spinRateRpm: 6900),
        .nineIron: BaselineClubData(carryYards: 136, ballSpeedMph: 100, launchAngleDeg: 20.0, spinRateRpm: 7800),
        .pitchingWedge: BaselineClubData(carryYards: 124, ballSpeedMph: 94, launchAngleDeg: 24.0, spinRateRpm: 8700),
        .approachWedge: BaselineClubData(carryYards: 118, ballSpeedMph: 90, launchAngleDeg: 26.0, spinRateRpm: 8950),
        .gapWedge: BaselineClubData(carryYards: 112, ballSpeedMph: 86, launchAngleDeg: 28.0, spinRateRpm: 9200),
        .fiftyTwoWedge: BaselineClubData(carryYards: 106, ballSpeedMph: 82, launchAngleDeg: 30.0, spinRateRpm: 9400),
        .sandWedge: BaselineClubData(carryYards: 100, ballSpeedMph: 78, launchAngleDeg: 32.0, spinRateRpm: 9600),
        .fiftySixWedge: BaselineClubData(carryYards: 94, ballSpeedMph: 74, launchAngleDeg: 34.0, spinRateRpm: 9800),
        .fiftyEightWedge: BaselineClubData(carryYards: 90, ballSpeedMph: 72, launchAngleDeg: 35.0, spinRateRpm: 9900),
        .lobWedge: BaselineClubData(carryYards: 86, ballSpeedMph: 70, launchAngleDeg: 36.0, spinRateRpm: 10000)
    ]
}