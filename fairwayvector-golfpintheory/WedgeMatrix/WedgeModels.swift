import SwiftUI

// Ported from fairwayvector-wedge-matrix, adapted to avoid clashing with this app's DistanceUnit.

struct Wedge: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var brand = ""
    var notes = ""
    var fullCarry: Double
    var isInBag = true
    // Legacy/default numbers are not evidence of user calibration.
    var fullCarryUserProvided = false
    private var shotCarries: [String: Double] = [:]

    var brandDisplay: String? {
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedBrand.isEmpty ? nil : trimmedBrand
    }

    init(id: UUID = UUID(), name: String, brand: String = "", notes: String = "", fullCarry: Double, isInBag: Bool = true, fullCarryUserProvided: Bool = false) {
        self.id = id
        self.name = name
        self.brand = brand
        self.notes = notes
        self.fullCarry = fullCarry
        self.isInBag = isInBag
        self.fullCarryUserProvided = fullCarryUserProvided
    }

    func carry(for trajectory: WedgeTrajectory, swing: SwingLength) -> Double {
        shotCarries[carryKey(trajectory: trajectory, swing: swing)]
            ?? trajectory.adjustedDistance(for: fullCarry * swing.factor)
    }

    func overrideCarry(for trajectory: WedgeTrajectory, swing: SwingLength) -> Double? {
        shotCarries[carryKey(trajectory: trajectory, swing: swing)]
    }

    mutating func setCarry(_ carry: Double, for trajectory: WedgeTrajectory, swing: SwingLength) {
        shotCarries[carryKey(trajectory: trajectory, swing: swing)] = carry
        if trajectory == .stock, swing == .full {
            fullCarry = carry
        }
    }

    mutating func clearCarry(for trajectory: WedgeTrajectory, swing: SwingLength) {
        shotCarries.removeValue(forKey: carryKey(trajectory: trajectory, swing: swing))
    }

    private func carryKey(trajectory: WedgeTrajectory, swing: SwingLength) -> String {
        "\(trajectory.rawValue).\(swing.rawValue)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, brand, notes, fullCarry, isInBag, fullCarryUserProvided, shotCarries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        fullCarry = try container.decode(Double.self, forKey: .fullCarry)
        isInBag = try container.decodeIfPresent(Bool.self, forKey: .isInBag) ?? true
        fullCarryUserProvided = try container.decodeIfPresent(Bool.self, forKey: .fullCarryUserProvided) ?? false
        shotCarries = try container.decodeIfPresent([String: Double].self, forKey: .shotCarries) ?? [:]
    }

    static let defaults = [
        Wedge(name: "PW", fullCarry: 125, isInBag: TrajectoryGolfClub.standardBag.contains(.pitchingWedge)),
        Wedge(name: "AW", fullCarry: 118, isInBag: TrajectoryGolfClub.standardBag.contains(.approachWedge)),
        Wedge(name: "GW", fullCarry: 112, isInBag: TrajectoryGolfClub.standardBag.contains(.gapWedge)),
        Wedge(name: "52", fullCarry: 106, isInBag: TrajectoryGolfClub.standardBag.contains(.fiftyTwoWedge)),
        Wedge(name: "54", fullCarry: 100, isInBag: TrajectoryGolfClub.standardBag.contains(.sandWedge)),
        Wedge(name: "56", fullCarry: 94, isInBag: TrajectoryGolfClub.standardBag.contains(.fiftySixWedge)),
        Wedge(name: "58", fullCarry: 90, isInBag: TrajectoryGolfClub.standardBag.contains(.fiftyEightWedge)),
        Wedge(name: "60", fullCarry: 86, isInBag: TrajectoryGolfClub.standardBag.contains(.lobWedge))
    ]

    static func catalog(from storedValue: String, availableClubs: Set<TrajectoryGolfClub> = TrajectoryGolfClub.standardBag) -> [Wedge] {
        let stored = storedValue.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([Wedge].self, from: $0) } ?? []
        var remaining = stored
        var catalog = defaults.map { template in
            guard let club = TrajectoryGolfClub.wedge(named: template.name) else { return template }
            if let index = remaining.firstIndex(where: { TrajectoryGolfClub.wedge(named: $0.name) == club }) {
                return remaining.remove(at: index)
            }
            var newEntry = template
            newEntry.isInBag = availableClubs.contains(club)
            return newEntry
        }
        catalog.append(contentsOf: remaining.filter { TrajectoryGolfClub.wedge(named: $0.name) == nil })
        return catalog
    }
}

