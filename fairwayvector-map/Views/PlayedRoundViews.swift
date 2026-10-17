import SwiftData
import SwiftUI
import UIKit

struct RoundSetupView: View {
    let selectedCourseReference: CourseReference
    let course: Course
    let dismissOnCompletion: Bool
    let onStarted: () -> Void
    let onCancel: () -> Void
    @Environment(PlayedRoundStore.self) private var store
    @EnvironmentObject private var trajectoryModel: TrajectoryCalculatorViewModel
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [PlayerProfile]
    @Query(sort: \GolfRound.date, order: .reverse) private var hcpRounds: [GolfRound]
    @State private var game: RoundGame = .strokePlay
    @State private var players = [RoundPlayer(name: "You", isOwner: true, handicapIndex: nil, keepsDetailedScore: true)]
    @State private var showWind = RoundDisplayOptions.roundSetupDefault.showWind
    @State private var showElevation = RoundDisplayOptions.roundSetupDefault.showElevation
    @State private var showClubSelection = RoundDisplayOptions.roundSetupDefault.showClubSelection
    @State private var scoringMode = RoundDisplayOptions.roundSetupDefault.scoringMode
    @State private var error: String?
    @State private var initialized = false

    init(selectedCourseReference: CourseReference, course: Course, dismissOnCompletion: Bool = true,
         onStarted: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.selectedCourseReference = selectedCourseReference
        self.course = course
        self.dismissOnCompletion = dismissOnCompletion
        self.onStarted = onStarted
        self.onCancel = onCancel
    }

    private var holes: [PlayedHole] {
        course.holes.map { PlayedHole(number: $0.number, par: $0.par, strokeIndex: $0.handicapIndex) }
    }
    private var candidate: PlayedRound {
        PlayedRound(reference: selectedCourseReference, course: course, holes: holes,
            players: players, game: game, detailMode: .detailed, allowance: 100,
            displayOptions: RoundDisplayOptions(showWind: showWind, showElevation: showElevation,
                                                showClubSelection: showClubSelection,
                                                scoringMode: showClubSelection && scoringMode))
    }

    private func binding(for playerID: UUID) -> Binding<RoundPlayer> {
        Binding(
            get: { players.first(where: { $0.id == playerID }) ?? RoundPlayer(name: "Player", isOwner: false, handicapIndex: nil) },
            set: { updated in
                guard let index = players.firstIndex(where: { $0.id == playerID }) else { return }
                players[index] = updated
            }
        )
    }

    private func removePlayer(_ playerID: UUID) {
        guard players.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            players = players.filter { $0.id != playerID }
        }
    }

    private var defaultOwnerHandicapIndex: Double {
        let entries = WHSCalculator.scoringEntries(from: hcpRounds, lowHandicapIndex: profiles.first?.lowHandicapIndex)
        let computed = WHSCalculator.handicapIndex(from: entries, lowHandicapIndex: profiles.first?.lowHandicapIndex)
        let shared = trajectoryModel.playerProfileStore.profile
        let index = computed ?? (shared.isSetupComplete ? shared.exactHandicap : nil)
        return index.flatMap { $0.isFinite && (-10...54).contains($0) ? $0 : nil } ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SELECTED COURSE & TEE")
                        .font(.caption.weight(.semibold)).tracking(1.2)
                        .foregroundStyle(PureLineStyle.muted)
                    Text(selectedCourseReference.courseName).font(.headline)
                    Text("\(selectedCourseReference.teeName) · \(selectedCourseReference.teeSex.capitalized) · \(holes.count) holes")
                        .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                    LabeledContent("Rating / slope", value: String(format: "%.1f / %d", selectedCourseReference.courseRating, selectedCourseReference.slopeRating))
                    Text("Uses this course's loaded holes and selected tee. To change tees, return to Choose Course.")
                        .font(.caption).foregroundStyle(PureLineStyle.muted)
                    if candidate.tee == nil || candidate.strokeRanks == nil {
                        Label("Some par, stroke indexes or applicable tee ratings are missing. Gross scoring is available; net, points and HCP calculations need complete course data.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(PureLineStyle.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pureLineCard()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your round").font(.headline)
                    Text("Game").font(.subheadline.weight(.medium))
                    Picker("Game", selection: $game) {
                        ForEach(RoundGame.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("Choose detailed scoring individually for each player. Detailed scorecards track putts, fairway position, bunker shots and penalties.")
                        .font(.caption).foregroundStyle(PureLineStyle.muted)
                }
                .pureLineCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Course view").font(.headline)
                    Toggle("Wind", isOn: $showWind)
                    Toggle("Elevation", isOn: $showElevation)
                    Toggle("Club selection", isOn: $showClubSelection)
                    Toggle("Scoring mode recommendations", isOn: $scoringMode)
                        .disabled(!showClubSelection)
                    Text("Scoring mode prioritizes calibrated wedge shots when the target is within your personal range.")
                        .font(.caption).foregroundStyle(PureLineStyle.muted)
                }
                .font(.subheadline)
                .tint(PureLineStyle.accent)
                .pureLineCard()
                ForEach(players) { player in
                    let playerBinding = binding(for: player.id)
                    VStack(alignment: .leading, spacing: 14) {
                        Label(player.isOwner ? "You · personal statistics" : "Additional player", systemImage: "person")
                            .font(.headline)
                        if !player.isOwner {
                            TextField("Player name", text: playerBinding.name)
                                .padding(12)
                                .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("Player name")
                        }
                        Toggle("Keep detailed score", isOn: Binding(
                            get: { playerBinding.wrappedValue.keepsDetailedScore ?? true },
                            set: { playerBinding.wrappedValue.keepsDetailedScore = $0 }))
                            .font(.subheadline)
                        Toggle("Use Handicap Index", isOn: Binding(
                            get: { playerBinding.wrappedValue.handicapIndex != nil },
                            set: { enabled in
                                playerBinding.wrappedValue.handicapIndex = enabled
                                    ? (player.isOwner ? defaultOwnerHandicapIndex : 0) : nil
                            }))
                            .font(.subheadline)
                        if playerBinding.wrappedValue.handicapIndex != nil {
                            LabeledContent("Handicap Index") {
                                TextField("Handicap Index", value: Binding(
                                    get: { playerBinding.wrappedValue.handicapIndex ?? 0 },
                                    set: { playerBinding.wrappedValue.handicapIndex = $0 }), format: .number)
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                    .padding(10)
                                    .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel("Handicap Index")
                            }
                            .font(.subheadline)
                            Text("Range −10 to 54. A plus 2 index is entered as −2. Zero means scratch, not unknown.")
                                .font(.caption).foregroundStyle(PureLineStyle.muted)
                        } else {
                            Text("Gross only. Net score and Stableford points unavailable until an index is supplied.")
                                .font(.caption).foregroundStyle(PureLineStyle.muted)
                        }
                        if !player.isOwner {
                            Button("Remove player", role: .destructive) { removePlayer(player.id) }
                                .font(.subheadline).foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pureLineCard()
                }
                    Button("Add player · \(players.count - 1)/3", systemImage: "person.badge.plus") {
                        players.append(RoundPlayer(name: "Player \(players.count + 1)", isOwner: false,
                                                   handicapIndex: nil, keepsDetailedScore: true))
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(PureLineStyle.line, lineWidth: 1) }
                    .disabled(players.count >= 4)
                    if game == .stableford, players.contains(where: { $0.handicapIndex == nil }) {
                        Text("Players without an index can record gross strokes but have no net Stableford total. Enable an index and explicitly choose 0 for scratch if appropriate.")
                            .font(.caption).foregroundStyle(PureLineStyle.muted)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Start round", systemImage: "flag.checkered") {
                        do {
                            try store.start(candidate)
                            onStarted()
                            if dismissOnCompletion { dismiss() }
                        } catch { self.error = error.localizedDescription }
                    }
                    .buttonStyle(PureLinePrimaryButtonStyle())
                    .disabled(!PlayedRoundStore.validStructure(candidate) || store.active != nil)
                    .accessibilityIdentifier("start-scored-round")
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .navigationTitle("Round setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        if dismissOnCompletion { dismiss() }
                    }
                }
            }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                players[0].handicapIndex = defaultOwnerHandicapIndex
            }
        }.tint(PureLineStyle.accent)
    }
}

