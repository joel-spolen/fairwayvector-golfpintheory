import SwiftUI

// Ported from fairwayvector-wedge-matrix.

struct WedgeClubSelectorView: View {
    var wedges: [Wedge]
    var unit: WedgeDistanceUnit
    @Binding var targetDistance: Double
    @Binding var elevationMeters: Double
    @Binding var pinFraction: Double
    var pageTitle: String
    var pageSubtitle: String

    private var flagPosition: FlagPosition {
        FlagPosition(fraction: pinFraction)
    }

    private var playsLike: Double {
        ClubSelector.playsLikeDistance(target: targetDistance, elevationMeters: elevationMeters, pin: flagPosition)
    }

    private var suggestions: [ClubSuggestion] {
        ClubSelector.suggestions(wedges: wedges, playsLike: playsLike, pin: flagPosition, elevationMeters: elevationMeters)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WedgePageHeader(title: pageTitle, subtitle: pageSubtitle, horizontalInset: 0)
                DistanceSliderCard(targetDistance: $targetDistance, unit: unit)

                GreenLayoutCard(
                    elevationMeters: $elevationMeters,
                    pinFraction: $pinFraction,
                    targetDistance: targetDistance,
                    unit: unit
                )

                PlaysLikeCard(
                    targetDistance: targetDistance,
                    playsLike: playsLike,
                    elevationMeters: elevationMeters,
                    pin: flagPosition,
                    unit: unit
                )

                if let best = suggestions.first {
                    RecommendationCard(
                        suggestion: best,
                        playsLike: playsLike,
                        elevationMeters: elevationMeters,
                        pin: flagPosition,
                        unit: unit
                    )

                    AlternativesCard(
                        suggestions: Array(suggestions.dropFirst().prefix(3)),
                        playsLike: playsLike,
                        unit: unit
                    )
                } else {
                    ContentUnavailableView(
                        L("No clubs in bag"),
                        systemImage: "bag.badge.questionmark",
                        description: Text("From Home, open In the bag > Wedge bag to add wedges and get a recommendation.")
                    )
                    .foregroundStyle(PureLineStyle.muted)
                    .padding(.vertical, 24)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .background(PureLineStyle.canvas)
    }
}

private struct DistanceSliderCard: View {
    @Binding var targetDistance: Double
    var unit: WedgeDistanceUnit
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Distance To Flag")
                    .font(.headline)
                    .foregroundStyle(PureLineStyle.ink)
                Spacer()
                Text(unit.format(targetDistance))
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(PureLineStyle.ink)
                Text(unit.abbreviation)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PureLineStyle.muted)
            }

            Slider(value: $targetDistance, in: 20...160, step: 1)
                .tint(PureLineStyle.accent)

            HStack {
                Text(unit.format(20) + " " + unit.abbreviation)
                Spacer()
                Text(unit.format(160) + " " + unit.abbreviation)
            }
            .font(.caption)
            .foregroundStyle(PureLineStyle.muted)
        }
        .pureLineCard()
    }
}

private struct GreenLayoutCard: View {
    @Binding var elevationMeters: Double
    @Binding var pinFraction: Double
    var targetDistance: Double
    var unit: WedgeDistanceUnit

    private var flagPosition: FlagPosition {
        FlagPosition(fraction: pinFraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Green & Pin")
                    .font(.headline)
                    .foregroundStyle(PureLineStyle.ink)
                Spacer()
                Button("Level") {
                    withAnimation(.snappy) {
                        elevationMeters = 0
                        pinFraction = 0.5
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(PureLineStyle.accent)
            }

            Text("Drag the green up or down to set elevation. Drag the flag along the green to set the pin.")
                .font(.caption)
                .foregroundStyle(PureLineStyle.muted)

            GreenProfilePad(elevationMeters: $elevationMeters, pinFraction: $pinFraction, unit: unit)
                .frame(height: 240)

            HStack(spacing: 12) {
                ReadoutChip(
                    systemImage: elevationMeters > 0.2 ? "arrow.up.right" : (elevationMeters < -0.2 ? "arrow.down.right" : "equal"),
                    title: L("Elevation"),
                    value: ClubSelector.elevationLabel(meters: elevationMeters, unit: unit)
                )
                ReadoutChip(
                    systemImage: flagPosition.systemImage,
                    title: L("Pin"),
                    value: flagPosition.title
                )
            }
        }
        .pureLineCard()
    }
}

private struct GreenProfilePad: View {
    @Binding var elevationMeters: Double
    @Binding var pinFraction: Double
    var unit: WedgeDistanceUnit