enum SwingLength: String, CaseIterable, Identifiable {
    case half
    case threeQuarter
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .half: "50%"
        case .threeQuarter: "75%"
        case .full: "Full"
        }
    }

    var factor: Double {
        switch self {
        case .half: 0.70
        case .threeQuarter: 0.90
        case .full: 1.0
        }
    }

    var background: Color {
        switch self {
        case .half: FairwayVectorColors.conditionsSurface.opacity(0.75)
        case .threeQuarter: FairwayVectorColors.conditionsSurface
        case .full: FairwayVectorColors.gold.opacity(0.22)
        }
    }

    func shotImageName(for trajectory: WedgeTrajectory) -> String {
        "Shot\(shotAssetSegment)\(trajectory.shotAssetSegment)"
    }

    private var shotAssetSegment: String {
        switch self {
        case .half: "50"
        case .threeQuarter: "75"
        case .full: "Full"
        }
    }
}

enum FlagPosition: String, CaseIterable, Identifiable {
    case short
    case middle
    case long

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: "Short Green"
        case .middle: "Middle Green"
        case .long: "Long Green"
        }
    }

    var shortTitle: String {
        switch self {
        case .short: "Short"
        case .middle: "Middle"
        case .long: "Long"
        }
    }

    var metricTitle: String {
        switch self {
        case .short: "Short Flag"
        case .middle: "Middle Flag"
        case .long: "Long Flag"
        }
    }

    var systemImage: String {
        switch self {
        case .short: "flag"
        case .middle: "flag.fill"
        case .long: "flag.checkered"
        }
    }

    var targetAdjustment: Double {
        switch self {
        case .short: -5
        case .middle: 0
        case .long: 5
        }
    }

    init(fraction: Double) {
        switch fraction {
        case ..<0.34: self = .short
        case ..<0.67: self = .middle
        default: self = .long
        }
    }
}

enum WedgeTrajectory: String, CaseIterable, Identifiable {
    case knockdown
    case stock
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .knockdown: "Low"
        case .stock: "Stock"
        case .high: "High"
        }
    }

    var systemImage: String {
        switch self {
        case .knockdown: "arrow.down.forward"
        case .stock: "arrow.up.forward"
        case .high: "arrow.up.right"
        }
    }

    var ballPositionDescription: String {
        switch self {
        case .knockdown: "Low flight: play the ball just back of center."
        case .stock: "Mid flight: play the ball in the center of your stance."
        case .high: "High flight: play the ball just forward of center."
        }
    }

    var shotAssetSegment: String {
        switch self {
        case .knockdown: "Low"
        case .stock: "Stock"
        case .high: "High"
        }
    }

    func adjustedDistance(for stockCarry: Double) -> Double {
        switch self {
        case .knockdown: stockCarry * 0.92
        case .stock: stockCarry
        case .high: stockCarry * 0.96
        }
    }
}

/// Yards-based unit, distinct from the meters-based `DistanceUnit` used elsewhere in this app.
enum WedgeDistanceUnit: String, CaseIterable, Identifiable {
    case yards
    case meters

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yards: "Imperial"
        case .meters: "Metric"
        }
    }

    var abbreviation: String {
        switch self {
        case .yards: "yd"
        case .meters: "m"
        }
    }

    func format(_ yards: Double) -> String {
        switch self {
        case .yards: String(format: "%.0f", yards)
        case .meters: String(format: "%.0f", yards * 0.9144)
        }
    }
}

struct ClubSuggestion: Identifiable {
    let wedge: Wedge
    let trajectory: WedgeTrajectory
    let swing: SwingLength
    let carry: Double
    let expectedRollout: Double
    let score: Double

    var id: String { "\(wedge.id.uuidString).\(trajectory.rawValue).\(swing.rawValue)" }

    var expectedFinish: Double {
        carry + expectedRollout
    }
}

enum ClubSelector {
    /// Elevation change adds (or removes) its own height in carry distance.
    static func elevationAdjustment(meters: Double) -> Double {
        meters / 0.9144
    }

