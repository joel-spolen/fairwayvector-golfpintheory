import Charts
import SwiftData
import SwiftUI

struct HolePerformanceSample {
    let par: Int
    let score: PlayedHoleScore

    var greenHit: Bool? {
        score.putts.map { score.strokes - $0 <= par - 2 }
    }
    var scramble: Bool? {
        guard greenHit == false else { return nil }
        return score.strokes <= par
    }
    var fairwayHit: Bool? {
        guard par > 3, score.fairway != .unknown, score.fairway != .notApplicable else { return nil }
        return score.fairway == .hit
    }
}

/// One owner-only record per round, with missing metrics kept distinct from zero.
struct RoundPerformanceRecord: Identifiable {
    let id: String
    let date: Date
    let title: String
    let holes: Int
    let gross: Int?
    let adjustedGross: Int?
    let differential: Double?
    let played: PlayedRound?
    let handicap: GolfRound?
    var putts = 0
    var puttHoles = 0
    var fairways = 0
    var fairwayHoles = 0
    var greens = 0
    var greenHoles = 0
    var penalties = 0
    var penaltyHoles = 0
    var bunkerHoles = 0
    var bunkerAnswered = 0
    var outcomes: [Int] = []
    var scoresByPar: [Int: [Int]] = [:]
    var holeDetails: [HolePerformanceSample] = []