    @State private var elevationDragStart: Double?

    private let maxElevationMeters: Double = 25

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let baseY = height * 0.70
            let travel = height * 0.30
            let greenY = baseY - CGFloat(elevationMeters / maxElevationMeters) * travel
            let greenLeft = width * 0.44
            let surfaceInset: CGFloat = 16
            let pinTrack = max(width - greenLeft - surfaceInset * 2 - 8, 1)
            let pinX = greenLeft + surfaceInset + CGFloat(pinFraction) * pinTrack

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.76, green: 0.87, blue: 0.94), Color(red: 0.90, green: 0.94, blue: 0.96)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                TerrainShape(baseY: baseY, greenY: greenY, greenLeft: greenLeft)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.42, green: 0.60, blue: 0.35), Color(red: 0.29, green: 0.44, blue: 0.26)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Path { path in
                    path.move(to: CGPoint(x: 8, y: baseY))
                    path.addLine(to: CGPoint(x: width - 8, y: baseY))
                }
                .stroke(PureLineStyle.ink.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                if abs(elevationMeters) > 0.2 {
                    ElevationRuler(x: greenLeft - 10, baseY: baseY, greenY: greenY)
                }

                BallFlightPath(from: CGPoint(x: width * 0.13, y: baseY - 10), to: CGPoint(x: pinX, y: greenY - 2))
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.56, green: 0.76, blue: 0.44), Color(red: 0.40, green: 0.62, blue: 0.32)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Ellipse().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
                    .frame(width: width - greenLeft - 8, height: 34)
                    .position(x: (greenLeft + width - 8) / 2, y: greenY)
                    .contentShape(Ellipse())
                    .gesture(elevationGesture(travel: travel))

                GolferMark()
                    .position(x: width * 0.13, y: baseY - 20)

                FlagMark(isSelected: true)
                    .position(x: pinX, y: greenY - 22)
                    .gesture(pinGesture(greenLeft: greenLeft, inset: surfaceInset, track: pinTrack))

                Text("You")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .position(x: width * 0.13, y: baseY + 14)

                PinZoneLabels(greenLeft: greenLeft, width: width, y: baseY + 34)
            }
            .coordinateSpace(name: "wedgeGreenPad")
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .animation(.interactiveSpring(duration: 0.18), value: elevationMeters)
            .animation(.interactiveSpring(duration: 0.18), value: pinFraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Green profile")
        .accessibilityValue("Elevation \(Int(elevationMeters.rounded())) meters, pin \(FlagPosition(fraction: pinFraction).title)")
        .accessibilityAdjustableAction { direction in
            elevationMeters = min(max(elevationMeters + (direction == .increment ? 1 : -1), -maxElevationMeters), maxElevationMeters)
        }
    }

    private func elevationGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if elevationDragStart == nil { elevationDragStart = elevationMeters }
                let metersPerPoint = maxElevationMeters / Double(max(travel, 1))
                let proposed = min(max((elevationDragStart ?? 0) - Double(value.translation.height) * metersPerPoint, -maxElevationMeters), maxElevationMeters)
                let increment = unit == .meters ? 1.0 : 0.5
                elevationMeters = (proposed / increment).rounded() * increment
            }
            .onEnded { _ in elevationDragStart = nil }
    }

    private func pinGesture(greenLeft: CGFloat, inset: CGFloat, track: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("wedgeGreenPad"))
            .onChanged { value in
                let raw = (value.location.x - greenLeft - inset) / track
                pinFraction = min(max(Double(raw), 0), 1)
            }
    }
}

private struct TerrainShape: Shape {
    var baseY: CGFloat
    var greenY: CGFloat
    var greenLeft: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let slopeStart = greenLeft - rect.width * 0.16
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: baseY))
        path.addLine(to: CGPoint(x: slopeStart, y: baseY))
        path.addCurve(
            to: CGPoint(x: greenLeft, y: greenY),
            control1: CGPoint(x: slopeStart + rect.width * 0.06, y: baseY),
            control2: CGPoint(x: greenLeft - rect.width * 0.05, y: greenY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: greenY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct BallFlightPath: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        let apexY = min(from.y, to.y) - rect.height * 0.34
        path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: apexY))
        return path
    }
}