    /// Strategic bias: cover the front for a short pin, stay below the hole for a back pin.
    static func pinAdjustment(_ pin: FlagPosition) -> Double {
        switch pin {
        case .short: 2
        case .middle: 0
        case .long: -2
        }
    }

    static func playsLikeDistance(target: Double, elevationMeters: Double, pin: FlagPosition) -> Double {
        target + elevationAdjustment(meters: elevationMeters) + pinAdjustment(pin)
    }

    static func elevationLabel(meters: Double, unit: WedgeDistanceUnit) -> String {
        let magnitude = abs(meters)
        if magnitude < 0.2 { return "Flat" }
        let value = unit == .yards ? magnitude / 0.3048 : magnitude
        let suffix = unit == .yards ? "ft" : "m"
        let direction = meters > 0 ? "uphill" : "downhill"
        let formatted = unit == .yards
            ? String(format: "%.0f", value.rounded())
            : String(format: value == value.rounded() ? "%.0f" : "%.1f", value)
        return "\(formatted) \(suffix) \(direction)"
    }

    static func suggestions(
        wedges: [Wedge],
        playsLike: Double,
        pin: FlagPosition,
        elevationMeters: Double
    ) -> [ClubSuggestion] {
        let candidates = wedges.flatMap { wedge in
            WedgeTrajectory.allCases.flatMap { trajectory in
                SwingLength.allCases.map { swing -> ClubSuggestion in
                    let carry = wedge.carry(for: trajectory, swing: swing)
                    let rollout = expectedRollout(for: trajectory, swing: swing, elevationMeters: elevationMeters)
                    let score = abs(carry + rollout - playsLike)
                        + swingPenalty(swing)
                        + trajectoryPenalty(trajectory, pin: pin, elevationMeters: elevationMeters)
                    return ClubSuggestion(wedge: wedge, trajectory: trajectory, swing: swing, carry: carry, expectedRollout: rollout, score: score)
                }
            }
        }

        let sorted = candidates.sorted { $0.score < $1.score }
        guard let best = sorted.first else { return [] }

        var results = [best]
        for candidate in sorted.dropFirst() where results.count < 4 {
            let duplicate = results.contains { $0.wedge.id == candidate.wedge.id && $0.swing == candidate.swing }
            if !duplicate, abs(candidate.expectedFinish - playsLike) <= 12 {
                results.append(candidate)
            }
        }
        return results
    }

    private static func expectedRollout(
        for trajectory: WedgeTrajectory,
        swing: SwingLength,
        elevationMeters: Double
    ) -> Double {
        let trajectoryRollout: Double
        switch trajectory {
        case .knockdown: trajectoryRollout = 8
        case .stock: trajectoryRollout = 4
        case .high: trajectoryRollout = 1
        }

        let swingFactor: Double
        switch swing {
        case .half: swingFactor = 1.0
        case .threeQuarter: swingFactor = 0.75
        case .full: swingFactor = 0.50
        }

        let elevationFactor = min(max(1 + elevationMeters / 50, 0.5), 1.5)
        return trajectoryRollout * swingFactor * elevationFactor
    }

    private static func swingPenalty(_ swing: SwingLength) -> Double {
        switch swing {
        case .half: 1.4
        case .threeQuarter: 0
        case .full: 0.5
        }
    }

    private static func trajectoryPenalty(_ trajectory: WedgeTrajectory, pin: FlagPosition, elevationMeters: Double) -> Double {
        var penalty: Double
        switch (pin, trajectory) {
        case (.short, .high): penalty = 0
        case (.short, .stock): penalty = 0.5
        case (.short, .knockdown): penalty = 1.2
        case (.middle, .stock): penalty = 0
        case (.middle, .high): penalty = 0.5
        case (.middle, .knockdown): penalty = 0.6
        case (.long, .knockdown): penalty = 0
        case (.long, .stock): penalty = 0.3
        case (.long, .high): penalty = 1.0
        }

        if elevationMeters <= -5 {
            penalty += trajectory == .high ? -0.3 : (trajectory == .knockdown ? 0.4 : 0)
        } else if elevationMeters >= 5 {
            penalty += trajectory == .knockdown ? -0.2 : (trajectory == .high ? 0.4 : 0)
        }
        return penalty
    }
}
