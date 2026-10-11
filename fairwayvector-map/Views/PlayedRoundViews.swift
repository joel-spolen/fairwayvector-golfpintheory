import SwiftData
import SwiftUI

struct RoundSetupView: View {
    let selectedCourseReference: CourseReference
    let course: Course
    let onStarted: () -> Void
    @Environment(PlayedRoundStore.self) private var store
    @EnvironmentObject private var trajectoryModel: TrajectoryCalculatorViewModel
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [PlayerProfile]
    @Query(sort: \GolfRound.date, order: .reverse) private var hcpRounds: [GolfRound]
    @State private var game: RoundGame = .strokePlay
    @State private var detailMode: RoundDetailMode = .detailed
    @State private var players = [RoundPlayer(name: "You", isOwner: true, handicapIndex: nil)]
    @State private var error: String?
    @State private var initialized = false

    private var holes: [PlayedHole] {
        course.holes.map { PlayedHole(number: $0.number, par: $0.par, strokeIndex: $0.handicapIndex) }
    }
    private var candidate: PlayedRound {
        PlayedRound(reference: selectedCourseReference, course: course, holes: holes,
            players: players, game: game, detailMode: detailMode, allowance: 100)
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
                    Text("Scorecard").font(.subheadline.weight(.medium))
                    Picker("Scorecard", selection: $detailMode) {
                        ForEach(RoundDetailMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("Detailed records putts, fairway hits, bunker shots and penalties for every player. Putts default to two; bunker shots and penalties start at zero. Strokes only leaves those statistics unknown.")
                        .font(.caption).foregroundStyle(PureLineStyle.muted)
                }
                .pureLineCard()
                ForEach($players) { $player in
                    VStack(alignment: .leading, spacing: 14) {
                        Label(player.isOwner ? "You · personal statistics" : "Additional player", systemImage: "person")
                            .font(.headline)
                        if !player.isOwner {
                            TextField("Player name", text: $player.name)
                                .padding(12)
                                .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("Player name")
                        }
                        Toggle("Use Handicap Index", isOn: Binding(
                            get: { player.handicapIndex != nil },
                            set: { enabled in
                                player.handicapIndex = enabled ? (player.isOwner ? defaultOwnerHandicapIndex : 0) : nil
                            }))
                            .font(.subheadline)
                        if player.handicapIndex != nil {
                            LabeledContent("Handicap Index") {
                                TextField("Handicap Index", value: Binding(
                                    get: { player.handicapIndex ?? 0 }, set: { player.handicapIndex = $0 }), format: .number)
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
                            Button("Remove player", role: .destructive) { players.removeAll { $0.id == player.id } }
                                .font(.subheadline).foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pureLineCard()
                }
                    Button("Add player", systemImage: "person.badge.plus") {
                        players.append(RoundPlayer(name: "Player \(players.count + 1)", isOwner: false, handicapIndex: nil))
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(PureLineStyle.line, lineWidth: 1) }
                    .disabled(players.count >= 8)
                    if game == .stableford, players.contains(where: { $0.handicapIndex == nil }) {
                        Text("Players without an index can record gross strokes but have no net Stableford total. Enable an index and explicitly choose 0 for scratch if appropriate.")
                            .font(.caption).foregroundStyle(PureLineStyle.muted)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Start round", systemImage: "flag.checkered") {
                        do {
                            try store.start(candidate)
                            onStarted(); dismiss()
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
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
    let buttonTitle: String
    let onSave: ([UUID: PlayedHoleScore]) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [UUID: PlayedHoleScore] = [:]
    @State private var error: String?
    @State private var showingGIRInfo = false
    private var hole: PlayedHole? { round.holes.first { $0.number == holeNumber } }

    private func binding(_ player: UUID) -> Binding<PlayedHoleScore> {
        Binding(get: { entries[player] ?? PlayedHoleScore(strokes: 4) }, set: { entries[player] = $0 })
    }
    private var valid: Bool { round.players.allSatisfy { entries[$0.id]?.isValid == true } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HOLE \(holeNumber)")
                        .font(.caption.weight(.semibold)).tracking(1.2)
                        .foregroundStyle(PureLineStyle.muted)
                    Text("Par \(hole?.par.map(String.init) ?? "—") · HCP \(hole?.strokeIndex.map(String.init) ?? "—")")
                        .font(.title2.weight(.semibold))
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
                        if round.detailMode == .detailed {
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
                    Button(buttonTitle) {
                        guard valid else { return }
                        do { try onSave(entries); dismiss() }
                        catch { self.error = "Score remains in this form / active draft. Storage failed: \(error.localizedDescription)" }
                    }
                    .buttonStyle(PureLinePrimaryButtonStyle())
                    .disabled(!valid)
                }
                .padding(18)
            }
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .navigationTitle("Hole \(holeNumber) scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
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
            .onAppear {
                guard entries.isEmpty else { return }
                for player in round.players {
                    var score = round.score(player: player.id, hole: holeNumber) ?? PlayedHoleScore(strokes: hole?.par ?? 4)
                    if round.detailMode == .detailed {
                        score.putts = score.putts ?? min(2, max(0, score.strokes - (score.penalties ?? 0)))
                        score.bunkerShots = score.bunkerShots ?? 0
                        score.penalties = score.penalties ?? 0
                        if score.fairway == .unknown { score.fairway = .missed }
                    }
                    if hole?.par == 3 { score.fairway = .notApplicable }
                    entries[player.id] = score
                }
            }
        }.tint(PureLineStyle.accent)
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
            Text("Fairway").font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                fairwayButton(.hit, icon: "checkmark", selection: selection)
                fairwayButton(.left, icon: "arrow.left", selection: selection)
                fairwayButton(.right, icon: "arrow.right", selection: selection)
                fairwayButton(.long, icon: "arrow.up", selection: selection)
                fairwayButton(.short, icon: "arrow.down", selection: selection)
            }
            if selection.wrappedValue == .missed {
                Text("Missed · choose a direction to add detail")
                    .font(.caption).foregroundStyle(PureLineStyle.muted)
            }
        }
    }

    private func fairwayButton(_ outcome: RoundFairway, icon: String, selection: Binding<RoundFairway>) -> some View {
        let selected = selection.wrappedValue == outcome
        return Button { selection.wrappedValue = outcome } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.body.weight(.semibold))
                Text(outcome.label).font(.caption.weight(.semibold))
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
        .accessibilityLabel(outcome == .hit ? "Fairway hit" : "Fairway miss: \(outcome.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                    Section("Hole-by-hole scorecard") {
                        ForEach(round.holes) { hole in
                            let score = round.score(player: player.id, hole: hole.number)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("Hole \(hole.number) · Par \(hole.par.map(String.init) ?? "—") · HCP \(hole.strokeIndex.map(String.init) ?? "—")")
                                    Spacer()
                                    Text(score.map { "\($0.strokes)" } ?? "—").bold().monospacedDigit()
                                }
                                if let score, round.detailMode == .detailed {
                                    Text("Putts \(score.putts.map(String.init) ?? "—") · Fairway \(score.fairway.label) · Bunker shots \(score.bunkerShots.map(String.init) ?? "—") · Penalties \(score.penalties.map(String.init) ?? "—")")
                                        .font(.caption).foregroundStyle(FairwayVectorColors.slate)
                                }
                                    if let score, let rank = round.strokeRanks?[hole.number],
                                       let ch = PlayedRoundCalculator.courseHandicap(round: round, player: player), let par = hole.par {
                                        let ph = Int(floor(Double(ch) * Double(round.allowance) / 100 + 0.5))
                                        let received = PlayedRoundCalculator.strokes(handicap: ph, rank: rank, holeCount: round.holes.count)
                                        Text("Handicap strokes \(received) · Net \(score.strokes - received) · \(max(0, 2 + par - score.strokes + received)) points")
                                        .font(.caption).foregroundStyle(FairwayVectorColors.slate)
                                    }
                                if !isSaved, let onEditHole {
                                    Button(score == nil ? "Record this hole" : "Edit this hole") {
                                        onEditHole(hole.number); dismiss()
                                    }
                                }
                            }
                        }
                    }
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