private struct ElevationRuler: View {
    var x: CGFloat
    var baseY: CGFloat
    var greenY: CGFloat

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: baseY))
            path.addLine(to: CGPoint(x: x, y: greenY))
            path.move(to: CGPoint(x: x - 5, y: greenY))
            path.addLine(to: CGPoint(x: x + 5, y: greenY))
        }
        .stroke(PureLineStyle.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}

private struct GolferMark: View {
    var body: some View {
        Image(systemName: "figure.golf")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(PureLineStyle.ink)
    }
}

private struct FlagMark: View {
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "flag.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PureLineStyle.accent)
                .offset(x: 7)
            Rectangle()
                .fill(PureLineStyle.ink)
                .frame(width: 2, height: 22)
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(PureLineStyle.ink.opacity(0.35), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(isSelected ? 0.18 : 0), radius: 3, y: 2)
    }
}

private struct PinZoneLabels: View {
    var greenLeft: CGFloat
    var width: CGFloat
    var y: CGFloat

    var body: some View {
        HStack {
            Text("Short")
            Spacer()
            Text("Middle")
            Spacer()
            Text("Long")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.9))
        .frame(width: max(width - greenLeft - 16, 1))
        .position(x: (greenLeft + width - 8) / 2, y: y)
    }
}

private struct ReadoutChip: View {
    var systemImage: String
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(PureLineStyle.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(PureLineStyle.muted)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PureLineStyle.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PlaysLikeCard: View {
    var targetDistance: Double
    var playsLike: Double
    var elevationMeters: Double
    var pin: FlagPosition
    var unit: WedgeDistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plays Like")
                .font(.headline)
                .foregroundStyle(PureLineStyle.ink)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(unit.format(playsLike))
                    .font(.system(size: 42, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PureLineStyle.ink)
                Text(unit.abbreviation)
                    .font(.headline)
                    .foregroundStyle(PureLineStyle.muted)
            }

            AdjustmentRow(label: L("Measured"), value: unit.format(targetDistance) + " " + unit.abbreviation)
            AdjustmentRow(
                label: ClubSelector.elevationLabel(meters: elevationMeters, unit: unit),
                value: signed(ClubSelector.elevationAdjustment(meters: elevationMeters), unit: unit)
            )
            AdjustmentRow(
                label: L("%@ pin play", "\(pin.title)"),
                value: signed(ClubSelector.pinAdjustment(pin), unit: unit)
            )
        }
        .pureLineCard()
    }

    private func signed(_ yards: Double, unit: WedgeDistanceUnit) -> String {
        let converted = unit == .meters ? yards * 0.9144 : yards
        let rounded = converted.rounded()
        let prefix = rounded > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.0f", rounded)) \(unit.abbreviation)"
    }
}

private struct AdjustmentRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(PureLineStyle.muted)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(PureLineStyle.ink)
        }
    }
}

