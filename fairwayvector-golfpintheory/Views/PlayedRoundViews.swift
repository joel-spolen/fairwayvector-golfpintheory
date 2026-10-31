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
            get: { players.first(where: { $0.id == playerID }) ?? RoundPlayer(name: L("Player"), isOwner: false, handicapIndex: nil) },
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
                        ForEach(RoundGame.allCases) { Text(L($0.rawValue)).tag($0) }
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
                        Label(player.isOwner ? L("You · personal statistics") : L("Additional player"), systemImage: "person")
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
                        players.append(RoundPlayer(name: L("Player %@", "\(players.count + 1)"), isOwner: false,
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
                    Button(dismissOnCompletion ? L("Cancel") : L("Back")) {
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
    var onFinish: () -> Void = {}
    @Environment(PlayedRoundStore.self) private var roundStore
    @State private var entries: [UUID: PlayedHoleScore] = [:]
    @State private var loadedHole: Int?
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
        if offset > 0, holePosition == round.holes.count - 1 {
            onFinish()
            return
        }
        let pageIndex = holePosition * 2 + 1
        let destinationPage = pageIndex + offset
        let lastPage = round.holes.count * 2 - 1
        guard (0...lastPage).contains(destinationPage) else { return }
        onNavigateHole(round.holes[destinationPage / 2].number)
    }

    private func loadEntries(for number: Int) {
        // Page transitions and sheet dismissal can trigger onAppear again.
        // Never replace in-progress edits with an older round snapshot.
        guard loadedHole != number else { return }
        loadedHole = number
        let currentRound = roundStore.active.flatMap { $0.id == round.id ? $0 : nil } ?? round
        entries = [:]
        for player in round.players {
            let savedScore = currentRound.score(player: player.id, hole: number)
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
                        roundStore.draftNeedsRetry ? L("Save pending") : allPlayersScored ? L("Score saved") : hasSavedScore ? L("Partly scored") : L("No score yet"),
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
                            Label(player.isOwner ? L("You") : player.name, systemImage: "person")
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
                            detailCount(L("Putts"), value: score.putts, maximum: score.wrappedValue.strokes)
                            if hole?.par == 3 {
                                LabeledContent("Fairway", value: L("N/A · par 3"))
                            } else {
                                fairwaySelector(score.fairway)
                            }
                            detailCount(L("Bunker shots"), value: score.bunkerShots, maximum: score.wrappedValue.strokes)
                            detailCount(L("Penalty strokes"), value: score.penalties, maximum: score.wrappedValue.strokes)
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
                                    Text(score.wrappedValue.strokes - putts <= par - 2 ? L("Yes") : L("No"))
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
                    .accessibilityIdentifier("score-previous-page")

                    Button {
                        do {
                            try saveCurrentHole()
                            if holePosition == round.holes.count - 1 {
                                onFinish()
                            } else {
                                onNavigateHole(round.holes[holePosition + 1].number)
                            }
                        }
                        catch { self.error = L("Score could not be saved: %@", "\(error.localizedDescription)") }
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
                    .accessibilityLabel("Next page")
                    .accessibilityIdentifier("score-next-page")
                }
                .buttonStyle(.plain)
                .foregroundStyle(PureLineStyle.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(PureLineStyle.canvas)
            }
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .alert("Score could not be saved", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
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
            .onChange(of: holeNumber) { loadEntries(for: holeNumber) }
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
        case -4: L("Condor")
        case -3: L("Albatross")
        case -2: L("Eagle")
        case -1: L("Birdie")
        case 0: L("Par")
        case 1: L("Bogey")
        case 2: L("Double bogey")
        case 3: L("Triple bogey")
        case 4: L("Quadruple bogey")
        case let difference where difference < 0: L("%@ under par", "\(-difference)")
        case let difference: L("%@ over par", "\(difference)")
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
        let title = outcome == .hit ? L("FIR") : outcome == .missed ? L("Missed FIR") : outcome.label
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
        .accessibilityLabel(outcome == .hit ? L("Fairway hit") : outcome == .missed ? L("Fairway missed") : L("Fairway miss: %@", "\(outcome.label)"))
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
    var onViewHole: ((Int) -> Void)? = nil
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
                result.append(.subtotal(title: L("OUT"), holes: Array(orderedHoles[..<9]), key: "out"))
            } else if round.holes.count == 18, index == 17 {
                result.append(.subtotal(title: L("IN"), holes: Array(orderedHoles[9...]), key: "in"))
            } else if round.holes.count == 9, index == 8 {
                result.append(.subtotal(title: L("TOTAL"), holes: orderedHoles, key: "total"))
            }
        }
        if round.holes.count == 18 {
            result.append(.subtotal(title: L("TOTAL"), holes: orderedHoles, key: "total"))
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let portrait = geometry.size.height > geometry.size.width
            let scorecardWidth = max(geometry.size.width, geometry.size.height)
            let scorecardHeight = min(geometry.size.width, geometry.size.height)
            let closeButtonSpace: CGFloat = 52
            let rowInsets = EdgeInsets(
                top: 0,
                leading: portrait ? geometry.safeAreaInsets.top : geometry.safeAreaInsets.leading,
                bottom: 0,
                trailing: (portrait ? geometry.safeAreaInsets.bottom : geometry.safeAreaInsets.trailing) + closeButtonSpace
            )
            let columnWidth = max(1, (scorecardWidth - labelWidth - closeButtonSpace) / CGFloat(max(1, columns.count)))
            let naturalHeight = 102 + round.players.reduce(0) {
                $0 + 42 + (round.recordsDetailedScore(for: $1) ? 125 : 0)
            }
            let rowScale = max(1, scorecardHeight / CGFloat(naturalHeight))
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                        row(label: L("HOLE"), columnWidth: columnWidth, rowInsets: rowInsets, isHeader: true, height: 34 * rowScale) { column in
                            if let hole = column.hole, let onViewHole {
                                Button { onViewHole(hole.number) } label: {
                                    Text(String(hole.number))
                                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View hole \(hole.number) on course map")
                            } else {
                                Text(column.hole.map { String($0.number) } ?? (column.title == L("TOTAL") ? L("TOT") : column.title) ?? "—")
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                            }
                        }
                        row(label: L("PAR"), columnWidth: columnWidth, rowInsets: rowInsets, isHeader: true, height: 34 * rowScale) { column in
                            scorecardText(parValue(for: column), emphasized: true)
                        }
                        row(label: L("HCP"), columnWidth: columnWidth, rowInsets: rowInsets, isHeader: true, height: 34 * rowScale) { column in
                            scorecardText(column.hole?.strokeIndex.map(String.init) ?? "—")
                        }

                        ForEach(round.players) { player in
                            row(label: round.players.count == 1 ? L("Score") : player.isOwner ? L("You") : player.name,
                                columnWidth: columnWidth, rowInsets: rowInsets, isEditable: !isSaved, height: 42 * rowScale) { column in
                                if let hole = column.hole {
                                    scoreValue(round.score(player: player.id, hole: hole.number), hole: hole)
                                } else {
                                    scorecardText(aggregateScores(player: player, holes: column.holes), emphasized: true)
                                }
                            }
                            if round.recordsDetailedScore(for: player) {
                                row(label: L("Putts"), columnWidth: columnWidth, rowInsets: rowInsets, height: 25 * rowScale) { column in
                                    scoreDetail(aggregateDetail(player: player, holes: column.holes, value: \.putts))
                                }
                                row(label: L("FIR"), columnWidth: columnWidth, rowInsets: rowInsets, height: 25 * rowScale) { column in
                                    fairwayCell(player: player, column: column)
                                }
                                row(label: L("GIR"), columnWidth: columnWidth, rowInsets: rowInsets, height: 25 * rowScale) { column in
                                    greenCell(player: player, column: column)
                                }
                                row(label: L("Sand"), columnWidth: columnWidth, rowInsets: rowInsets, height: 25 * rowScale) { column in
                                    scoreDetail(aggregateDetail(player: player, holes: column.holes, value: \.bunkerShots))
                                }
                                row(label: L("Penalties"), columnWidth: columnWidth, rowInsets: rowInsets, height: 25 * rowScale) { column in
                                    scoreDetail(aggregateDetail(player: player, holes: column.holes, value: \.penalties))
                                }
                            }
                        }

                }
            }
            .scrollClipDisabled()
            .padding(.trailing, closeButtonSpace)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .frame(width: scorecardWidth, height: scorecardHeight)
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PureLineStyle.ink)
                        .frame(width: 44, height: 44)
                        .background(PureLineStyle.surface, in: Circle())
                        .overlay {
                            Circle().strokeBorder(PureLineStyle.ink.opacity(0.5), lineWidth: 1)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close scorecard")
                .accessibilityIdentifier("close-round-scorecard")
                .padding(4)
            }
            .rotationEffect(.degrees(portrait ? 90 : 0))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
        }
        // Keep scores and controls safe while row decoration extends to the edges.
        .background(PureLineStyle.canvas.ignoresSafeArea())
        .statusBarHidden(true)
        .preferredColorScheme(.light)
    }

    private func row<Cell: View>(label: String, columnWidth: CGFloat, rowInsets: EdgeInsets, isHeader: Bool = false, isEditable: Bool = false,
                                 height: CGFloat = 34,
                                 @ViewBuilder cell: @escaping (RoundScorecardColumn) -> Cell) -> some View {
        HStack(spacing: 0) {
            Text(label.uppercased())
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
        .background {
            (isHeader ? PureLineStyle.surface : PureLineStyle.canvas)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PureLineStyle.line).frame(height: 1)
                }
                .padding(.leading, -rowInsets.leading)
                .padding(.trailing, -rowInsets.trailing)
                .allowsHitTesting(false)
        }
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
        case ...(-3): return L("%@ under par", "\(par - score.strokes)")
        case -2: return L("Eagle")
        case -1: return L("Birdie")
        case 0: return L("Par")
        case 1: return L("Bogey")
        case 2: return L("Double bogey")
        default: return L("%@ over par", "\(score.strokes - par)")
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
        } else if column.title == L("OUT") || column.title == L("IN") || column.title == L("TOTAL") {
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
        } else if column.title == L("OUT") || column.title == L("IN") || column.title == L("TOTAL") {
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
    var isHistoryDetail = false
    @State private var notes = ""
    @State private var notesLoaded = false
    @State private var includeInHandicap = true
    @State private var confirmingSave = false
    var onEditHole: ((Int) -> Void)? = nil
    @Environment(PlayedRoundStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var hcpRounds: [GolfRound]
    @State private var playerID: UUID?
    @State private var error: String?

    private var round: PlayedRound {
        store.saved.first { $0.id == initialRound.id }
        ?? (store.active?.id == initialRound.id ? store.active : nil) ?? initialRound
    }
    private var isSaved: Bool { store.saved.contains { $0.id == round.id } }
    private var player: RoundPlayer? { round.players.first { $0.id == playerID } ?? round.owner }
    private var imported: Bool { hcpRounds.contains { $0.sourceSavedRoundID == round.id.uuidString } }
    private var hcpEligible: Bool { PlayedRoundHandicapBridge.isEligible(round) }

    @ViewBuilder
    var body: some View {
        if isHistoryDetail {
            reviewContent
        } else {
            NavigationStack { reviewContent }
                .tint(PureLineStyle.accent)
                .preferredColorScheme(.light)
        }
    }

    private var reviewContent: some View {
            Form {
                Section {
                    if store.draftNeedsRetry {
                        Text("Latest draft changes are in memory only. Retry saving before quitting.").foregroundStyle(.red).font(.footnote)
                    }
                    Text(round.reference.courseName).font(.headline)
                    LabeledContent("Tee", value: round.reference.teeName)
                    LabeledContent("Holes", value: String(round.holes.count))
                    LabeledContent("Par", value: String(round.reference.totalPar))
                    LabeledContent("Course rating", value: round.reference.courseRating.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("Slope rating", value: String(round.reference.slopeRating))
                    LabeledContent("Format", value: L(round.game.rawValue))
                    LabeledContent("Date") {
                        Text(round.date, format: .dateTime.day().month().year())
                    }
                    if round.players.count > 1 {
                        Picker("Player", selection: Binding(get: { player?.id ?? round.players[0].id }, set: { playerID = $0 })) {
                            ForEach(round.players) { Text($0.isOwner ? L("You") : $0.name).tag($0.id) }
                        }
                    }
                }
                .listRowBackground(PureLineStyle.canvas)
                if let player {
                    totalsSection(player)
                    Section("Scorecard") { scorecardGrid }
                        .listRowBackground(PureLineStyle.canvas)
                }
                if !isSaved {
                    Section("Notes") {
                        TextField("Add a note (optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    .listRowBackground(PureLineStyle.canvas)
                    Section {
                        Toggle("Save your round in HCP", isOn: Binding(
                            get: { hcpEligible && includeInHandicap },
                            set: { includeInHandicap = hcpEligible && $0 }
                        ))
                            .disabled(!hcpEligible)
                            .tint(PureLineStyle.accent)
                        if !hcpEligible {
                            Text("Not eligible for HCP. Complete the selected rated 9- or 18-hole layout with your Handicap Index. Scattered holes do not qualify; nine-hole rounds need a nine-hole rating. Demo courses are excluded.")
                                .font(.footnote).foregroundStyle(PureLineStyle.muted)
                        }
                        if !round.isComplete {
                            Text("Some holes are unplayed. You can still save this round to Statistics.")
                                .font(.footnote).foregroundStyle(PureLineStyle.muted)
                        }
                    }
                    .listRowBackground(PureLineStyle.canvas)
                }
                if isSaved, let notes = round.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Section("Notes") { Text(notes) }
                        .listRowBackground(PureLineStyle.canvas)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                        .listRowBackground(PureLineStyle.canvas)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .onAppear {
                if !hcpEligible { includeInHandicap = false }
                if !notesLoaded {
                    notes = round.notes ?? ""
                    notesLoaded = true
                }
            }
            .onChange(of: hcpEligible) {
                if !hcpEligible { includeInHandicap = false }
            }
            .navigationTitle(isHistoryDetail ? L("Round details") : L("Round summary"))
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isHistoryDetail {
                        Button { dismiss() } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isHistoryDetail {
                    Button("Save") {
                        if isSaved {
                            if includeInHandicap && !imported && PlayedRoundHandicapBridge.isEligible(round) {
                                saveRound()
                            } else {
                                dismiss()
                            }
                        } else if !round.isComplete || (includeInHandicap && !PlayedRoundHandicapBridge.isEligible(round)) {
                            confirmingSave = true
                        } else {
                            saveRound()
                        }
                    }
                    .fontWeight(.semibold)
                    }
                }
            }
            .navigationBarBackButtonHidden(isHistoryDetail)
            .confirmationDialog("Save this round?", isPresented: $confirmingSave, titleVisibility: .visible) {
                Button(includeInHandicap && !PlayedRoundHandicapBridge.isEligible(round)
                       ? L("Save without HCP") : L("Save round anyway")) {
                    saveRound()
                }
                Button("Keep editing", role: .cancel) { }
            } message: {
                Text((round.isComplete ? "" : L("Some holes have not been played or recorded. Missing scores will remain empty. "))
                     + (includeInHandicap && !PlayedRoundHandicapBridge.isEligible(round)
                        ? L("This round is not eligible for HCP and will be saved to Statistics only.")
                        : L("The round will be saved to Statistics.")))
            }
    }

    private func saveRound() {
        do {
            // Persist Statistics first; if HCP fails, retain this screen and allow retry.
            var snapshot = round
            if !isSaved {
                let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                snapshot.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
                try store.updateDraft(snapshot)
                try store.saveActive(allowIncomplete: true)
            }
            if includeInHandicap && PlayedRoundHandicapBridge.isEligible(snapshot) {
                _ = try PlayedRoundHandicapBridge.add(snapshot, context: context)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var scorecardGrid: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    scorecardLabelCell(L("HOLE"), header: true)
                    ForEach(round.holes) { hole in
                        scorecardCell(String(hole.number), header: true)
                    }
                }
                HStack(spacing: 0) {
                    scorecardLabelCell(L("PAR"), header: true)
                    ForEach(round.holes) { hole in
                        scorecardCell(hole.par.map(String.init) ?? "—")
                    }
                }
                HStack(spacing: 0) {
                    scorecardLabelCell(L("HCP"), header: true)
                    ForEach(round.holes) { hole in
                        scorecardCell(hole.strokeIndex.map(String.init) ?? "—")
                    }
                }
                ForEach(round.players) { player in
                    HStack(spacing: 0) {
                        scorecardLabelCell(player.isOwner ? L("You") : player.name, header: true)
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
        scorecardScoreValue(score, hole: hole)
            .frame(width: 44, height: 42)
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
        Section(player.isOwner ? L("Your totals") : L("%@ · totals", "\(player.name)")) {
            LabeledContent("Holes played", value: "\(t.scoredHoles)")
            LabeledContent("Gross strokes", value: "\(t.gross)")
            LabeledContent("Net strokes", value: t.net.map(String.init) ?? L("Unavailable"))
            LabeledContent("Stableford", value: t.stableford.map { L("%@ points", "\($0)") } ?? L("Unavailable"))
            LabeledContent("Putts", value: t.puttHoles > 0 ? "\(t.putts)" : "—")
            LabeledContent("Fairways", value: t.fairwaysAnswered > 0 ? "\(t.fairwaysHit)" : "—")
            LabeledContent("GIR", value: t.girHoles > 0 ? "\(t.estimatedGIR)" : "—")
            LabeledContent("Bunkers", value: t.bunkerAnswered > 0 ? "\(t.bunkerShots)" : "—")
            LabeledContent("Penalties", value: t.penaltyHoles > 0 ? "\(t.penalties)" : "—")
        }
        .listRowBackground(PureLineStyle.canvas)
    }
}

struct RoundStatisticsView: View {
    var body: some View {
        RoundStatisticsDashboard()
    }
}

private extension View {
    func roundFormStyle() -> some View {
        self.scrollContentBackground(.hidden)
            .background(FairwayVectorColors.background)
            .listRowBackground(FairwayVectorColors.surface)
    }
}