struct RoundHoleEntryView: View {
    let round: PlayedRound
    let holeNumber: Int
    let onSave: (Int, [UUID: PlayedHoleScore]) throws -> Void
    let onNavigateHole: (Int) -> Void
    @Environment(PlayedRoundStore.self) private var roundStore
    @State private var entries: [UUID: PlayedHoleScore] = [:]
    @State private var error: String?
    @State private var showingGIRInfo = false
    private var hole: PlayedHole? { round.holes.first { $0.number == holeNumber } }

    private func binding(_ player: UUID) -> Binding<PlayedHoleScore> {
        Binding(get: { entries[player] ?? PlayedHoleScore(strokes: 4) }, set: { entries[player] = $0 })
    }
    private var valid: Bool { round.players.allSatisfy { entries[$0.id]?.isValid == true } }
    private var holePosition: Int { round.holes.firstIndex(where: { $0.number == holeNumber }) ?? 0 }
    private var hasSavedScore: Bool { round.players.contains { round.score(player: $0.id, hole: holeNumber) != nil } }
    private var allPlayersScored: Bool {
        round.players.allSatisfy { round.score(player: $0.id, hole: holeNumber)?.isValid == true }
    }

    private func saveCurrentHole() throws {
        guard valid else { throw RoundStorageError.incomplete }
        try onSave(holeNumber, entries)
        error = nil
    }

    private func moveHole(by offset: Int) {
        let pageIndex = holePosition * 2 + 1
        let destinationPage = pageIndex + offset
        let lastPage = round.holes.count * 2 - 1
        guard (0...lastPage).contains(destinationPage) else { return }
        do {
            try saveCurrentHole()
            onNavigateHole(round.holes[destinationPage / 2].number)
        } catch {
            self.error = "Save this hole before moving on: \(error.localizedDescription)"
        }
    }