private struct RecommendationCard: View {
    var suggestion: ClubSuggestion
    var playsLike: Double
    var elevationMeters: Double
    var pin: FlagPosition
    var unit: WedgeDistanceUnit
    @State private var showReasoning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Play This Shot")
                .font(.caption.bold())
                .foregroundStyle(PureLineStyle.muted)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(suggestion.wedge.name)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(PureLineStyle.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(suggestion.swing.title) swing · \(suggestion.trajectory.title) flight")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PureLineStyle.ink)
                    if let brand = suggestion.wedge.brandDisplay {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(PureLineStyle.muted)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ReadoutChip(
                    systemImage: "ruler",
                    title: L("Carries"),
                    value: "\(unit.format(suggestion.carry)) \(unit.abbreviation)"
                )
                ReadoutChip(
                    systemImage: "target",
                    title: L("Vs. number"),
                    value: deltaText
                )
            }

            Divider().overlay(PureLineStyle.line)

            DisclosureGroup(isExpanded: $showReasoning) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(PureLineStyle.accent)
                                .padding(.top, 2)
                            Text(reason)
                                .font(.subheadline)
                                .foregroundStyle(PureLineStyle.ink)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Why this shot?", systemImage: "text.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PureLineStyle.ink)
            }
            .tint(PureLineStyle.accent)
        }
        .pureLineCard()
    }

    private var deltaText: String {
        let delta = suggestion.expectedFinish - playsLike
        let converted = unit == .meters ? delta * 0.9144 : delta
        let rounded = converted.rounded()
        if abs(rounded) < 1 { return L("On the number") }
        return rounded > 0
            ? "\(String(format: "%.0f", rounded)) \(unit.abbreviation) long"
            : "\(String(format: "%.0f", abs(rounded))) \(unit.abbreviation) short"
    }

    private var reasons: [String] {
        var items: [String] = []
        let carryText = "\(unit.format(suggestion.carry)) \(unit.abbreviation)"
        let rolloutText = "\(unit.format(suggestion.expectedRollout)) \(unit.abbreviation)"
        let playsText = "\(unit.format(playsLike)) \(unit.abbreviation)"
        items.append(L("Your %@ at a %@ swing carries %@ with about %@ of rollout, finishing closest to the %@ this shot plays.", "\(suggestion.wedge.name)", "\(suggestion.swing.title.lowercased())", "\(carryText)", "\(rolloutText)", "\(playsText)"))
        items.append(L("The %@ swing changes the release distance, so the recommendation accounts for both how hard you swing and how the ball flies.", "\(suggestion.swing.title.lowercased())"))

        if elevationMeters >= 0.6 {
            items.append(L("It is uphill to the green, so the shot plays longer than the laser number — the extra club covers it."))
        } else if elevationMeters <= -0.6 {
            items.append(L("The green sits below you, so the ball hangs and runs — less club keeps it from flying the surface."))
        }

        if abs(elevationMeters) >= 0.5 {
            let direction = elevationMeters > 0 ? L("uphill") : L("downhill")
            items.append(L("The %@ elevation changes rollout as well as carry: uphill increases the expected release, while downhill reduces it.", "\(direction)"))
        }

        switch pin {
        case .short:
            items.append(L("Front pin: choose a %@ flight that gives you enough landing room to reach the front portion of the green.", "\(suggestion.trajectory.title.lowercased())"))
        case .middle:
            items.append(L("Middle pin: the %@ flight is the balanced option, combining predictable carry with controlled rollout.", "\(suggestion.trajectory.title.lowercased())"))
        case .long:
            items.append(L("Back pin: the %@ flight gives the ball enough forward release to reach the deeper pin position.", "\(suggestion.trajectory.title.lowercased())"))
        }

        items.append(rolloutReason)
        items.append(suggestion.trajectory.ballPositionDescription)

        if suggestion.swing == .half {
            items.append(L("Keep the tempo smooth — this is the shortest swing in your matrix, so distance control comes from length, not speed."))
        }
        return items
    }

    private var rolloutReason: String {
        switch suggestion.trajectory {
        case .knockdown:
            L("Low flight: expect about %@ %@ of rollout, so the carry must finish short of the pin.", "\(unit.format(suggestion.expectedRollout))", "\(unit.abbreviation)")
        case .stock:
            L("Mid flight: expect about %@ %@ of rollout and a balanced carry-to-release pattern.", "\(unit.format(suggestion.expectedRollout))", "\(unit.abbreviation)")
        case .high:
            L("High flight: expect only about %@ %@ of rollout, so most of the distance is covered in the air.", "\(unit.format(suggestion.expectedRollout))", "\(unit.abbreviation)")
        }
    }
}

private struct AlternativesCard: View {
    var suggestions: [ClubSuggestion]
    var playsLike: Double
    var unit: WedgeDistanceUnit

    var body: some View {
        if suggestions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Other Options")
                    .font(.headline)
                    .foregroundStyle(PureLineStyle.ink)

                ForEach(suggestions) { suggestion in
                    HStack {
                        Text(suggestion.wedge.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(PureLineStyle.ink)
                            .frame(width: 44, alignment: .leading)
                        Text("\(suggestion.swing.title) · \(suggestion.trajectory.title)")
                            .font(.subheadline)
                            .foregroundStyle(PureLineStyle.muted)
                        Spacer()
                        Text("\(unit.format(suggestion.carry)) \(unit.abbreviation)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(PureLineStyle.ink)
                    }
                    .padding(10)
                    .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .pureLineCard()
        }
    }
}