    static func combined(played: [PlayedRound], handicap: [GolfRound]) -> [Self] {
        let savedIDs = Set(played.map { $0.id.uuidString })
        var records: [Self] = played.compactMap { round in
            guard let owner = round.owner else { return nil }
            let totals = PlayedRoundCalculator.totals(round: round, player: owner)
            let linked = handicap.first { $0.sourceSavedRoundID == round.id.uuidString }
            var record = Self(id: round.id.uuidString, date: round.date,
                title: round.reference.courseName, holes: totals.scoredHoles,
                gross: totals.scoredHoles > 0 ? totals.gross : nil,
                adjustedGross: totals.adjustedGross,
                differential: linked?.handicapDifferential ?? totals.differential,
                played: round, handicap: linked,
                putts: totals.putts, puttHoles: totals.puttHoles,
                fairways: totals.fairwaysHit, fairwayHoles: totals.fairwaysAnswered,
                greens: totals.estimatedGIR, greenHoles: totals.girHoles,
                penalties: totals.penalties, penaltyHoles: totals.penaltyHoles,
                bunkerHoles: totals.bunkerHoles, bunkerAnswered: totals.bunkerAnswered)
            record.outcomes = round.holes.compactMap { hole in
                guard let par = hole.par,
                      let score = round.score(player: owner.id, hole: hole.number), score.isValid else { return nil }
                return score.strokes - par
            }
            for hole in round.holes {
                guard let par = hole.par,
                      let score = round.score(player: owner.id, hole: hole.number), score.isValid else { continue }
                if (3...5).contains(par) {
                    record.scoresByPar[par, default: []].append(score.strokes)
                }
                if round.recordsDetailedScore(for: owner) {
                    record.holeDetails.append(HolePerformanceSample(par: par, score: score))
                }
            }
            return record
        }
        for round in handicap where !savedIDs.contains(round.sourceSavedRoundID ?? "") {
            // HCP adjusted gross is not actual gross. Never mix these measures.
            let scores = round.holeScores ?? []
            let validScores = scores.filter { $0 > 0 }
            let hasScores = !scores.isEmpty && scores.count == round.holes && validScores.count == scores.count
            var record = Self(id: "hcp-\(round.persistentModelID)", date: round.date,
                title: round.courseName.isEmpty ? L("HCP round") : round.courseName,
                holes: round.holes, gross: hasScores ? scores.reduce(0, +) : nil,
                adjustedGross: round.adjustedGrossScore, differential: round.handicapDifferential,
                played: nil, handicap: round)
            if hasScores, let pars = round.holePars, pars.count == scores.count, pars.allSatisfy({ $0 > 0 }) {
                record.outcomes = zip(scores, pars).map { $0 - $1 }
                for (score, par) in zip(scores, pars) where (3...5).contains(par) {
                    record.scoresByPar[par, default: []].append(score)
                }
            }
            records.append(record)
        }
        return records.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}

struct RoundStatisticsDashboard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayedRoundStore.self) private var store
    @Query(sort: \GolfRound.date, order: .reverse) private var handicapRounds: [GolfRound]
    @State private var deleting: UUID?
    @State private var error: String?

    private var records: [RoundPerformanceRecord] {
        RoundPerformanceRecord.combined(played: store.saved, handicap: handicapRounds)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PureLinePageHeader(title: L("Rounds & statistics"),
                        subtitle: L("See your progress and discover where you can improve."))
                    if let message = store.errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(.footnote).foregroundStyle(.red)
                            Button("Try again") {
                                if store.draftNeedsRetry {
                                    do { try store.retryDraft() } catch { self.error = error.localizedDescription }
                                } else { store.load() }
                            }
                        }.pureLineCard()
                    }
                    if records.isEmpty {
                        ContentUnavailableView("Your story starts here", systemImage: "chart.xyaxis.line",
                            description: Text("Save your first round to see your averages and trends."))
                    } else {
                        overview
                        scoringByPar
                        holeTypeDetails
                        scrambling
                        scoringTrend
                        handicapTrend
                        accuracy
                        scoringMix
                        history
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(24)
            }
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .navigationTitle("Rounds & statistics")
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                PureLineHomeButton { dismiss() }
            }
            .confirmationDialog("Delete saved scorecard?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("Delete scorecard", role: .destructive) {
                    guard let id = deleting else { return }
                    do { try store.delete(id) } catch { self.error = error.localizedDescription }
                    deleting = nil
                }
            } message: {
                Text("This removes the scorecard, but keeps any saved handicap result. You can remove that separately in Handicap.")
            }
        }
        .tint(PureLineStyle.accent)
        .preferredColorScheme(.light)
    }

    private var overview: some View {
        let data = records
        let scored = data.filter { $0.gross != nil && $0.holes > 0 }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(L("Rounds"), value: String(data.count), detail: L("Your round history"))
            statCard(L("Strokes / hole"), value: average(scored.compactMap(\.gross).reduce(0, +), scored.reduce(0) { $0 + $1.holes }), detail: L("Average score"))
            statCard(L("Putts / hole"), value: average(data.reduce(0) { $0 + $1.putts }, data.reduce(0) { $0 + $1.puttHoles }), detail: L("Average putts"))
            statCard(L("Penalties / 18"), value: average(data.reduce(0) { $0 + $1.penalties }, data.reduce(0) { $0 + $1.penaltyHoles }, scale: 18), detail: L("Average per 18 holes"))
        }
    }

    private func statCard(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(PureLineStyle.muted)
            Text(value).font(.system(size: 29, weight: .semibold)).monospacedDigit().tracking(-1)
            Text(detail).font(.caption2).foregroundStyle(PureLineStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
    }

    private var scoringByPar: some View {
        let groups = (3...5).map { par in
            (par: par, scores: records.flatMap { $0.scoresByPar[par] ?? [] })
        }
        return VStack(alignment: .leading, spacing: 16) {
            chartHeading(L("Scoring by par"), detail: L("Your average score on each type of hole"))
            HStack(alignment: .top, spacing: 12) {
                ForEach(groups, id: \.par) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Par \(group.par)")
                            .font(.caption.weight(.medium)).foregroundStyle(PureLineStyle.muted)
                        Text(average(group.scores.reduce(0, +), group.scores.count))
                            .font(.title2.weight(.semibold)).monospacedDigit()
                        Text(group.scores.isEmpty ? L("No scores yet") : L("%@ holes", "\(group.scores.count)"))
                            .font(.caption2).foregroundStyle(PureLineStyle.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            if groups.contains(where: { !$0.scores.isEmpty }) {
                Chart(groups.filter { !$0.scores.isEmpty }, id: \.par) { group in
                    let value = Double(group.scores.reduce(0, +)) / Double(group.scores.count)
                    BarMark(x: .value(L("Hole type"), L("Par %@", "\(group.par)")), y: .value(L("Average score"), value))
                        .cornerRadius(4)
                        .foregroundStyle(PureLineStyle.accent.gradient)
                        .accessibilityLabel("Par \(group.par)")
                        .accessibilityValue("Average \(value.formatted(.number.precision(.fractionLength(1)))) strokes across \(group.scores.count) holes")
                }
                .frame(height: 150)
            }
        }.pureLineCard()
    }

    private var holeTypeDetails: some View {
        let samples = records.flatMap(\.holeDetails)
        return VStack(alignment: .leading, spacing: 16) {
            chartHeading(L("Your game by hole type"), detail: L("See where you play your best"))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 16) {
                GridRow {
                    Text("Average").foregroundStyle(PureLineStyle.muted)
                    ForEach(3...5, id: \.self) { par in
                        Text("Par \(par)").fontWeight(.semibold)
                    }
                }
                detailAverageRow(L("Putts"), samples: samples, value: \.putts)
                detailAverageRow(L("Sand shots"), samples: samples, value: \.bunkerShots)
                detailAverageRow(L("Penalties"), samples: samples, value: \.penalties)
                GridRow {
                    Text("Fairways hit")
                    ForEach(3...5, id: \.self) { par in
                        Text(par == 3 ? "—" : percentage(samples.filter { $0.par == par }.compactMap(\.fairwayHit)))
                            .monospacedDigit()
                    }
                }
                GridRow {
                    Text("GIR")
                    ForEach(3...5, id: \.self) { par in
                        Text(percentage(samples.filter { $0.par == par }.compactMap(\.greenHit)))
                            .monospacedDigit()
                    }
                }
                GridRow {
                    Text("Scrambling")
                    ForEach(3...5, id: \.self) { par in
                        Text(percentage(samples.filter { $0.par == par }.compactMap(\.scramble)))
                            .monospacedDigit()
                    }
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Shot averages are per hole. Add shot details to see more of your game.")
                .font(.caption2).foregroundStyle(PureLineStyle.muted)
        }.pureLineCard()
    }

    private func detailAverageRow(_ title: String, samples: [HolePerformanceSample],
                                  value: @escaping (PlayedHoleScore) -> Int?) -> some View {
        GridRow {
            Text(title)
            ForEach(3...5, id: \.self) { par in
                let values = samples.filter { $0.par == par }.compactMap { value($0.score) }
                Text(average(values.reduce(0, +), values.count)).monospacedDigit()
            }
        }
    }

    private var scrambling: some View {
        let results = records.flatMap(\.holeDetails).compactMap(\.scramble)
        return VStack(alignment: .leading, spacing: 16) {
            chartHeading(L("Scrambling"), detail: L("Saving par after missing the green in regulation"))
            accuracyRing(L("All holes"), hits: results.filter { $0 }.count, total: results.count)
            if !results.isEmpty {
                Text("\(results.filter { $0 }.count) par saves or better from \(results.count) missed greens")
                    .font(.caption).foregroundStyle(PureLineStyle.muted)
            }
            Text("Estimated from your score and putts, like GIR.")
                .font(.caption2).foregroundStyle(PureLineStyle.muted)
        }.pureLineCard()
    }

    private func percentage(_ results: [Bool]) -> String {
        guard !results.isEmpty else { return "—" }
        return "\(Int((Double(results.filter { $0 }.count) / Double(results.count) * 100).rounded()))%"
    }

    private var scoringTrend: some View {
        let points = records.filter { $0.gross != nil && $0.holes > 0 }
        return VStack(alignment: .leading, spacing: 16) {
            chartHeading(L("Scoring trend"), detail: L("Your average strokes per hole over time"))
            if points.isEmpty {
                chartEmpty(L("Add hole scores to see your scoring trend."))
            } else {
                Chart(Array(points.enumerated()), id: \.element.id) { index, record in
                    let value = Double(record.gross ?? 0) / Double(record.holes)
                    LineMark(x: .value(L("Round"), index + 1), y: .value(L("Strokes / hole"), value))
                        .foregroundStyle(PureLineStyle.accent)
                    PointMark(x: .value(L("Round"), index + 1), y: .value(L("Strokes / hole"), value))
                        .foregroundStyle(PureLineStyle.accent)
                        .accessibilityLabel(record.title)
                        .accessibilityValue("\(record.date.formatted(date: .abbreviated, time: .omitted)), \(value.formatted(.number.precision(.fractionLength(1)))) strokes per hole")
                    if index == 0 {
                        RuleMark(y: .value(L("Average"), Double(points.compactMap(\.gross).reduce(0, +)) / Double(points.reduce(0) { $0 + $1.holes })))
                            .foregroundStyle(PureLineStyle.muted.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXAxisLabel(L("Earlier → Latest"))
                .frame(height: 180)
            }
            Text("The dashed line shows your overall average.")
                .font(.caption2).foregroundStyle(PureLineStyle.muted)
        }.pureLineCard()
    }

    private var handicapTrend: some View {
        let points = records.filter { $0.differential?.isFinite == true }
        return VStack(alignment: .leading, spacing: 16) {
            chartHeading(L("Handicap performance"), detail: L("Your HCP scores over time · lower is better"))
            if points.isEmpty {
                chartEmpty(L("Save a handicap round to see your progress here."))
            } else {
                Text(average(points.compactMap(\.differential)))
                    .font(.title.weight(.semibold)).monospacedDigit()
                Text("Average HCP score · \(points.count) rounds")
                    .font(.caption).foregroundStyle(PureLineStyle.muted)
                Chart(Array(points.enumerated()), id: \.element.id) { index, record in
                    BarMark(x: .value(L("Round"), index + 1), y: .value(L("HCP score"), record.differential ?? 0))
                        .cornerRadius(3)
                        .foregroundStyle(PureLineStyle.accent.gradient)
                        .accessibilityLabel(record.title)
                        .accessibilityValue("HCP score \((record.differential ?? 0).formatted(.number.precision(.fractionLength(1))))")
                }
                .chartXAxisLabel(L("Earlier → Latest"))
                .frame(height: 160)
            }
        }.pureLineCard()
    }

    private var accuracy: some View {
        let data = records
        return VStack(alignment: .leading, spacing: 16) {
            chartHeading(L("Finding your targets"), detail: L("Fairways hit and greens in regulation"))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    accuracyRing(L("Fairways"), hits: data.reduce(0) { $0 + $1.fairways }, total: data.reduce(0) { $0 + $1.fairwayHoles })
                    accuracyRing(L("GIR"), hits: data.reduce(0) { $0 + $1.greens }, total: data.reduce(0) { $0 + $1.greenHoles })
                }
                VStack(spacing: 20) {
                    accuracyRing(L("Fairways"), hits: data.reduce(0) { $0 + $1.fairways }, total: data.reduce(0) { $0 + $1.fairwayHoles })
                    accuracyRing(L("GIR"), hits: data.reduce(0) { $0 + $1.greens }, total: data.reduce(0) { $0 + $1.greenHoles })
                }
            }
            Text("Par 3s don't count toward fairways hit. GIR is estimated from your score and putts.")
                .font(.caption2).foregroundStyle(PureLineStyle.muted)
            LabeledContent("Holes with bunker shots", value: average(data.reduce(0) { $0 + $1.bunkerHoles }, data.reduce(0) { $0 + $1.bunkerAnswered }, scale: 100) + (data.contains { $0.bunkerAnswered > 0 } ? "%" : ""))
                .font(.caption)
        }.pureLineCard()
    }

    private func accuracyRing(_ title: String, hits: Int, total: Int) -> some View {
        VStack(spacing: 10) {
            Chart {
                SectorMark(angle: .value(L("Hit"), hits), innerRadius: .ratio(0.8), angularInset: 2)
                    .foregroundStyle(PureLineStyle.accent)
                SectorMark(angle: .value(L("Miss"), max(0, total - hits)), innerRadius: .ratio(0.8), angularInset: 2)
                    .foregroundStyle(PureLineStyle.line)
                if total == 0 {
                    SectorMark(angle: .value(L("No data"), 1), innerRadius: .ratio(0.8))
                        .foregroundStyle(PureLineStyle.line)
                }
            }
            .frame(width: 120, height: 120)
            .overlay {
                Text(total > 0 ? "\(Int((Double(hits) / Double(total) * 100).rounded()))%" : "—")
                    .font(.title2.weight(.semibold)).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(total > 0 ? L("%@ hits from %@ holes", "\(hits)", "\(total)") : L("No data yet"))
            Text(title).font(.subheadline.weight(.semibold))
            Text(total > 0 ? L("Across %@ holes", "\(total)") : L("No data yet"))
                .font(.caption2).foregroundStyle(PureLineStyle.muted)
        }.frame(maxWidth: .infinity)
    }

    private var scoringMix: some View {
        let outcomes = records.flatMap(\.outcomes)
        let labels = [L("Birdie or better"), L("Par"), L("Bogey"), L("Double bogey or worse")]
        let counts = [outcomes.filter { $0 < 0 }.count, outcomes.filter { $0 == 0 }.count,
                      outcomes.filter { $0 == 1 }.count, outcomes.filter { $0 >= 2 }.count]
        let colors = [PureLineStyle.accent, Color(red: 0.35, green: 0.62, blue: 0.58),
                      Color(red: 0.80, green: 0.60, blue: 0.33), PureLineStyle.muted]
        return VStack(alignment: .leading, spacing: 16) {
            chartHeading(L("Your scoring mix"), detail: L("How often you score par, birdie or bogey"))
            if outcomes.isEmpty {
                chartEmpty(L("Add hole-by-hole scores to see your scoring mix."))
            } else {
                Chart(0..<4, id: \.self) { index in
                    SectorMark(angle: .value(L("Holes"), counts[index]), innerRadius: .ratio(0.65), angularInset: 2)
                        .cornerRadius(3)
                        .foregroundStyle(colors[index])
                        .accessibilityLabel(labels[index])
                        .accessibilityValue("\(counts[index]) holes")
                }
                .frame(height: 185)
                .overlay {
                    VStack(spacing: 3) {
                        Text(String(outcomes.count)).font(.title.weight(.semibold)).monospacedDigit()
                        Text("holes").font(.caption).foregroundStyle(PureLineStyle.muted)
                    }
                }
                ForEach(0..<4, id: \.self) { index in
                    HStack {
                        Circle().fill(colors[index]).frame(width: 8, height: 8)
                        Text(labels[index])
                        Spacer()
                        Text("\(counts[index]) · \(Int((Double(counts[index]) / Double(outcomes.count) * 100).rounded()))%")
                            .monospacedDigit()
                    }.font(.caption)
                }
            }
        }.pureLineCard()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 16) {
            chartHeading(L("Round history"), detail: L("%@ rounds · newest first", "\(records.count)"))
            ForEach(records.reversed()) { record in
                NavigationLink {
                    if let round = record.played {
                        RoundReviewView(initialRound: round, isHistoryDetail: true)
                    } else if let round = record.handicap {
                        StatisticsHandicapDetail(round: round)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: record.handicap != nil ? "chart.line.uptrend.xyaxis" : "flag")
                            .foregroundStyle(PureLineStyle.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.title).font(.subheadline.weight(.semibold))
                            Text("\(record.date.formatted(date: .abbreviated, time: .omitted)) · \(record.holes) holes")
                                .font(.caption).foregroundStyle(PureLineStyle.muted)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 4) {
                            if let gross = record.gross {
                                Text(String(gross)).font(.title3.weight(.semibold)).monospacedDigit()
                                Text("strokes").font(.caption2).foregroundStyle(PureLineStyle.muted)
                            } else if let adjusted = record.adjustedGross {
                                Text(String(adjusted)).font(.title3.weight(.semibold)).monospacedDigit()
                                Text("adjusted score").font(.caption2).foregroundStyle(PureLineStyle.muted)
                            }
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(PureLineStyle.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let round = record.played {
                        Button("Delete scorecard", role: .destructive) { deleting = round.id }
                    }
                }
                Divider().overlay(PureLineStyle.line)
            }
        }
    }

    private func chartHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(PureLineStyle.muted)
        }
    }

    private func chartEmpty(_ message: String) -> some View {
        Text(message).font(.subheadline).foregroundStyle(PureLineStyle.muted)
            .frame(maxWidth: .infinity, minHeight: 90)
    }

    private func average(_ numerator: Int, _ denominator: Int, scale: Double = 1) -> String {
        guard denominator > 0 else { return "—" }
        return (Double(numerator) / Double(denominator) * scale).formatted(.number.precision(.fractionLength(1)))
    }

    private func average(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "—" }
        return (values.reduce(0, +) / Double(values.count)).formatted(.number.precision(.fractionLength(1)))
    }
}

private struct StatisticsHandicapDetail: View {
    let round: GolfRound
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RoundDetailView(round: round, handicapIndex: nil)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
    }
}