    private func loadEntries(for number: Int) {
        entries = [:]
        for player in round.players {
            let savedScore = round.score(player: player.id, hole: number)
            var score = savedScore
                ?? PlayedHoleScore(strokes: round.holes.first(where: { $0.number == number })?.par ?? 4)
            if round.recordsDetailedScore(for: player) {
                score.putts = score.putts ?? min(2, max(0, score.strokes - (score.penalties ?? 0)))
                score.bunkerShots = score.bunkerShots ?? 0
                score.penalties = score.penalties ?? 0
                if savedScore == nil { score.fairway = .hit }
            }
            if round.holes.first(where: { $0.number == number })?.par == 3 { score.fairway = .notApplicable }
            entries[player.id] = score
        }
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HOLE \(holeNumber)")
                        .font(.caption.weight(.semibold)).tracking(1.2)
                        .foregroundStyle(PureLineStyle.muted)
                    Text("Par \(hole?.par.map(String.init) ?? "—") · HCP \(hole?.strokeIndex.map(String.init) ?? "—")")
                        .font(.title2.weight(.semibold))
                    Label(
                        roundStore.draftNeedsRetry ? "Save pending" : allPlayersScored ? "Score saved" : hasSavedScore ? "Partly scored" : "No score yet",
                        systemImage: roundStore.draftNeedsRetry ? "exclamationmark.circle" : allPlayersScored ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(allPlayersScored && !roundStore.draftNeedsRetry ? PureLineStyle.accent : PureLineStyle.muted)
                    .accessibilityIdentifier("scorecard-hole-score-status")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pureLineCard()
                ForEach(round.players) { player in
                    VStack(alignment: .leading, spacing: 16) {
                        let score = binding(player.id)
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                if let par = hole?.par {
                                    Text("Gross · \(scoreName(strokes: score.wrappedValue.strokes, par: par))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(PureLineStyle.accent)
                                    if player.handicapIndex != nil {
                                        if let received = handicapStrokes(for: player) {
                                            Text("HCP · \(scoreName(strokes: score.wrappedValue.strokes - received, par: par))")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(PureLineStyle.muted)
                                        } else {
                                            Text("HCP · unavailable")
                                                .font(.caption).foregroundStyle(PureLineStyle.muted)
                                        }
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                            Label(player.isOwner ? "You" : player.name, systemImage: "person")
                                .font(.headline)
                        }
                        Stepper(value: score.strokes, in: 1...30) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total strokes")
                                    .font(.caption).foregroundStyle(PureLineStyle.muted)
                                Text("\(score.wrappedValue.strokes)")
                                    .font(.largeTitle.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(PureLineStyle.accent)
                            }
                        }
                        if round.recordsDetailedScore(for: player) {
                            Divider().overlay(PureLineStyle.line)
                            detailCount("Putts", value: score.putts, maximum: score.wrappedValue.strokes)
                            if hole?.par == 3 {
                                LabeledContent("Fairway", value: "N/A · par 3")
                            } else {
                                fairwaySelector(score.fairway)
                            }
                            detailCount("Bunker shots", value: score.bunkerShots, maximum: score.wrappedValue.strokes)
                            detailCount("Penalty strokes", value: score.penalties, maximum: score.wrappedValue.strokes)
                            if let putts = score.wrappedValue.putts, let par = hole?.par {
                                HStack {
                                    Text("GIR")
                                    Button { showingGIRInfo.toggle() } label: {
                                        Image(systemName: "info.circle")
                                            .font(.subheadline)
                                            .frame(width: 32, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(PureLineStyle.accent)
                                    .accessibilityLabel("About GIR and its calculation")
                                    Spacer()
                                    Text(score.wrappedValue.strokes - putts <= par - 2 ? "Yes" : "No")
                                        .foregroundStyle(PureLineStyle.muted)
                                }
                            }
                        }
                        if !score.wrappedValue.isValid {
                            Text("Counts must be between 0 and total strokes; putts plus penalties cannot exceed total strokes.").foregroundStyle(.red).font(.footnote)
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pureLineCard()
                }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .padding(18)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 12) {
                    Button { moveHole(by: -1) } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 48, height: 48)
                            .background(PureLineStyle.surface, in: Circle())
                    }
                    .accessibilityLabel("Previous page")

                    Button {
                        do {
                            try saveCurrentHole()
                            let nextHoleIndex = min(holePosition + 1, round.holes.count - 1)
                            onNavigateHole(round.holes[nextHoleIndex].number)
                        }
                        catch { self.error = "Score could not be saved: \(error.localizedDescription)" }
                    } label: {
                        Label("Save hole", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(PureLinePrimaryButtonStyle())
                    .disabled(!valid)
                    .accessibilityIdentifier("save-hole-score")

                    Button { moveHole(by: 1) } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 48, height: 48)
                            .background(PureLineStyle.surface, in: Circle())
                    }
                    .disabled(holePosition >= round.holes.count - 1)
                    .accessibilityLabel("Next page")
                }
                .buttonStyle(.plain)
                .foregroundStyle(PureLineStyle.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(PureLineStyle.canvas)
            }
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .sheet(isPresented: $showingGIRInfo) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Green in regulation").font(.headline)
                        Spacer()
                        Button("Done") { showingGIRInfo = false }
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("GIR means reaching the green in no more than par minus two strokes: 1 on a par 3, 2 on a par 4, or 3 on a par 5.")
                    Text("The app estimates GIR when total strokes − putts ≤ par − 2. This is inferred, not measured green arrival; penalties and recovery play can affect the result.")
                        .foregroundStyle(PureLineStyle.muted)
                }
                .font(.subheadline)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(PureLineStyle.canvas)
                .foregroundStyle(PureLineStyle.ink)
                .tint(PureLineStyle.accent)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
            }
            .onAppear { loadEntries(for: holeNumber) }
        .tint(PureLineStyle.accent)
    }

    private func handicapStrokes(for player: RoundPlayer) -> Int? {
        guard player.handicapIndex != nil,
              let rank = round.strokeRanks?[holeNumber],
              let courseHandicap = PlayedRoundCalculator.courseHandicap(round: round, player: player) else { return nil }
        let playingHandicap = Int(floor(Double(courseHandicap) * Double(round.allowance) / 100 + 0.5))
        return PlayedRoundCalculator.strokes(handicap: playingHandicap, rank: rank, holeCount: round.holes.count)
    }

    private func scoreName(strokes: Int, par: Int) -> String {
        switch strokes - par {
        case -4: "Condor"
        case -3: "Albatross"
        case -2: "Eagle"
        case -1: "Birdie"
        case 0: "Par"
        case 1: "Bogey"
        case 2: "Double bogey"
        case 3: "Triple bogey"
        case 4: "Quadruple bogey"
        case let difference where difference < 0: "\(-difference) under par"
        case let difference: "\(difference) over par"
        }
    }

    private func detailCount(_ title: String, value: Binding<Int?>, maximum: Int) -> some View {
        Stepper("\(title): \(value.wrappedValue ?? 0)", value: Binding(
            get: { value.wrappedValue ?? 0 }, set: { value.wrappedValue = $0 }), in: 0...maximum)
    }

    private func fairwaySelector(_ selection: Binding<RoundFairway>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fairway in regulation").font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                fairwayButton(.hit, icon: "checkmark", selection: selection)
                fairwayButton(.missed, icon: "xmark", selection: selection)
            }
            if isFairwayMiss(selection.wrappedValue) {
                Text("Miss direction (optional)")
                    .font(.caption)
                    .foregroundStyle(PureLineStyle.muted)
                HStack(spacing: 6) {
                    fairwayButton(.left, icon: "arrow.left", selection: selection)
                    fairwayButton(.right, icon: "arrow.right", selection: selection)
                    fairwayButton(.long, icon: "arrow.up", selection: selection)
                    fairwayButton(.short, icon: "arrow.down", selection: selection)
                }
            }
        }
    }

    private func isFairwayMiss(_ outcome: RoundFairway) -> Bool {
        [.missed, .left, .right, .long, .short].contains(outcome)
    }

    private func fairwayButton(_ outcome: RoundFairway, icon: String, selection: Binding<RoundFairway>) -> some View {
        let selected = outcome == .missed ? isFairwayMiss(selection.wrappedValue) : selection.wrappedValue == outcome
        let title = outcome == .hit ? "FIR" : outcome == .missed ? "Missed FIR" : outcome.label
        return Button {
            // Tapping a selected direction clears only that optional detail.
            if outcome != .hit && outcome != .missed && selection.wrappedValue == outcome {
                selection.wrappedValue = .missed
            } else if outcome != .missed || !isFairwayMiss(selection.wrappedValue) {
                selection.wrappedValue = outcome
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.body.weight(.semibold))
                Text(title).font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(selected ? Color.white : PureLineStyle.accent)
            .background(selected ? PureLineStyle.accent : PureLineStyle.canvas,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PureLineStyle.line, lineWidth: selected ? 0 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(outcome == .hit ? "Fairway hit" : outcome == .missed ? "Fairway missed" : "Fairway miss: \(outcome.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private enum RoundScorecardColumn: Identifiable {
    case hole(PlayedHole)
    case subtotal(title: String, holes: [PlayedHole], key: String)

    var id: String {
        switch self {
        case .hole(let hole): "hole-\(hole.number)"
        case .subtotal(_, _, let key): key
        }
    }

    var holes: [PlayedHole] {
        switch self {
        case .hole(let hole): [hole]
        case .subtotal(_, let holes, _): holes
        }
    }

    var title: String? {
        if case .subtotal(let title, _, _) = self { return title }
        return nil
    }

    var hole: PlayedHole? {
        if case .hole(let hole) = self { return hole }
        return nil
    }
}

/// Full-screen landscape-style scorecard rendered inside the portrait app shell.
struct RoundScorecardView: View {
    let round: PlayedRound
    var onEditHole: ((Int) -> Void)? = nil
    @Environment(PlayedRoundStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let labelWidth: CGFloat = 72
    private var isSaved: Bool { store.saved.contains { $0.id == round.id } }
    private var columns: [RoundScorecardColumn] {
        var result: [RoundScorecardColumn] = []
        let orderedHoles = round.holes.sorted { $0.number < $1.number }
        for (index, hole) in orderedHoles.enumerated() {
            result.append(.hole(hole))
            if round.holes.count == 18, index == 8 {
                result.append(.subtotal(title: "OUT", holes: Array(orderedHoles[..<9]), key: "out"))
            } else if round.holes.count == 18, index == 17 {
                result.append(.subtotal(title: "IN", holes: Array(orderedHoles[9...]), key: "in"))
            } else if round.holes.count == 9, index == 8 {
                result.append(.subtotal(title: "TOTAL", holes: orderedHoles, key: "total"))
            }
        }
        if round.holes.count == 18 {
            result.append(.subtotal(title: "TOTAL", holes: orderedHoles, key: "total"))
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let portrait = geometry.size.height > geometry.size.width
            let scorecardWidth = max(geometry.size.width, geometry.size.height)
            let scorecardHeight = min(geometry.size.width, geometry.size.height)
            let columnWidth = max(1, (scorecardWidth - labelWidth) / CGFloat(max(1, columns.count)))
            let naturalHeight = 102 + round.players.reduce(0) {
                $0 + 42 + (round.recordsDetailedScore(for: $1) ? 125 : 0)
            }
            let rowScale = max(1, scorecardHeight / CGFloat(naturalHeight))
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                        row(label: "HOLE", columnWidth: columnWidth, isHeader: true, height: 34 * rowScale) { column in
                            Text(column.hole.map { String($0.number) } ?? (column.title == "TOTAL" ? "TOT" : column.title) ?? "—")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                        }
                        row(label: "PAR", columnWidth: columnWidth, isHeader: true, height: 34 * rowScale) { column in
                            scorecardText(parValue(for: column), emphasized: true)
                        }
                        row(label: "HCP", columnWidth: columnWidth, isHeader: true, height: 34 * rowScale) { column in
                            scorecardText(column.hole?.strokeIndex.map(String.init) ?? "—")
                        }

                        ForEach(round.players) { player in
                            row(label: round.players.count == 1 ? "Score" : player.isOwner ? "You" : player.name,
                                columnWidth: columnWidth, isEditable: !isSaved, height: 42 * rowScale) { column in
                                if let hole = column.hole {
                                    scoreValue(round.score(player: player.id, hole: hole.number), hole: hole)
                                } else {
                                    scorecardText(aggregateScores(player: player, holes: column.holes), emphasized: true)
                                }
                            }
                            if round.recordsDetailedScore(for: player) {
                                row(label: "Putts", columnWidth: columnWidth, height: 25 * rowScale) { column in
                                    scoreDetail(aggregateDetail(player: player, holes: column.holes, value: \.putts))
                                }
                                row(label: "FIR", columnWidth: columnWidth, height: 25 * rowScale) { column in
                                    fairwayCell(player: player, column: column)
                                }
                                row(label: "GIR", columnWidth: columnWidth, height: 25 * rowScale) { column in
                                    greenCell(player: player, column: column)
                                }
                                row(label: "Sand", columnWidth: columnWidth, height: 25 * rowScale) { column in
                                    scoreDetail(aggregateDetail(player: player, holes: column.holes, value: \.bunkerShots))
                                }
                                row(label: "Penalties", columnWidth: columnWidth, height: 25 * rowScale) { column in
                                    scoreDetail(aggregateDetail(player: player, holes: column.holes, value: \.penalties))
                                }
                            }
                        }

                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .frame(width: scorecardWidth, height: scorecardHeight)
            .rotationEffect(.degrees(portrait ? 90 : 0))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
        }
        // Size and rotate within the safe area so the camera and home indicator
        // cannot cover the table; only the canvas extends to the screen edges.
        .background(PureLineStyle.canvas.ignoresSafeArea())
        .statusBarHidden(true)
        .preferredColorScheme(.light)
    }

    private func row<Cell: View>(label: String, columnWidth: CGFloat, isHeader: Bool = false, isEditable: Bool = false,
                                 height: CGFloat = 34,
                                 @ViewBuilder cell: @escaping (RoundScorecardColumn) -> Cell) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(label.uppercased())
                if label == "HOLE" {
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .frame(width: 26, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close scorecard")
                    .accessibilityIdentifier("close-round-scorecard")
                }
            }
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isHeader ? PureLineStyle.muted : PureLineStyle.ink)
                .frame(width: labelWidth - 8, height: height, alignment: .leading)
                .padding(.leading, 8)
                .background(isHeader ? PureLineStyle.surface : PureLineStyle.canvas)
                .overlay(alignment: .bottom) { Rectangle().fill(PureLineStyle.line).frame(height: 1) }

            ForEach(columns) { column in
                Group {
                    if isEditable, !isSaved, let onEditHole, let hole = column.hole {
                        Button { onEditHole(hole.number) } label: { cell(column) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit \(label) score on hole \(hole.number)")
                    } else {
                        cell(column)
                    }
                }
                .frame(width: columnWidth, height: height)
                .background(isHeader ? PureLineStyle.surface : PureLineStyle.canvas)
                .overlay {
                    Rectangle().strokeBorder(PureLineStyle.line.opacity(0.65), lineWidth: 0.5)
                }
            }
        }
        .background(isHeader ? PureLineStyle.surface : PureLineStyle.canvas)
    }

    private func parValue(for column: RoundScorecardColumn) -> String {
        if let hole = column.hole { return hole.par.map(String.init) ?? "—" }
        let pars = column.holes.compactMap(\.par)
        guard pars.count == column.holes.count else { return "—" }
        return String(pars.reduce(0, +))
    }

    private func aggregateScores(player: RoundPlayer, holes: [PlayedHole]) -> String {
        let scores = holes.compactMap { round.score(player: player.id, hole: $0.number) }
        guard !scores.isEmpty else { return "—" }
        return String(scores.reduce(0) { $0 + $1.strokes })
    }

    private func aggregateDetail(player: RoundPlayer, holes: [PlayedHole], value: (PlayedHoleScore) -> Int?) -> String {
        let scores = holes.compactMap { round.score(player: player.id, hole: $0.number) }
        let values = scores.compactMap(value)
        guard !values.isEmpty else { return "—" }
        return String(values.reduce(0, +))
    }

    private func aggregateFairways(player: RoundPlayer, holes: [PlayedHole]) -> String {
        let eligible = holes.filter { $0.par.map { $0 > 3 } == true }
        let answered = eligible.compactMap { hole -> Bool? in
            guard let outcome = round.score(player: player.id, hole: hole.number)?.fairway,
                  outcome != .unknown, outcome != .notApplicable else { return nil }
            return outcome == .hit
        }
        return hitPercentage(answered)
    }

    private func aggregateGreens(player: RoundPlayer, holes: [PlayedHole]) -> String {
        let answered = holes.compactMap { hole -> Bool? in
            guard let par = hole.par,
                  let score = round.score(player: player.id, hole: hole.number),
                  let putts = score.putts else { return nil }
            return score.strokes - putts <= par - 2
        }
        return hitPercentage(answered)
    }

    private func hitPercentage(_ results: [Bool]) -> String {
        guard !results.isEmpty else { return "—" }
        let percentage = (Double(results.filter { $0 }.count) / Double(results.count) * 100).rounded()
        return "\(Int(percentage))%"
    }

    @ViewBuilder
    private func scoreValue(_ score: PlayedHoleScore?, hole: PlayedHole) -> some View {
        if let score {
            GeometryReader { geometry in
                let size = max(12, min(30, geometry.size.width - 6, geometry.size.height - 6))
                Text(String(score.strokes))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(scoreColor(score, par: hole.par))
                    .frame(width: size, height: size)
                    .overlay {
                        if let par = hole.par {
                            scoreOutline(difference: score.strokes - par, size: size)
                                .foregroundStyle(scoreColor(score, par: par))
                        }
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .accessibilityLabel("\(score.strokes) strokes")
            .accessibilityValue(scoreDescription(score, par: hole.par))
        } else {
            Text("—")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(PureLineStyle.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func scoreOutline(difference: Int, size: CGFloat) -> some View {
        if difference < 0 {
            Circle().strokeBorder(lineWidth: 1)
            if difference <= -2 {
                Circle().strokeBorder(lineWidth: 1)
                    .frame(width: size - 5, height: size - 5)
            }
        } else if difference > 0 {
            Rectangle().strokeBorder(lineWidth: 1)
            if difference >= 2 {
                Rectangle().strokeBorder(lineWidth: 1)
                    .frame(width: size - 5, height: size - 5)
            }
        }
    }

    private func scoreDescription(_ score: PlayedHoleScore, par: Int?) -> String {
        guard let par else { return "" }
        switch score.strokes - par {
        case ...(-3): return "\(par - score.strokes) under par"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double bogey"
        default: return "\(score.strokes - par) over par"
        }
    }

    private func scoreDetail(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(PureLineStyle.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func fairwayCell(player: RoundPlayer, column: RoundScorecardColumn) -> some View {
        if let hole = column.hole {
            let score = round.score(player: player.id, hole: hole.number)
            if hole.par == 3 || !round.recordsDetailedScore(for: player) {
                scoreDetail("—")
            } else if let score, score.fairway != .unknown, score.fairway != .notApplicable {
                coloredMark(score.fairway == .hit ? "✓" : "×", color: .red)
            } else {
                scoreDetail("—")
            }
        } else if column.title == "OUT" || column.title == "IN" || column.title == "TOTAL" {
            let result = aggregateFairways(player: player, holes: column.holes)
            if result == "—" { scoreDetail("—") }
            else { coloredMark(result, color: .red) }
        } else {
            scoreDetail("—")
        }
    }

    @ViewBuilder
    private func greenCell(player: RoundPlayer, column: RoundScorecardColumn) -> some View {
        if let hole = column.hole {
            if let score = round.score(player: player.id, hole: hole.number),
               round.recordsDetailedScore(for: player),
               let putts = score.putts, let par = hole.par {
                coloredMark(score.strokes - putts <= par - 2 ? "✓" : "×", color: .green)
            } else {
                scoreDetail("—")
            }
        } else if column.title == "OUT" || column.title == "IN" || column.title == "TOTAL" {
            let result = aggregateGreens(player: player, holes: column.holes)
            if result == "—" { scoreDetail("—") }
            else { coloredMark(result, color: .green) }
        } else {
            scoreDetail("—")
        }
    }

    private func coloredMark(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
            .padding(.horizontal, 3)
            .padding(.vertical, 4)
    }

    private func fairwayResult(_ score: PlayedHoleScore?, hole: PlayedHole) -> String {
        guard hole.par != 3, let fairway = score?.fairway, fairway != .unknown, fairway != .notApplicable else { return "—" }
        return fairway == .hit ? "✓" : "×"
    }

    private func greenResult(_ score: PlayedHoleScore?, hole: PlayedHole) -> String {
        guard let score, let putts = score.putts, let par = hole.par else { return "—" }
        return score.strokes - putts <= par - 2 ? "✓" : "×"
    }

    private func scoreColor(_ score: PlayedHoleScore, par: Int?) -> Color {
        guard let par else { return PureLineStyle.ink }
        if score.strokes < par { return PureLineStyle.accent }
        if score.strokes > par { return PureLineStyle.muted }
        return PureLineStyle.ink
    }

    private func scorecardText(_ value: String, emphasized: Bool = false) -> some View {
        Text(value)
            .font(.system(size: 10, weight: emphasized ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(emphasized ? PureLineStyle.ink : PureLineStyle.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct RoundReviewView: View {
    let initialRound: PlayedRound
    var onEditHole: ((Int) -> Void)? = nil
    @Environment(PlayedRoundStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var hcpRounds: [GolfRound]
    @Query private var profiles: [PlayerProfile]
    @State private var playerID: UUID?
    @State private var confirmDiscard = false
    @State private var error: String?
    @State private var importMessage: String?

    private var round: PlayedRound {
        store.saved.first { $0.id == initialRound.id }
        ?? (store.active?.id == initialRound.id ? store.active : nil) ?? initialRound
    }
    private var isSaved: Bool { store.saved.contains { $0.id == round.id } }
    private var player: RoundPlayer? { round.players.first { $0.id == playerID } ?? round.owner }
    private var imported: Bool { hcpRounds.contains { $0.sourceSavedRoundID == round.id.uuidString } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.draftNeedsRetry {
                        Text("Latest draft changes are in memory only. Retry saving before quitting.").foregroundStyle(.red).font(.footnote)
                    }
                    Text(round.reference.courseName).font(.headline)
                    Text("\(round.reference.teeName) · \(round.holes.count) holes · \(round.game.rawValue)")
                    Text(round.date, format: .dateTime.day().month().year())
                    Text(isSaved ? "Saved in Statistics" : "Draft · not yet saved in Statistics")
                        .foregroundStyle(FairwayVectorColors.orange)
                    if round.players.count > 1 {
                        Picker("Player", selection: Binding(get: { player?.id ?? round.players[0].id }, set: { playerID = $0 })) {
                            ForEach(round.players) { Text($0.isOwner ? "You" : $0.name).tag($0.id) }
                        }
                    }
                }
                if let player {
                    totalsSection(player)
                    Section("Scorecard") { scorecardGrid }
                }
                Section("Handicap history · You only") {
                    Text("HCP score below is a local WHS differential estimate, not an official posted result. Saving Statistics does not add a handicap round automatically.")
                        .font(.footnote)
                    if let projected = PlayedRoundHandicapBridge.projectedIndex(round, history: hcpRounds,
                        lowHandicapIndex: profiles.first?.lowHandicapIndex) {
                        LabeledContent("Projected local index estimate", value: WHSCalculator.formatHCPScore(projected))
                        Text("Uses the existing shared history, exceptional-score adjustments and caps. Requires at least three existing scoring entries. This is a local projection, not an official new index.").font(.footnote)
                    }
                    if isSaved {
                        Button(imported ? "Already added to Handicap rounds" : "Add your score to Handicap rounds") {
                            do {
                                let added = try PlayedRoundHandicapBridge.add(round, context: context)
                                importMessage = added ? "Your score was saved to the existing Handicap history." : "This round is already in Handicap history."
                            } catch { self.error = error.localizedDescription }
                        }.disabled(imported || !PlayedRoundHandicapBridge.isEligible(round))
                    } else {
                        Text("Save to Statistics first to enable the optional HCP copy.").font(.footnote)
                    }
                    if round.holes.count == 9 {
                        Text("Nine-hole scores use the WHS expected Score Differential based on the Handicap Index at play. This local estimate is not an official posted result.").font(.footnote)
                    } else if !PlayedRoundHandicapBridge.isEligible(round) {
                        Text("Needs all 18 holes, actual par / unique SI, valid rating / slope and your index. This round is not eligible for Handicap import.").font(.footnote)
                    }
                    if let importMessage { Text(importMessage).font(.footnote) }
                }
                if !isSaved {
                    Section {
                        Button("Save round to Statistics", systemImage: "square.and.arrow.down") {
                            do { try store.saveActive() } catch { self.error = error.localizedDescription }
                        }.disabled(!round.isComplete || store.active?.id != round.id)
                        if !round.isComplete { Text("Every player must have valid strokes on every hole before saving.").font(.footnote) }
                        Button("Retry saving draft to device") {
                            do { try store.retryDraft() } catch { self.error = error.localizedDescription }
                        }
                        Button("Discard round", role: .destructive) { confirmDiscard = true }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .roundFormStyle()
            .navigationTitle(round.isComplete ? "Round summary" : "Round scorecard")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Discard this unsaved round?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard round", role: .destructive) {
                    do { try store.discardDraft(); dismiss() } catch { self.error = error.localizedDescription }
                }
            } message: { Text("All players' unsaved scores will be removed. Saved rounds and Handicap history are unaffected.") }
        }.tint(FairwayVectorColors.navy)
    }

    private var scorecardGrid: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    scorecardLabelCell("HOLE", header: true)
                    ForEach(round.holes) { hole in
                        scorecardCell(String(hole.number), header: true)
                    }
                }
                HStack(spacing: 0) {
                    scorecardLabelCell("PAR", header: true)
                    ForEach(round.holes) { hole in
                        scorecardCell(hole.par.map(String.init) ?? "—")
                    }
                }
                HStack(spacing: 0) {
                    scorecardLabelCell("HCP", header: true)
                    ForEach(round.holes) { hole in
                        scorecardCell(hole.strokeIndex.map(String.init) ?? "—")
                    }
                }
                ForEach(round.players) { player in
                    HStack(spacing: 0) {
                        scorecardLabelCell(player.isOwner ? "You" : player.name, header: true)
                        ForEach(round.holes) { hole in
                            let score = round.score(player: player.id, hole: hole.number)
                            scorecardScoreCell(score, hole: hole)
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(PureLineStyle.line, lineWidth: 1)
            }
        }
        .scrollIndicators(.visible)
        .accessibilityLabel("Round scorecard. Scroll horizontally to see all holes.")
    }

    private func scorecardLabelCell(_ title: String, header: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(header ? PureLineStyle.ink : PureLineStyle.muted)
            .frame(width: 76, height: 42, alignment: .leading)
            .padding(.leading, 8)
            .background(header ? PureLineStyle.surface : PureLineStyle.canvas)
            .overlay(alignment: .bottom) { Rectangle().fill(PureLineStyle.line).frame(height: 1) }
    }

    private func scorecardCell(_ value: String, header: Bool = false) -> some View {
        Text(value)
            .font(.system(size: 12, weight: header ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(PureLineStyle.ink)
            .frame(width: 44, height: 42)
            .background(header ? PureLineStyle.surface : PureLineStyle.canvas)
            .overlay {
                Rectangle().strokeBorder(PureLineStyle.line.opacity(0.65), lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private func scorecardScoreCell(_ score: PlayedHoleScore?, hole: PlayedHole) -> some View {
        Group {
            if !isSaved, let onEditHole {
                Button {
                    onEditHole(hole.number)
                    dismiss()
                } label: {
                    scorecardScoreValue(score, hole: hole)
                        .frame(width: 44, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(score == nil ? "Enter" : "Edit") score for hole \(hole.number)")
            } else {
                scorecardScoreValue(score, hole: hole)
                    .frame(width: 44, height: 42)
            }
        }
        .background(PureLineStyle.canvas)
        .overlay {
            Rectangle().strokeBorder(PureLineStyle.line.opacity(0.65), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func scorecardScoreValue(_ score: PlayedHoleScore?, hole: PlayedHole) -> some View {
        if let score {
            let relative = score.strokes - (hole.par ?? score.strokes)
            Text(String(score.strokes))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(relative < 0 ? PureLineStyle.accent : PureLineStyle.ink)
                .frame(width: 30, height: 30)
                .background(relative < 0 ? PureLineStyle.accent.opacity(0.12) : .clear, in: Circle())
                .overlay {
                    Circle().strokeBorder(relative < 0 ? PureLineStyle.accent.opacity(0.6) : .clear, lineWidth: 1)
                }
        } else {
            Text("—")
                .font(.system(size: 13, weight: .regular).monospacedDigit())
                .foregroundStyle(PureLineStyle.muted)
                .frame(width: 44, height: 42)
        }
    }

    @ViewBuilder private func totalsSection(_ player: RoundPlayer) -> some View {
        let t = PlayedRoundCalculator.totals(round: round, player: player)
        Section(player.isOwner ? "Your totals" : "\(player.name) · totals") {
            LabeledContent("Scored holes", value: "\(t.scoredHoles) / \(round.holes.count)")
            LabeledContent("Gross strokes", value: "\(t.gross)")
            LabeledContent("Net strokes", value: t.net.map(String.init) ?? "Unavailable")
            LabeledContent("Stableford", value: t.stableford.map { "\($0) points" } ?? "Unavailable")
            if t.puttHoles > 0 { LabeledContent("Putts", value: "\(t.putts) / \(t.puttHoles) recorded holes") }
            LabeledContent("Fairways", value: "\(t.fairwaysHit) / \(t.fairwaysAnswered) answered eligible holes")
            LabeledContent("GIR", value: "\(t.estimatedGIR) / \(t.girHoles) holes with putts & par")
            if t.bunkerAnswered > 0 { LabeledContent("Bunkers", value: "\(t.bunkerShots) shots · \(t.bunkerHoles) / \(t.bunkerAnswered) recorded holes") }
            if t.penaltyHoles > 0 { LabeledContent("Penalties (already included)", value: "\(t.penalties) / \(t.penaltyHoles) recorded holes") }
            Text("GIR is inferred from strokes − putts ≤ par − 2, not measured arrival; penalties and recovery play affect it.").font(.footnote)
        }
        Section("HCP score · distinct from net score") {
            LabeledContent("Handicap Index at play", value: player.handicapIndex.map { WHSCalculator.formatHCPScore($0) } ?? "Unknown")
            LabeledContent("Course Handicap", value: t.courseHandicap.map(String.init) ?? "Unavailable")
            LabeledContent("Playing Handicap (\(round.allowance)%)", value: t.playingHandicap.map(String.init) ?? "Unavailable")
            LabeledContent("Adjusted gross · net double bogey", value: t.adjustedGross.map(String.init) ?? "Unavailable")
            LabeledContent("HCP score · differential (PCC 0)", value: t.differential.map { WHSCalculator.formatHCPScore($0) } ?? "Unavailable")
            Text("Course Handicap uses the full index and applicable tee. WHS adjusted gross caps each hole at net double bogey with full Course Handicap. Net and points use Playing Handicap. Partial totals are not final differentials.").font(.footnote)
        }
    }
}

struct RoundStatisticsView: View {
    @Environment(PlayedRoundStore.self) private var store
    @State private var deleting: UUID?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Your game, over time", systemImage: "chart.xyaxis.line").font(.title2.bold())
                        .foregroundStyle(FairwayVectorColors.navy)
                    Text("Only explicitly saved rounds and your own scores contribute. Other players stay in the scorecard.")
                        .font(.footnote).foregroundStyle(FairwayVectorColors.slate)
                }
                if let error = store.errorMessage {
                    Section("Storage unavailable") {
                        Text(error).foregroundStyle(.red)
                        if store.draftNeedsRetry {
                            Button("Retry saving active draft") {
                                do { try store.retryDraft() } catch { self.error = error.localizedDescription }
                            }
                        } else { Button("Retry loading preserved rounds") { store.load() } }
                    }
                }
                if store.saved.isEmpty {
                    Section { ContentUnavailableView("No saved rounds", systemImage: "flag.checkered",
                        description: Text("Start a round from Home or Course, then explicitly save its summary here.")) }
                } else {
                    averages
                    Section("Saved rounds · \(store.saved.count)") {
                        ForEach(store.saved) { round in
                            NavigationLink {
                                RoundReviewView(initialRound: round)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(round.reference.courseName).font(.headline)
                                    Text("\(round.reference.teeName) · \(round.holes.count) holes · \(round.game.rawValue) · \(round.players.count) player(s)").font(.caption)
                                    HStack {
                                        Text(round.date, format: .dateTime.day().month().year())
                                        if let owner = round.owner {
                                            let t = PlayedRoundCalculator.totals(round: round, player: owner)
                                            Text("Gross \(t.gross) · Net \(t.net.map(String.init) ?? "—")")
                                            if round.game == .stableford {
                                                Text(t.stableford.map { "\($0) pts" } ?? "Points unavailable")
                                            }
                                        }
                                    }.font(.caption).foregroundStyle(FairwayVectorColors.slate)
                                }
                            }
                            .swipeActions { Button("Delete", role: .destructive) { deleting = round.id } }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .roundFormStyle()
            .navigationTitle("Rounds & statistics")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete saved round?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete from Statistics", role: .destructive) {
                    guard let id = deleting else { return }
                    do { try store.delete(id) } catch { self.error = error.localizedDescription }
                    deleting = nil
                }
            } message: { Text("All scorecard players are removed from Statistics. Any explicit copy already in Handicap rounds is retained; manage it in Handicap separately.") }
        }.tint(FairwayVectorColors.navy)
    }

    @ViewBuilder private var averages: some View {
        let s = RoundStatistics(rounds: store.saved)
        Section("Your averages · matched recorded holes") {
            metric("Gross strokes / hole", s.gross, s.holes)
            metric("Net strokes / hole", s.net, s.netHoles)
            metric("Putts / recorded hole", s.putts, s.puttHoles)
            metric("Fairways hit %", s.fairwaysHit, s.fairwaysAnswered, scale: 100)
            metric("GIR %", s.gir, s.girHoles, scale: 100)
            metric("Bunker holes %", s.bunkerHoles, s.bunkerAnswered, scale: 100)
            metric("Penalties / 18 recorded holes", s.penalties, s.penaltyHoles, scale: 18)
            Text("Fairways exclude par 3 and N/A/unanswered. GIR requires putts and actual par. Unknown details are excluded, not zero. GIR is inferred, not measured; total strokes include penalties.").font(.footnote)
        }
        ForEach([9, 18], id: \.self) { count in
            let rounds = store.saved.filter { $0.holes.count == count }
            let group = RoundStatistics(rounds: rounds)
            if !rounds.isEmpty {
                Section("\(count)-hole rounds · \(group.rounds)") {
                    metric("Gross strokes / round", group.gross, group.rounds)
                    let netRoundCount = rounds.filter { round in
                        round.owner.map { PlayedRoundCalculator.totals(round: round, player: $0).net != nil } ?? false
                    }.count
                    metric("Net strokes / rated round", group.net, netRoundCount)
                    let fullyRecordedPutts = rounds.compactMap { round -> Int? in
                        guard let owner = round.owner else { return nil }
                        let t = PlayedRoundCalculator.totals(round: round, player: owner)
                        return t.puttHoles == count ? t.putts : nil
                    }
                    metric("Putts / fully recorded round", fullyRecordedPutts.reduce(0, +), fullyRecordedPutts.count)
                }
            }
        }
    }
    private func metric(_ title: String, _ numerator: Int, _ denominator: Int, scale: Double = 1) -> some View {
        LabeledContent(title, value: RoundStatistics.rate(numerator, denominator, scale: scale)
            .map { String(format: "%.1f · n=%d", $0, denominator) } ?? "Not recorded")
    }
}

private extension View {
    func roundFormStyle() -> some View {
        self.scrollContentBackground(.hidden)
            .background(FairwayVectorColors.background)
            .listRowBackground(FairwayVectorColors.surface)
    }
}