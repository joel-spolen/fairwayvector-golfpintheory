//
//  ContentView.swift
//  fairwayvector-hcp-projection
//

import Charts
import SwiftData
import SwiftUI

// Native entry and swipe actions remain intact; these modifiers only style HCP lists.
private extension View {
    func hcpPureLineList() -> some View {
        self
            .listStyle(.insetGrouped)
            .listSectionSpacing(18)
            .listRowSeparatorTint(PureLineStyle.line)
            .environment(\.defaultMinListRowHeight, 52)
            .scrollContentBackground(.hidden)
            .background(PureLineStyle.canvas)
            .tint(PureLineStyle.accent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct HCPPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        PureLinePageHeader(title: title, subtitle: subtitle)
            .padding(18)
            .background(PureLineStyle.canvas)
    }
}

private struct HCPPureLineIntro: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(PureLineStyle.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(PureLineStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .listRowBackground(PureLineStyle.canvas)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}

private struct HCPNineHoleNotice: View {
    var currentHandicap: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nine-hole WHS estimate", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PureLineStyle.accent)
            Text(currentHandicap == nil
                 ? L("The WHS expected 9-hole differential requires an established Handicap Index. Until one is available, this round cannot contribute an estimated differential.")
                 : L("The 9-hole Score Differential is combined with the WHS expected 9-hole differential based on your current Handicap Index. This is a local estimate; confirm official posting with your handicap provider."))
                .font(.caption)
                .foregroundStyle(PureLineStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct HCPProjectionRootView: View {
    private enum Tab: String, CaseIterable { 
        case home
        case predict
        case round

        var title: String {
            switch self {
            case .home: AppLanguage.localized("Overview")
            case .predict: AppLanguage.localized("Predict")
            case .round: AppLanguage.localized("Add round")
            }
        }

        var pageTitle: String {
            switch self {
            case .home: AppLanguage.localized("Your handicap")
            case .predict: AppLanguage.localized("Plan your next round")
            case .round: AppLanguage.localized("Record a round")
            }
        }

        var pageSubtitle: String {
            switch self {
            case .home: AppLanguage.localized("Track your rounds. Plan your next score.")
            case .predict: AppLanguage.localized("Choose a course and tee to see how your score could move your Handicap Index.")
            case .round: AppLanguage.localized("Select your course and tee, or enter an official HCP score without a course.")
            }
        }
    }

    let courseCatalog: CourseCatalogStore
    var onHome: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<GolfClub> { $0.isCustom == true }, sort: \GolfClub.name) private var clubs: [GolfClub]
    @Query(filter: #Predicate<GolfCourse> { $0.isCustom == true }, sort: \GolfCourse.name) private var courses: [GolfCourse]
    @Query(filter: #Predicate<TeeSet> { $0.isCustom == true }, sort: \TeeSet.name) private var tees: [TeeSet]
    @Query(sort: \GolfRound.date, order: .reverse) private var rounds: [GolfRound]
    @Query private var profiles: [PlayerProfile]
    @State private var selectedTab = Tab.home

    var body: some View {
        VStack(spacing: 0) {
            PureLineHomeButton(onHome: onHome)
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(selectedTab == tab ? PureLineStyle.accent : PureLineStyle.muted)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding(.horizontal, 4)
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(PureLineStyle.canvas)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(PureLineStyle.line, lineWidth: 1)
                                        }
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                    .accessibilityHint("Shows the \(tab.title.lowercased()) handicap tool")
                }
            }
            .padding(4)
            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(PureLineStyle.canvas)
            .accessibilityElement(children: .contain)
                    .accessibilityLabel(AppLanguage.localized("Handicap tools"))

            Group {
                switch selectedTab {
                case .home:
                    HomeView(courseCatalog: courseCatalog, rounds: rounds, profile: profiles.first, clubs: clubs, courses: courses, tees: tees, onAddRound: { selectedTab = .round }, onPredict: { selectedTab = .predict }, pageTitle: selectedTab.pageTitle, pageSubtitle: selectedTab.pageSubtitle, onHome: onHome)
                case .predict:
                    TargetCalculatorView(courseCatalog: courseCatalog, clubs: clubs, courses: courses, tees: tees, rounds: rounds, profile: profiles.first, pageTitle: selectedTab.pageTitle, pageSubtitle: selectedTab.pageSubtitle, onHome: onHome)
                case .round:
                    NewRoundView(courseCatalog: courseCatalog, clubs: clubs, courses: courses, tees: tees, rounds: rounds, profile: profiles.first, pageTitle: selectedTab.pageTitle, pageSubtitle: selectedTab.pageSubtitle, onHome: onHome)
                }
            }
        }
        .tint(PureLineStyle.accent)
        .foregroundStyle(PureLineStyle.ink)
        .preferredColorScheme(.light)
        .onAppear {
            SeedData.loadIfNeeded(modelContext: modelContext)
        }
    }
}

#Preview {
    HCPProjectionRootView(courseCatalog: CourseCatalogStore())
        .modelContainer(for: [PlayerProfile.self, GolfClub.self, GolfCourse.self, TeeSet.self, GolfRound.self], inMemory: true)
}

private struct HomeView: View {
    let courseCatalog: CourseCatalogStore
    var rounds: [GolfRound]
    var profile: PlayerProfile?
    var clubs: [GolfClub]
    var courses: [GolfCourse]
    var tees: [TeeSet]
    let onAddRound: () -> Void
    var onPredict: (() -> Void)? = nil
    var pageTitle = L("Your handicap")
    var pageSubtitle = L("Track your rounds. Plan your next score.")
    var onHome: () -> Void = {}

    private var entries: [ScoringRecordEntry] {
        WHSCalculator.scoringEntries(from: rounds, lowHandicapIndex: profile?.lowHandicapIndex)
    }

    private var handicapIndex: Double? {
        WHSCalculator.handicapIndex(from: entries, lowHandicapIndex: profile?.lowHandicapIndex)
    }

    private var handicapRounds: [GolfRound] {
        Array(rounds.sorted { $0.date > $1.date }.prefix(20))
    }

    private var trendPoints: [HCPTrendPoint] {
        WHSCalculator.handicapProgression(from: rounds, lowHandicapIndex: profile?.lowHandicapIndex)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HCPPageHeader(title: pageTitle, subtitle: pageSubtitle)
                VStack(alignment: .leading, spacing: 24) {
                    metricLinks

                    VStack(spacing: 8) {
                        Button(action: onAddRound) {
                            Label("Add round", systemImage: "plus")
                        }
                        .buttonStyle(PureLinePrimaryButtonStyle())

                        if let onPredict {
                            Button(action: onPredict) {
                                Label("Predict your next Handicap Index", systemImage: "arrow.up.right")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(PureLineStyle.accent)
                        }
                    }

                    HCPTrendGraphCard(
                        trendPoints: trendPoints,
                        currentHandicap: handicapIndex
                    )

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Recent rounds")
                            .font(.title3.weight(.semibold))
                        if rounds.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.title2)
                                    .foregroundStyle(PureLineStyle.accent)
                                Text("No Rounds Yet")
                                    .font(.headline)
                                Text("Add a round to start tracking your Handicap Index.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        } else {
                            ForEach(rounds.prefix(5)) { round in
                                NavigationLink(destination: RoundDetailView(round: round, handicapIndex: handicapIndex)) {
                                    RoundRow(round: round)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .pureLineCard()
                }
                .padding(18)
                }
            }
            .background(PureLineStyle.canvas)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var handicapIndexText: String {
        handicapIndex.map { WHSCalculator.formatHCPScore($0) } ?? "N/A"
    }

    @ViewBuilder
    private var metricLinks: some View {
        NavigationLink(destination: HandicapRoundsView(rounds: handicapRounds, handicapIndex: handicapIndex)) {
            MetricCard(title: L("Current Handicap Index"), value: handicapIndexText, systemImage: "number", subtitle: L("View counting rounds"))
        }
        .buttonStyle(.plain)
        .accessibilityHint("View the rounds counting toward your Handicap Index")

        NavigationLink(destination: AllRoundsView(rounds: rounds, profile: profile)) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(PureLineStyle.accent)
                Text("Rounds")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(entries.count)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PureLineStyle.muted)
            }
            .foregroundStyle(PureLineStyle.ink)
            .pureLineCard(padding: 16)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round history")
        .accessibilityValue("\(entries.count) scoring entries")
        .accessibilityHint("View all saved rounds")
    }

}

private struct HCPTrendGraphCard: View {
    var trendPoints: [HCPTrendPoint]
    var currentHandicap: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var visibleTrendPoints: [HCPTrendPoint] {
        Array(trendPoints.suffix(5))
    }

    private var trendDifference: Double? {
        guard visibleTrendPoints.count >= 2,
              let first = visibleTrendPoints.first?.handicapIndex,
              let last = visibleTrendPoints.last?.handicapIndex else { return nil }
        return WHSCalculator.roundToTenth(last - first)
    }

    private var yDomain: ClosedRange<Double> {
        let values = visibleTrendPoints.map(\.handicapIndex)
        guard let minVal = values.min(), let maxVal = values.max() else { return 0...20 }
        let spread = maxVal - minVal
        let step = spread > 6 ? 5.0 : 1.0
        let padding = max(step, spread * 0.3)
        let rawLower = minVal - padding
        let lower = minVal >= 0
            ? max(0, floor(rawLower / step) * step)
            : floor(rawLower / step) * step
        let upper = ceil((maxVal + padding) / step) * step
        return lower...max(upper, lower + step)
    }

    private var yAxisValues: [Double] {
        let step = yDomain.upperBound - yDomain.lowerBound > 12 ? 5.0 : 1.0
        return stride(from: yDomain.lowerBound, through: yDomain.upperBound, by: step).map { $0 }
    }

    private var xDomain: ClosedRange<Int> {
        guard let first = visibleTrendPoints.first?.roundIndex,
              let last = visibleTrendPoints.last?.roundIndex else { return 0...1 }
        return first...max(first + 1, last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            headerLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Handicap trend")
                        .font(.headline)
                        .foregroundStyle(PureLineStyle.ink)
                    if let currentHandicap {
                        Text("Current: \(WHSCalculator.formatHCPScore(currentHandicap))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(PureLineStyle.muted)
                    }
                }

                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }

                if let diff = trendDifference {
                    HStack(spacing: 4) {
                        Image(systemName: diff < 0 ? "arrow.down.right.circle.fill" : (diff > 0 ? "arrow.up.right.circle.fill" : "equal.circle.fill"))
                        Text(trendText(diff: diff))
                            .font(.caption.bold().monospacedDigit())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PureLineStyle.canvas)
                    .foregroundStyle(PureLineStyle.muted)
                    .clipShape(Capsule())
                }
            }

            if visibleTrendPoints.count >= 2 {
                Chart {
                    ForEach(visibleTrendPoints) { point in
                        AreaMark(
                            x: .value(L("Round"), point.roundIndex),
                            y: .value(L("HCP"), point.handicapIndex)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [PureLineStyle.accent.opacity(0.12), PureLineStyle.accent.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.linear)

                        LineMark(
                            x: .value(L("Round"), point.roundIndex),
                            y: .value(L("HCP"), point.handicapIndex)
                        )
                        .foregroundStyle(PureLineStyle.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)

                        PointMark(
                            x: .value(L("Round"), point.roundIndex),
                            y: .value(L("HCP"), point.handicapIndex)
                        )
                        .foregroundStyle(PureLineStyle.accent)
                        .symbolSize(point.id == visibleTrendPoints.last?.id ? 45 : 18)
                    }
                }
                .chartXScale(domain: xDomain, range: .plotDimension(padding: 0))
                .chartYScale(domain: yDomain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(PureLineStyle.line)
                        AxisValueLabel {
                            if let hcp = value.as(Double.self) {
                                Text(WHSCalculator.formatHCPScore(hcp))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(PureLineStyle.muted)
                            }
                        }
                    }
                }
                .frame(height: 140)
                .clipped()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Handicap trend chart")
                .accessibilityValue(trendAccessibilityValue)

                let summaryLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                summaryLayout {
                    if let first = visibleTrendPoints.first {
                        Text("Start: \(WHSCalculator.formatHCPScore(first.handicapIndex))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(PureLineStyle.muted)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    if let lowest = visibleTrendPoints.map(\.handicapIndex).min() {
                        Text("Low: \(WHSCalculator.formatHCPScore(lowest))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(PureLineStyle.muted)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    if let last = visibleTrendPoints.last {
                        Text("Latest: \(WHSCalculator.formatHCPScore(last.handicapIndex))")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(PureLineStyle.ink)
                    }
                }
                .padding(.top, 2)
            } else {
                Text("Add at least four rounds to view your Handicap Index trend.")
                    .font(.caption)
                    .foregroundStyle(PureLineStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .pureLineCard()
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func trendText(diff: Double) -> String {
        if diff < 0 {
            return L("Improved by %@", "\(abs(diff).formatted(.number.precision(.fractionLength(1))))")
        } else if diff > 0 {
            return L("Increased by %@", "\(diff.formatted(.number.precision(.fractionLength(1))))")
        } else {
            return L("No change")
        }
    }

    private var trendAccessibilityValue: String {
        let latest = visibleTrendPoints.last.map { WHSCalculator.formatHCPScore($0.handicapIndex) } ?? "unavailable"
        let lowest = visibleTrendPoints.map(\.handicapIndex).min().map { WHSCalculator.formatHCPScore($0) } ?? "unavailable"
        let change = trendDifference.map { trendText(diff: $0) } ?? L("no trend yet")
        return L("Latest handicap %@, lowest %@, %@, across %@ trend points", "\(latest)", "\(lowest)", "\(change)", "\(visibleTrendPoints.count)")
    }
}

private struct HandicapRoundsView: View {
    var rounds: [GolfRound]
    var handicapIndex: Double?

    private var roundResults: [(round: GolfRound, differential: Double)] {
        let sortedRounds = rounds.sorted { $0.date > $1.date }
        var eligible: [(round: GolfRound, differential: Double)] = []
        for round in sortedRounds {
            guard let entry = WHSCalculator.scoringEntry(
                for: round,
                currentHandicapIndex: handicapIndex
            ) else { continue }
            eligible.append((round: round, differential: entry.scoreDifferential))
        }

        guard eligible.count >= 3 else { return [] }
        let rule = WHSCalculator.bestDifferentialRule(for: min(eligible.count, 20))
        let byDifferential = eligible.sorted { left, right in
            left.differential < right.differential
        }
        let counting: [(round: GolfRound, differential: Double)] = Array(byDifferential.prefix(rule.count))
        return counting.sorted { left, right in
            left.round.date > right.round.date
        }
    }

    private var scoreCount: Int {
        rounds.compactMap { WHSCalculator.scoringEntry(for: $0, currentHandicapIndex: handicapIndex) }.count
    }

    private var countingRuleSummary: String {
        guard scoreCount >= 3 else {
            return L("At least three scores are required to calculate a Handicap Index.")
        }
        let rule = WHSCalculator.bestDifferentialRule(for: min(scoreCount, 20))
        let adjustment = rule.adjustment == 0 ? "" : " with a \(Int(rule.adjustment)) adjustment"
        return "With \(scoreCount) scores, your lowest \(rule.count) \(rule.count == 1 ? "score counts" : "scores count")\(adjustment)."
    }

    var body: some View {
        List {
            if let handicapIndex {
                Section("Handicap Index") {
                    Text(WHSCalculator.formatHCPScore(handicapIndex))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(PureLineStyle.ink)
                        .padding(.vertical, 8)
                }
                .listRowBackground(PureLineStyle.surface)
            }

            if roundResults.isEmpty {
                Section("Counting Rounds") {
                    Text("No rounds count yet.")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(PureLineStyle.surface)
            } else {
                Section("Counting Rounds") {
                    ForEach(roundResults, id: \.round.id) { item in
                        NavigationLink(destination: RoundDetailView(round: item.round, handicapIndex: handicapIndex)) {
                            HandicapRoundRow(round: item.round, differential: item.differential)
                        }
                    }
                }
                .listRowBackground(PureLineStyle.surface)
            }

            Section("How Counting Rounds Work") {
                Text(countingRuleSummary)
                    .font(.subheadline)

                DisclosureGroup("WHS counting rules") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("3 scores: lowest 1, minus 2.0")
                        Text("4 scores: lowest 1, minus 1.0")
                        Text("5 scores: lowest 1")
                        Text("6 scores: lowest 2, minus 1.0")
                        Text("7–8 scores: lowest 2")
                        Text("9–11 scores: lowest 3")
                        Text("12–14 scores: lowest 4")
                        Text("15–16 scores: lowest 5")
                        Text("17–18 scores: lowest 6")
                        Text("19 scores: lowest 7")
                        Text("20 scores: lowest 8")
                    }
                    .font(.caption)
                    .foregroundStyle(PureLineStyle.muted)
                    .padding(.vertical, 8)
                }
            }
            .listRowBackground(PureLineStyle.surface)
        }
        .hcpPureLineList()
        .navigationTitle("Handicap rounds")
    }
}

private struct HandicapRoundRow: View {
    var round: GolfRound
    var differential: Double
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var scoreText: String {
        round.scoreSummaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(round.courseName.isEmpty ? L("No Course") : round.courseName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PureLineStyle.ink)
                    if !round.clubName.isEmpty || !round.teeName.isEmpty {
                        Text([round.clubName, round.teeName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                VStack(alignment: .trailing, spacing: 4) {
                    Text("HCP score")
                        .font(.caption2)
                        .foregroundStyle(PureLineStyle.muted)
                    Text(WHSCalculator.formatHCPScore(differential))
                        .font(.headline.monospacedDigit())
                    Text(round.date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if round.handicapDifferential == nil {
                Text("HCP score: \(WHSCalculator.formatHCPScore(differential)) · \(scoreText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AllRoundsView: View {
    @Environment(\.modelContext) private var modelContext
    var rounds: [GolfRound]
    var profile: PlayerProfile?

    private var sortedRounds: [GolfRound] {
        rounds.sorted { $0.date > $1.date }
    }

    private var recent20Rounds: [GolfRound] {
        Array(sortedRounds.prefix(20))
    }

    private var olderRounds: [GolfRound] {
        Array(sortedRounds.dropFirst(20))
    }

    private var countingRoundIDs: Set<PersistentIdentifier> {
        let entriesWithRound: [(round: GolfRound, entry: ScoringRecordEntry)] = recent20Rounds.compactMap { round in
            guard let entry = WHSCalculator.scoringEntry(for: round) else { return nil }
            return (round, entry)
        }

        guard entriesWithRound.count >= 3 else { return [] }

        let rule = WHSCalculator.bestDifferentialRule(for: entriesWithRound.count)
        let sortedByDiff = entriesWithRound.sorted { $0.entry.scoreDifferential < $1.entry.scoreDifferential }
        let counting = sortedByDiff.prefix(rule.count)
        return Set(counting.map(\.round.persistentModelID))
    }

    private var currentHandicapIndex: Double? {
        let entries = WHSCalculator.scoringEntries(from: rounds, lowHandicapIndex: profile?.lowHandicapIndex)
        return WHSCalculator.handicapIndex(from: entries, lowHandicapIndex: profile?.lowHandicapIndex)
    }

    var body: some View {
        List {
            if !recent20Rounds.isEmpty {
                Section {
                    ForEach(recent20Rounds) { round in
                        NavigationLink(destination: RoundDetailView(round: round, handicapIndex: currentHandicapIndex)) {
                            RoundRow(round: round, isCountingRound: countingRoundIDs.contains(round.persistentModelID))
                        }
                    }
                    .onDelete(perform: deleteRecentRounds)
                } header: {
                    Text("Last 20 rounds (WHS window)")
                }
                .listRowBackground(PureLineStyle.surface)
            }

            if !olderRounds.isEmpty {
                Section {
                    ForEach(olderRounds) { round in
                        NavigationLink(destination: RoundDetailView(round: round, handicapIndex: currentHandicapIndex)) {
                            RoundRow(round: round, isCountingRound: false)
                        }
                    }
                    .onDelete(perform: deleteOlderRounds)
                } header: {
                    Text("Older rounds (past 20-round window)")
                }
                .listRowBackground(PureLineStyle.surface)
            }
        }
        .hcpPureLineList()
        .navigationTitle("All rounds")
    }

    private func deleteRecentRounds(at offsets: IndexSet) {
        for index in offsets {
            let round = recent20Rounds[index]
            modelContext.delete(round)
        }
    }

    private func deleteOlderRounds(at offsets: IndexSet) {
        for index in offsets {
            let round = olderRounds[index]
            modelContext.delete(round)
        }
    }
}

private struct TargetModePicker: View {
    @Binding var inputMode: RoundInputMode
    let hasHoleByHoleData: Bool
    var allowsStableford: Bool = true
    var allowsHoleByHole: Bool = true

    private var selection: Binding<RoundInputMode> {
        Binding(
            get: { inputMode },
            set: { newMode in
                guard newMode != .holeByHole || hasHoleByHoleData else { return }
                inputMode = newMode
            }
        )
    }

    var body: some View {
        Picker("Target", selection: selection) {
            ForEach(RoundInputMode.allCases.filter {
                (allowsStableford || $0 != .stablefordPoints) &&
                (allowsHoleByHole || $0 != .holeByHole)
            }) { mode in
                TargetModeRow(mode: mode, isDisabled: mode == .holeByHole && !hasHoleByHoleData)
            }
        }
        .pickerStyle(.segmented)
        .tint(PureLineStyle.accent)
        .padding(.vertical, 4)
    }
}

private struct TargetModeRow: View {
    let mode: RoundInputMode
    let isDisabled: Bool

    var body: some View {
        Text(mode.title)
            .tag(mode)
            .opacity(isDisabled ? 0.45 : 1)
            .disabled(isDisabled)
    }
}

private struct HoleScoreRowView: View {
    let holeNumber: Int
    let par: Int
    let handicapIndex: Int
    let points: Int?
    @Binding var score: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        rowContent
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private var rowContent: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hole \(holeNumber)")
                    .font(.headline)
                Text("Par \(par) · Index \(handicapIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if let points {
                Text("\(points) pts")
                    .font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PureLineStyle.accent.opacity(0.08))
                    .foregroundStyle(PureLineStyle.accent)
                    .clipShape(Capsule())
            }
            Stepper("\(score)", value: $score, in: 1...15)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Hole \(holeNumber), strokes")
        }
    }
}

@MainActor
private struct TargetCalculatorView: View {
    let courseCatalog: CourseCatalogStore
    var clubs: [GolfClub]
    var courses: [GolfCourse]
    var tees: [TeeSet]
    var rounds: [GolfRound]
    var profile: PlayerProfile?
    var pageTitle = L("Plan your next round")
    var pageSubtitle = L("Choose a course and tee to see how your score could move your Handicap Index.")
    var onHome: () -> Void = {}

    @State private var searchText = ""
    @State private var selectedClubName = ""
    @State private var selectedCourseName = ""
    @State private var selectedTeeName = ""
    @State private var inputMode = RoundInputMode.adjustedGrossScore
    @State private var improvingLimit = 6
    @State private var showMoreWorsening = false
    @State private var showingAddCourse = false
    @State private var showingCustomCourses = false
    @State private var selectedCustomTeeID: PersistentIdentifier?
    @State private var addCourseCountry = ""
    @State private var providerCourse: HCPProviderCourse?
    @State private var projectionResults: [TargetResult] = []
    @State private var projectionHandicap: Double?

    private var activeCountry: String {
        profile?.countryOrDefault ?? GolfAPICoverage.preferredCountry()
    }

    private var selectedTee: CourseTeeInfo? {
        if let providerCourse {
            return providerCourse.tee.ratingSex == (profile?.sexOrDefault ?? .male) ? providerCourse.tee : nil
        }
        guard showingCustomCourses else { return nil }
                guard let tee = tees.first(where: { $0.persistentModelID == selectedCustomTeeID }),
              tee.isAvailable(for: profile?.sexOrDefault ?? .male) else { return nil }
                return CourseTeeInfo(custom: tee)
    }

    private var selectedTeeSummary: String {
        guard let selectedTee else { return "" }
        let rating = selectedTee.courseRating.formatted(.number.precision(.fractionLength(1)))
        return L("Par %@ • CR %@ • Slope %@", "\(selectedTee.par)", "\(rating)", "\(selectedTee.slopeRating)")
    }

    private var hasHoleByHoleData: Bool {
        guard let selectedTee else { return false }
        let parData = selectedTee.holeParsData ?? []
        let hcpData = selectedTee.holeHandicapIndicesData ?? []
        return parData.count == selectedTee.holes && hcpData.count == selectedTee.holes && !parData.isEmpty && !hcpData.isEmpty
    }

    private var entries: [ScoringRecordEntry] {
        WHSCalculator.scoringEntries(from: rounds, lowHandicapIndex: profile?.lowHandicapIndex)
    }

    private var currentHandicap: Double? {
        WHSCalculator.handicapIndex(from: entries, lowHandicapIndex: profile?.lowHandicapIndex)
    }

    private var results: [TargetResult] {
        guard let selectedTee else { return [] }
        return WHSCalculator.targetResults(
            currentEntries: entries,
            tee: selectedTee.snapshot,
            inputMode: inputMode,
            lowHandicapIndex: profile?.lowHandicapIndex
        )
    }

    private func improvingResults(from results: [TargetResult]) -> [TargetResult] {
        let list = results.filter { $0.change < 0 }
        switch inputMode {
        case .adjustedGrossScore, .holeByHole:
            return list.sorted { $0.value > $1.value }
        case .stablefordPoints:
            return list.sorted { $0.value < $1.value }
        }
    }

    private func worseningResults(from results: [TargetResult], currentHandicap: Double?) -> [TargetResult] {
        guard let currentHandicap else { return [] }
        let list = results.filter { $0.projectedHandicapIndex > currentHandicap }
        let sorted: [TargetResult]
        switch inputMode {
        case .adjustedGrossScore, .holeByHole:
            sorted = list.sorted { $0.value < $1.value }
        case .stablefordPoints:
            sorted = list.sorted { $0.value > $1.value }
        }

        var shownIndexes = Set<Double>()
        return sorted.filter { shownIndexes.insert($0.projectedHandicapIndex).inserted }
    }

    var body: some View {
        let activeTee = selectedTee
        let activeHasHoleDetails = activeTee.map {
            let pars = $0.holeParsData ?? []
            let indices = $0.holeHandicapIndicesData ?? []
            return pars.count == $0.holes && indices.count == $0.holes && !pars.isEmpty && !indices.isEmpty
        } ?? false
        let calculatedHandicap = projectionHandicap
        let calculatedResults = projectionResults
        let improvingResults = improvingResults(from: calculatedResults)
        let worseningResults = worseningResults(from: calculatedResults, currentHandicap: calculatedHandicap)
        let projectionKey = "\(providerCourse?.id ?? "custom")|\(activeTee?.hashValue ?? 0)|\(activeCountry)|\(profile?.sexOrDefault.rawValue ?? PlayerSex.male.rawValue)|\(selectedClubName)|\(selectedCourseName)|\(selectedTeeName)|\(inputMode.rawValue)|\(rounds.count)|\(profile?.lowHandicapIndex ?? 0)"

        NavigationStack {
            List {
                Section {
                    HCPPageHeader(title: pageTitle, subtitle: pageSubtitle)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(PureLineStyle.canvas)
                        .listRowSeparator(.hidden)
                }
                .listSectionMargins(.top, 0)
                .listSectionMargins(.horizontal, 0)
                Section {
                    HCPProviderCourseSelectionView(profile: profile, clubs: clubs, courses: courses, tees: tees,
                            country: activeCountry, confirmedCourseID: providerCourse?.id,
                            confirmedCustomTeeID: $selectedCustomTeeID, onSelectCustom: { tee in
                                providerCourse = nil
                                showingCustomCourses = true
                                selectedClubName = tee.clubName
                                selectedCourseName = tee.courseName
                                selectedTeeName = tee.name
                                projectionResults = []
                                projectionHandicap = nil
                                improvingLimit = 6
                                showMoreWorsening = false
                            }) { selection in
                            providerCourse = selection
                            showingCustomCourses = false
                            selectedClubName = selection.tee.clubName
                            selectedCourseName = selection.tee.courseName
                            selectedTeeName = selection.tee.name
                            projectionResults = []
                            projectionHandicap = nil
                            improvingLimit = 6
                            showMoreWorsening = false
                        }
                }
                .listRowBackground(PureLineStyle.surface)

                if !selectedClubName.isEmpty {
                    Section("Course & scoring") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedClubName)
                                    .font(.headline)
                                if let providerCourse {
                                    Text("\(providerCourse.tee.courseName) · \(providerCourse.tee.name) tee · \(providerCourse.tee.ratingSex?.label ?? "")")
                                        .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                                    if activeTee == nil {
                                        Text("Profile rating category changed. Choose a matching provider tee again.")
                                            .font(.caption).foregroundStyle(PureLineStyle.muted)
                                    }
                                }
                                if showingCustomCourses {
                                    Text("Custom · \(selectedCourseName) · \(selectedTeeName) tee")
                                        .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                                }
                            }
                        }

                        if let activeTee {
                            let rating = activeTee.courseRating.formatted(.number.precision(.fractionLength(1)))
                            Text("Par \(activeTee.par) • CR \(rating) • Slope \(activeTee.slopeRating)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if activeTee != nil {
                            TargetModePicker(
                                inputMode: $inputMode,
                                hasHoleByHoleData: activeHasHoleDetails,
                                allowsHoleByHole: false
                            )
                                .onChange(of: inputMode) {
                                    if !activeHasHoleDetails && inputMode == .holeByHole {
                                        inputMode = .adjustedGrossScore
                                    }
                                    improvingLimit = 6
                                }
                                .onChange(of: selectedTeeName) {
                                    if !activeHasHoleDetails && inputMode == .holeByHole {
                                        inputMode = .adjustedGrossScore
                                    }
                                }
                        }
                    }
                    .listRowBackground(PureLineStyle.surface)
                }

                if let activeTee, activeTee.holes == 9 {
                    Section {
                        HCPNineHoleNotice()
                    }
                    .listRowBackground(PureLineStyle.surface)
                }

                if let calculatedHandicap, let activeTee {
                    Section("Your starting point") {
                        LabeledContent("Handicap Index", value: WHSCalculator.formatHCPScore(calculatedHandicap))
                            .font(.headline.monospacedDigit())
                        LabeledContent("Course Handicap", value: "\(WHSCalculator.courseHandicap(handicapIndex: calculatedHandicap, tee: activeTee.snapshot))")
                    }
                    .listRowBackground(PureLineStyle.surface)
                }

                if activeTee != nil {
                    if calculatedResults.isEmpty {
                        Section("Outcomes") {
                            ContentUnavailableView("No outcomes calculated", systemImage: "equal.circle", description: Text("Add at least three rounds or select another tee."))
                        }
                        .listRowBackground(PureLineStyle.surface)
                    } else {
                        if !improvingResults.isEmpty {
                            Section {
                                ForEach(improvingResults.prefix(improvingLimit)) { result in
                                    TargetResultRow(result: result)
                                }
                                if improvingLimit > 6 || improvingResults.count > improvingLimit {
                                    HStack {
                                        if improvingResults.count > improvingLimit {
                                            Button("Show more") {
                                                withAnimation {
                                                    improvingLimit = min(improvingLimit + 6, improvingResults.count)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(PureLineStyle.accent)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        Spacer()
                                        if improvingLimit > 6 {
                                            Button("Show less") {
                                                withAnimation {
                                                    improvingLimit = max(6, improvingLimit - 6)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(PureLineStyle.accent)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                        }
                                    }
                                }
                            } header: {
                                Text("Lower Handicap Index")
                            }
                            .listRowBackground(PureLineStyle.surface)
                        }

                        if !worseningResults.isEmpty {
                            Section {
                                ForEach(showMoreWorsening ? worseningResults : Array(worseningResults.prefix(6))) { result in
                                    TargetResultRow(result: result)
                                }
                                if worseningResults.count > 6 {
                                    Button(showMoreWorsening ? L("Show fewer") : L("Show all %@ worsening outcomes", "\(worseningResults.count)")) {
                                        showMoreWorsening.toggle()
                                    }
                                }
                            } header: {
                                Text("Higher Handicap Index")
                            }
                            .listRowBackground(PureLineStyle.surface)
                        } else {
                            Section {
                                Text("No score would raise your Handicap Index.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } header: {
                                Text("Higher Handicap Index")
                            }
                            .listRowBackground(PureLineStyle.surface)
                        }
                    }
                }
            }
            .hcpPureLineList()
            .contentMargins(.top, 0, for: .scrollContent)
            .toolbar {
                if !selectedClubName.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            selectedClubName = ""
                            providerCourse = nil
                            showingCustomCourses = false
                            selectedCustomTeeID = nil
                            selectedCourseName = ""
                            selectedTeeName = ""
                            projectionResults = []
                            projectionHandicap = nil
                            improvingLimit = 6
                            showMoreWorsening = false
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
            }
            .toolbar(selectedClubName.isEmpty ? .hidden : .visible, for: .navigationBar)
            .sheet(isPresented: $showingAddCourse) {
                AddCourseView(courseCatalog: courseCatalog, profile: profile, clubs: clubs, courses: courses, tees: tees, initialClubName: searchText, initialCountry: addCourseCountry)
            }
            .onAppear {
                if let defaultMode = profile?.defaultInputMode {
                    inputMode = defaultMode
                }
                if rounds.count < 3 && inputMode == .stablefordPoints {
                    inputMode = .adjustedGrossScore
                }
                if !hasHoleByHoleData && inputMode == .holeByHole {
                    inputMode = .adjustedGrossScore
                }
            }
            .task(id: projectionKey) {
                await refreshProjection()
            }
        }
    }

    @MainActor
    private func refreshProjection() async {
        guard let selectedTee else {
            projectionResults = []
            projectionHandicap = nil
            return
        }

        await Task.yield()
        guard !Task.isCancelled else { return }

        let currentEntries = entries
        let handicap = WHSCalculator.handicapIndex(
            from: currentEntries,
            lowHandicapIndex: profile?.lowHandicapIndex
        )
        let results = WHSCalculator.targetResults(
            currentEntries: currentEntries,
            tee: selectedTee.snapshot,
            inputMode: inputMode,
            lowHandicapIndex: profile?.lowHandicapIndex
        )

        guard !Task.isCancelled else { return }
        projectionHandicap = handicap
        projectionResults = results
    }
}

@MainActor
private struct NewRoundView: View {
    @Environment(\.modelContext) private var modelContext

    let courseCatalog: CourseCatalogStore
    var clubs: [GolfClub]
    var courses: [GolfCourse]
    var tees: [TeeSet]
    var rounds: [GolfRound]
    var profile: PlayerProfile?
    var pageTitle = L("Record a round")
    var pageSubtitle = L("Select your course and tee, or enter an official HCP score without a course.")
    var onHome: () -> Void = {}

    @State private var searchText = ""
    @State private var selectedClubName = ""
    @State private var selectedCourseName = ""
    @State private var selectedTeeName = ""
    @State private var inputMode = RoundInputMode.adjustedGrossScore
    @State private var isManualDifferential = false
    @State private var manualDifferentialText = ""
    @State private var roundDate = Date()
    @State private var strokes = 88
    @State private var points = 36
    @State private var pcc = 0.0
    @State private var notes = ""
    @State private var showingSavedConfirmation = false
    @State private var showingAddCourse = false
    @State private var showingCustomCourses = false
    @State private var selectedCustomTeeID: PersistentIdentifier?
    @State private var addCourseCountry = ""
    @State private var providerCourse: HCPProviderCourse?
    @State private var holeScores: [Int] = Array(repeating: 4, count: 18)

    private var activeCountry: String {
        profile?.countryOrDefault ?? GolfAPICoverage.preferredCountry()
    }

    private var selectedTee: CourseTeeInfo? {
        if let providerCourse {
            return providerCourse.tee.ratingSex == (profile?.sexOrDefault ?? .male) ? providerCourse.tee : nil
        }
        guard showingCustomCourses else { return nil }
                guard let tee = tees.first(where: { $0.persistentModelID == selectedCustomTeeID }),
              tee.isAvailable(for: profile?.sexOrDefault ?? .male) else { return nil }
                return CourseTeeInfo(custom: tee)
    }

    private var selectedTeeSummary: String {
        guard let selectedTee else { return "" }
        let rating = selectedTee.courseRating.formatted(.number.precision(.fractionLength(1)))
        return L("Par %@ • CR %@ • Slope %@", "\(selectedTee.par)", "\(rating)", "\(selectedTee.slopeRating)")
    }

    private var hasHoleByHoleData: Bool {
        guard let selectedTee else { return false }
        let parData = selectedTee.holeParsData ?? []
        let hcpData = selectedTee.holeHandicapIndicesData ?? []
        return parData.count == selectedTee.holes && hcpData.count == selectedTee.holes && !parData.isEmpty && !hcpData.isEmpty
    }

    private var currentHandicap: Double? {
        let entries = WHSCalculator.scoringEntries(from: rounds, lowHandicapIndex: profile?.lowHandicapIndex)
        return WHSCalculator.handicapIndex(from: entries, lowHandicapIndex: profile?.lowHandicapIndex)
    }

    var body: some View {
        let activeTee = selectedTee
        let activeHasHoleDetails = activeTee.map {
            let pars = $0.holeParsData ?? []
            let indices = $0.holeHandicapIndicesData ?? []
            return pars.count == $0.holes && indices.count == $0.holes && !pars.isEmpty && !indices.isEmpty
        } ?? false
        let calculatedHandicap = activeTee == nil ? nil : currentHandicap
        let canShowStablefordPoints = rounds.count >= 3

        NavigationStack {
            Form {
                Section {
                    HCPPageHeader(title: pageTitle, subtitle: pageSubtitle)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(PureLineStyle.canvas)
                        .listRowSeparator(.hidden)
                }
                .listSectionMargins(.top, 0)
                .listSectionMargins(.horizontal, 0)
                if !isManualDifferential {
                    Section {
                        HCPProviderCourseSelectionView(profile: profile, clubs: clubs, courses: courses, tees: tees,
                            country: activeCountry, confirmedCourseID: providerCourse?.id, title: L("What did you play?"),
                            onAddCustom: { query, country in
                                searchText = query
                                addCourseCountry = country
                                showingAddCourse = true
                            },
                            confirmedCustomTeeID: $selectedCustomTeeID, onSelectCustom: { tee in
                                providerCourse = nil
                                showingCustomCourses = true
                                selectedClubName = tee.clubName
                                selectedCourseName = tee.courseName
                                selectedTeeName = tee.name
                                if !hasHoleByHoleData && inputMode == .holeByHole { inputMode = .adjustedGrossScore }
                                resetHoleScores()
                            }) { selection in
                            providerCourse = selection
                            showingCustomCourses = false
                            selectedClubName = selection.tee.clubName
                            selectedCourseName = selection.tee.courseName
                            selectedTeeName = selection.tee.name
                            if !hasHoleByHoleData && inputMode == .holeByHole { inputMode = .adjustedGrossScore }
                            resetHoleScores()
                        }
                    }
                    .listRowBackground(PureLineStyle.surface)
                }

                if !isManualDifferential && selectedClubName.isEmpty {
                    Section {
                        Button {
                            isManualDifferential = true
                            searchText = ""
                        } label: {
                            HStack {
                                Label("No course", systemImage: "minus.circle")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                            Text("Use this when the course is not available and you already know the official HCP score.")
                                .font(.caption)
                                .foregroundStyle(PureLineStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(PureLineStyle.surface)

                }

                if isManualDifferential || !selectedCourseName.isEmpty {
                    Section("Round Details") {
                        DatePicker("Date", selection: $roundDate, displayedComponents: .date)
                    }
                    .listRowBackground(PureLineStyle.surface)
                }

                if isManualDifferential {
                    Section("No Course") {
                        TextField("HCP score", text: $manualDifferentialText)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .padding(.vertical, 4)
                        Text("Enter the official HCP score for this round.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !manualDifferentialText.isEmpty && parsedManualDifferential == nil {
                            Text("Enter a number between −20 and 54.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowBackground(PureLineStyle.surface)
                }

                if !isManualDifferential && !selectedClubName.isEmpty {
                    Section("Course & scoring") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedClubName)
                                    .font(.headline)
                                if let providerCourse {
                                    Text("\(providerCourse.tee.courseName) · \(providerCourse.tee.name) tee · \(providerCourse.tee.ratingSex?.label ?? "")")
                                        .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                                    if activeTee == nil {
                                        Text("Profile rating category changed. Choose a matching provider tee again.")
                                            .font(.caption).foregroundStyle(PureLineStyle.muted)
                                    }
                                }
                                if showingCustomCourses {
                                    Text("Custom · \(selectedCourseName) · \(selectedTeeName) tee")
                                        .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                                }
                            }
                        }

                        if let activeTee {
                            let rating = activeTee.courseRating.formatted(.number.precision(.fractionLength(1)))
                            Text("Par \(activeTee.par) • CR \(rating) • Slope \(activeTee.slopeRating)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        TargetModePicker(
                            inputMode: $inputMode,
                            hasHoleByHoleData: activeHasHoleDetails,
                            allowsStableford: rounds.count >= 3
                        )
                            .onChange(of: inputMode) {
                                if !activeHasHoleDetails && inputMode == .holeByHole {
                                    inputMode = .adjustedGrossScore
                                }
                            }
                            .onChange(of: selectedTeeName) {
                                if !activeHasHoleDetails && inputMode == .holeByHole {
                                    inputMode = .adjustedGrossScore
                                }
                            }

                        if !activeHasHoleDetails {
                            Text("Hole-by-hole scoring requires hole details for this tee.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if rounds.count < 3 {
                            Text("Stableford scoring becomes available after three rounds have been entered.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(PureLineStyle.surface)
                }

                if !isManualDifferential, let activeTee {
                    if activeTee.holes == 9, calculatedHandicap == nil {
                        Section {
                            HCPNineHoleNotice(currentHandicap: nil)
                        }
                        .listRowBackground(PureLineStyle.surface)
                    }

                    if inputMode == .holeByHole && activeHasHoleDetails {
                        let holeCount = activeTee.holes
                        let pars = activeTee.holePars
                        let hcpIndices = activeTee.holeHandicapIndices
                        let safeHoleCount = min(holeCount, min(holeScores.count, min(pars.count, hcpIndices.count)))
                        let ch = WHSCalculator.courseHandicap(handicapIndex: calculatedHandicap ?? 0, tee: activeTee.snapshot)
                        let holeCalc = WHSCalculator.calculateHoleByHole(
                            holeScores: Array(holeScores.prefix(safeHoleCount)),
                            holePars: pars,
                            holeHandicapIndices: hcpIndices,
                            courseHandicap: ch
                        )

                        Section("Round Summary") {
                            HStack {
                                Text("Total Gross")
                                Spacer()
                                Text("\(holeCalc.totalGrossScore)")
                                    .monospacedDigit()
                                    .bold()
                            }
                            HStack {
                                Text("WHS Adjusted Score")
                                Spacer()
                                Text("\(holeCalc.netDoubleBogeyAdjustedScore)")
                                    .monospacedDigit()
                                    .bold()
                            }
                            if canShowStablefordPoints {
                                HStack {
                                    Text("Stableford Points")
                                    Spacer()
                                    Text("\(holeCalc.totalStablefordPoints) pts")
                                        .monospacedDigit()
                                        .bold()
                                        .foregroundStyle(PureLineStyle.accent)
                                }
                            }
                        }
                        .listRowBackground(PureLineStyle.surface)

                        Section("Hole by Hole Scores") {
                            ForEach(0..<safeHoleCount, id: \.self) { i in
                                let scoreBinding = Binding<Int>(
                                    get: { i < holeScores.count ? holeScores[i] : pars[i] },
                                    set: { newVal in
                                        if i < holeScores.count {
                                            holeScores[i] = newVal
                                        }
                                    }
                                )
                                HoleScoreRowView(
                                    holeNumber: i + 1,
                                    par: pars[i],
                                    handicapIndex: hcpIndices[i],
                                    points: canShowStablefordPoints && i < holeCalc.holePoints.count
                                        ? holeCalc.holePoints[i] : nil,
                                    score: scoreBinding
                                )
                            }
                        }
                        .listRowBackground(PureLineStyle.surface)
                    } else {
                        Section("Score") {
                            if inputMode == .adjustedGrossScore {
                                VStack(alignment: .leading, spacing: 12) {
                                    InfoLabel(
                                        title: L("Adjusted Gross Score"),
                                        explanation: L("Adjusted Gross Score is the total strokes you took after WHS maximums are applied on any hole. It is used to calculate your handicap differential and removes the effect of a few unusually bad holes.")
                                    )
                                    HStack {
                                        Text("\(strokes)")
                                            .font(.title2.weight(.semibold).monospacedDigit())
                                        Spacer()
                                        Stepper("", value: $strokes, in: 45...160)
                                            .labelsHidden()
                                            .accessibilityLabel("Adjusted Gross Score")
                                    }
                                }
                            } else if inputMode == .stablefordPoints && canShowStablefordPoints {
                                Stepper("Stableford points: \(points)", value: $points, in: 0...54)
                            }
                        }
                        .listRowBackground(PureLineStyle.surface)
                    }

                    Section("Conditions & Notes") {
                        HStack {
                            InfoLabel(
                                title: L("PCC"),
                                explanation: L("Playing Conditions Calculation. It adjusts your handicap differential for unusually easy or difficult course conditions, such as wind, rain, green speed, or setup. A positive value means conditions were harder than normal; a negative value means easier than normal.")
                            )
                            Spacer()
                            Text(pcc.formatted(.number.precision(.fractionLength(1))))
                                .font(.body.bold())
                            Stepper("", value: $pcc, in: -1...3, step: 1)
                                .labelsHidden()
                                .accessibilityLabel("PCC adjustment")
                        }
                        TextField("Notes", text: $notes)
                    }
                    .listRowBackground(PureLineStyle.surface)

                }

                if isManualDifferential {
                    Section("Notes") {
                        TextField("Notes", text: $notes)
                    }
                    .listRowBackground(PureLineStyle.surface)

                }
            }
            .hcpPureLineList()
            .contentMargins(.top, 0, for: .scrollContent)
            .toolbar {
                if isManualDifferential || !selectedClubName.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isManualDifferential = false
                            providerCourse = nil
                            showingCustomCourses = false
                            selectedCustomTeeID = nil
                            selectedClubName = ""
                            selectedCourseName = ""
                            selectedTeeName = ""
                            manualDifferentialText = ""
                            searchText = ""
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
                if isManualDifferential || !selectedClubName.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { saveRound() }
                            .disabled(!canSaveRound)
                    }
                }
            }
            .toolbar(isManualDifferential || !selectedClubName.isEmpty ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingAddCourse) {
                AddCourseView(courseCatalog: courseCatalog, profile: profile, clubs: clubs, courses: courses, tees: tees, initialClubName: searchText, initialCountry: addCourseCountry)
            }
            .onAppear {
                if let defaultMode = profile?.defaultInputMode {
                    inputMode = defaultMode
                }
                if !hasHoleByHoleData && inputMode == .holeByHole {
                    inputMode = .adjustedGrossScore
                }
                resetHoleScores()
            }
            .onChange(of: rounds.count) {
                if rounds.count < 3 && inputMode == .stablefordPoints {
                    inputMode = .adjustedGrossScore
                }
            }
            .onChange(of: rounds.count) { oldCount, newCount in
                if newCount > oldCount { showingSavedConfirmation = true }
            }
            .alert("Round saved", isPresented: $showingSavedConfirmation) {
                Button("Done", role: .cancel) { }
            } message: {
                Text("Your round is now in your history.")
            }
            .onChange(of: isManualDifferential) {
                if isManualDifferential {
                    providerCourse = nil
                    selectedCustomTeeID = nil
                    showingCustomCourses = false
                    selectedClubName = ""
                    selectedCourseName = ""
                    selectedTeeName = ""
                }
            }
        }
    }

    private func resetHoleScores() {
        let count = selectedTee?.holes ?? 18
        let pars = selectedTee?.holePars ?? TeeSet.defaultPars(for: count, totalPar: selectedTee?.par ?? 72)
        holeScores = pars
    }

    private func saveRound() {
        guard canSaveRound else { return }
        if isManualDifferential {
            guard let handicapDifferential = parsedManualDifferential else { return }
            modelContext.insert(
                GolfRound(
                    date: roundDate,
                    clubName: "",
                    courseName: "",
                    teeName: "",
                    holes: 18,
                    inputMode: .adjustedGrossScore,
                    handicapDifferential: handicapDifferential,
                    par: 72,
                    courseRating: 0,
                    slopeRating: 113,
                    pcc: 0,
                    notes: notes
                )
            )
            notes = ""
            manualDifferentialText = ""
            roundDate = Date()
            isManualDifferential = false
            return
        }

        guard let selectedTee else { return }
        if !hasHoleByHoleData && inputMode == .holeByHole {
            inputMode = .adjustedGrossScore
            return
        }
        let courseHandicap = WHSCalculator.courseHandicap(handicapIndex: currentHandicap ?? 0, tee: selectedTee.snapshot)

        let finalAdjustedScore: Int
        let finalPoints: Int?
        let finalDifferential: Double?
        let recordedHoleScores: [Int]?
        let recordedHolePars: [Int]?
        let recordedHoleIndices: [Int]?

        switch inputMode {
        case .adjustedGrossScore:
            finalAdjustedScore = strokes
            finalPoints = nil
            finalDifferential = selectedTee.holes == 9
                ? WHSCalculator.nineHoleScoreDifferential(adjustedGrossScore: strokes,
                    courseRating: selectedTee.courseRating, slopeRating: selectedTee.slopeRating,
                    pcc: pcc, handicapIndex: currentHandicap ?? .nan)
                : nil
            recordedHoleScores = nil
            recordedHolePars = nil
            recordedHoleIndices = nil

        case .stablefordPoints:
            finalAdjustedScore = WHSCalculator.stablefordAdjustedGrossScore(
                points: points,
                par: selectedTee.par,
                courseHandicap: courseHandicap,
                holes: selectedTee.holes
            )
            finalPoints = points
            finalDifferential = selectedTee.holes == 9
                ? WHSCalculator.nineHoleScoreDifferential(adjustedGrossScore: finalAdjustedScore,
                    courseRating: selectedTee.courseRating, slopeRating: selectedTee.slopeRating,
                    pcc: pcc, handicapIndex: currentHandicap ?? .nan)
                : nil
            recordedHoleScores = nil
            recordedHolePars = nil
            recordedHoleIndices = nil

        case .holeByHole:
            let pars = selectedTee.holePars
            let indices = selectedTee.holeHandicapIndices
            let holeCount = selectedTee.holes
            let currentScores = Array(holeScores.prefix(holeCount))
            let calc = WHSCalculator.calculateHoleByHole(
                holeScores: currentScores,
                holePars: pars,
                holeHandicapIndices: indices,
                courseHandicap: courseHandicap
            )
            finalAdjustedScore = calc.netDoubleBogeyAdjustedScore
            finalPoints = calc.totalStablefordPoints
            finalDifferential = selectedTee.holes == 9
                ? WHSCalculator.nineHoleScoreDifferential(adjustedGrossScore: finalAdjustedScore,
                    courseRating: selectedTee.courseRating, slopeRating: selectedTee.slopeRating,
                    pcc: pcc, handicapIndex: currentHandicap ?? .nan)
                : nil
            recordedHoleScores = currentScores
            recordedHolePars = pars
            recordedHoleIndices = indices
        }

        modelContext.insert(
            GolfRound(
                date: roundDate,
                clubName: selectedTee.clubName,
                courseName: selectedTee.courseName,
                teeName: selectedTee.name,
                holes: selectedTee.holes,
                inputMode: inputMode,
                adjustedGrossScore: finalAdjustedScore,
                stablefordPoints: finalPoints,
                handicapDifferential: finalDifferential,
                par: selectedTee.par,
                courseRating: selectedTee.courseRating,
                slopeRating: selectedTee.slopeRating,
                pcc: pcc,
                notes: notes,
                holeScoresData: recordedHoleScores,
                holeParsData: recordedHolePars,
                holeHandicapIndicesData: recordedHoleIndices
            )
        )
        notes = ""
        roundDate = Date()
        providerCourse = nil
        showingCustomCourses = false
        selectedCustomTeeID = nil
        selectedClubName = ""
        selectedCourseName = ""
        selectedTeeName = ""
    }

    private var canSaveRound: Bool {
        if isManualDifferential {
            return parsedManualDifferential != nil
        }

        guard !selectedClubName.isEmpty,
              !selectedCourseName.isEmpty,
              !selectedTeeName.isEmpty,
              let selectedTee else { return false }

        if inputMode == .holeByHole {
            return hasHoleByHoleData && holeScores.count == selectedTee.holes && holeScores.allSatisfy { $0 > 0 }
        }

        switch inputMode {
        case .adjustedGrossScore:
            return (45...160).contains(strokes)
        case .stablefordPoints:
            return (0...54).contains(points)
        case .holeByHole:
            return true
        }
    }

    private var parsedManualDifferential: Double? {
        let normalized = manualDifferentialText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= -20, value <= 54 else { return nil }
        return WHSCalculator.roundToTenth(value)
    }
}

private struct DrillRowView: View {
    var title: String
    var subtitle: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

private struct CustomCourseSearchResult: Identifiable {
    let club: GolfClub
    let courseName: String

    var id: String {
        "\(club.country.lowercased())|\(club.city.lowercased())|\(club.name.lowercased())|\(courseName.lowercased())"
    }
}

private struct CustomCoursesView: View {
    @Environment(\.modelContext) private var modelContext
    let courseCatalog: CourseCatalogStore
    var profile: PlayerProfile?
    var clubs: [GolfClub]
    var courses: [GolfCourse]
    var tees: [TeeSet]

    @State private var showingAddCourse = false
    @State private var searchText = ""

    private var customTees: [TeeSet] {
        tees.filter { $0.isCustom ?? false }
    }

    private var customClubs: [GolfClub] {
        clubs.filter { $0.isCustom ?? false }
    }

    private var uniqueCustomClubs: [GolfClub] {
        let groups = Dictionary(grouping: customClubs) { club in
            [club.country, club.city, club.name]
                .map(HCPCustomCourseSearch.normalizedCountry)
                .joined(separator: "|")
        }
        return groups.values.compactMap(\.first)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var searchQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filteredClubs: [GolfClub] {
        guard !searchQuery.isEmpty else { return uniqueCustomClubs }
        return uniqueCustomClubs.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
                || $0.city.localizedCaseInsensitiveContains(searchQuery)
                || $0.country.localizedCaseInsensitiveContains(searchQuery)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filteredCourses: [CustomCourseSearchResult] {
        return uniqueCustomClubs.flatMap { club in
            courseNames(for: club.name).compactMap { courseName in
                guard searchQuery.isEmpty
                        || courseName.localizedCaseInsensitiveContains(searchQuery)
                        || club.name.localizedCaseInsensitiveContains(searchQuery)
                        || club.city.localizedCaseInsensitiveContains(searchQuery)
                        || club.country.localizedCaseInsensitiveContains(searchQuery) else { return nil }
                return CustomCourseSearchResult(club: club, courseName: courseName)
            }
        }.sorted {
            if $0.club.name == $1.club.name {
                return $0.courseName.localizedStandardCompare($1.courseName) == .orderedAscending
            }
            return $0.club.name.localizedStandardCompare($1.club.name) == .orderedAscending
        }
    }

    private func courseNames(for club: String) -> [String] {
        Array(Set(courses.filter { ($0.isCustom ?? false) && $0.clubName == club }.map(\.name)
            + customTees.filter { $0.clubName == club }.map(\.courseName))).sorted()
    }

    private func teesIn(club: String, course: String) -> [TeeSet] {
        customTees.filter { $0.clubName == club && $0.courseName == course }.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PureLineStyle.muted)
                    TextField("Search courses or clubs", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(PureLineStyle.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
            }
            .listRowBackground(PureLineStyle.surface)

            if filteredCourses.isEmpty {
                Section {
                    ContentUnavailableView(
                        searchQuery.isEmpty ? L("No Custom Courses") : L("No Matches"),
                        systemImage: searchQuery.isEmpty ? "flag.badge.ellipsis" : "magnifyingglass",
                        description: Text(searchQuery.isEmpty
                            ? L("Add a custom course to see it listed here.")
                            : L("No courses match \"%@\".", "\(searchQuery)"))
                    )
                }
                .listRowBackground(PureLineStyle.surface)
            }

            if !filteredCourses.isEmpty {
                Section(searchQuery.isEmpty ? L("All Courses") : L("Matching Courses")) {
                    ForEach(filteredCourses) { result in
                        NavigationLink {
                            CustomCourseSummaryView(courseName: result.courseName, club: result.club,
                                tees: customTees.filter { $0.clubName == result.club.name && $0.courseName == result.courseName })
                        } label: {
                            DrillRowView(title: result.courseName, subtitle: result.club.name)
                        }
                    }
                    .onDelete(perform: deleteCourses)
                }
                .listRowBackground(PureLineStyle.surface)
            }
        }
        .hcpPureLineList()
        .navigationTitle("Custom Courses")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddCourse = true
                } label: {
                    Label("Add Course", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCourse) {
            AddCourseView(courseCatalog: courseCatalog, profile: profile, clubs: clubs, courses: courses, tees: tees)
        }
    }

    private func deleteCourses(at offsets: IndexSet) {
        let selectedCourses = offsets.compactMap { index in
            filteredCourses.indices.contains(index) ? filteredCourses[index] : nil
        }

        for result in selectedCourses {
            let clubName = result.club.name
            let courseName = result.courseName

            for tee in customTees where tee.clubName == clubName && tee.courseName == courseName {
                modelContext.delete(tee)
            }
            for course in courses where (course.isCustom ?? false)
                    && course.clubName == clubName && course.name == courseName {
                modelContext.delete(course)
            }

            let clubStillHasCourses = courses.contains {
                ($0.isCustom ?? false) && $0.clubName == clubName && $0.name != courseName
            } || customTees.contains {
                $0.clubName == clubName && $0.courseName != courseName
            }
            if !clubStillHasCourses {
                for club in customClubs where club.name == clubName {
                    modelContext.delete(club)
                }
            }
        }
    }
}

private struct CustomCourseSummaryView: View {
    let courseName: String
    let club: GolfClub
    let tees: [TeeSet]

    private var region: String {
        GolfAPICoverage.regions.first { region in
            region.countries.contains {
                HCPCustomCourseSearch.normalizedCountry($0) == HCPCustomCourseSearch.normalizedCountry(club.country)
            }
        }?.name ?? L("Other")
    }

    var body: some View {
        List {
            Section("Course") {
                LabeledContent("Course", value: courseName)
                LabeledContent("Club", value: club.name)
                LabeledContent("Region", value: region)
                LabeledContent("Country", value: club.country)
                if !club.city.isEmpty {
                    LabeledContent("City", value: club.city)
                }
            }
            .listRowBackground(PureLineStyle.surface)

            Section("Tees") {
                if tees.isEmpty {
                    Text("No tees have been added for this course.")
                        .font(.subheadline)
                        .foregroundStyle(PureLineStyle.muted)
                } else {
                    ForEach(tees) { tee in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tee.name)
                                .font(.headline)
                                .foregroundStyle(PureLineStyle.ink)
                            Text("\(tee.ratingSex?.label ?? L("Universal")) · Par \(tee.par) · CR \(tee.courseRating.formatted(.number.precision(.fractionLength(1)))) · Slope \(tee.slopeRating)")
                                .font(.caption)
                                .foregroundStyle(PureLineStyle.muted)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .listRowBackground(PureLineStyle.surface)
        }
        .hcpPureLineList()
        .navigationTitle(courseName)
    }
}

@MainActor
private struct AddCourseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let courseCatalog: CourseCatalogStore
    var profile: PlayerProfile?
    var clubs: [GolfClub]
    var courses: [GolfCourse]
    var tees: [TeeSet] = []

    var initialClubName: String = ""
    var initialCountry: String = ""
    var initialCourseName: String = ""
    var sourceTee: TeeSet? = nil

    @State private var addHoleDetails = false
    @State private var clubName = ""
    @State private var country = ""
    @State private var selectedRegion = "Europe"
    @State private var courseName = ""
    @State private var teeName = ""
    @State private var holes = 18
    @State private var par = 72
    @State private var courseRating = 72.0
    @State private var slopeRating = 113
    @State private var selectedRatingSex = PlayerSex.male
    @State private var holePars: [Int] = Array(repeating: 0, count: 18)
    @State private var holeHandicapIndices: [Int] = Array(1...18)
    @State private var showHoleHcpWarning = false
    @State private var showDuplicateWarning = false
    @State private var isApplyingPrefill = false

    private var availableRegions: [GolfAPICoverageRegion] {
        GolfAPICoverage.regions
    }

    private var availableCountries: [String] {
        availableRegions.first { $0.name == selectedRegion }?.countries ?? []
    }

    private var matchingClubs: [CourseClubInfo] {
        guard !clubName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let query = clubName.trimmingCharacters(in: .whitespacesAndNewlines)
        let available = courseCatalog.clubs(in: country) + clubs
            .filter { $0.country == country }
            .map(CourseClubInfo.init(custom:))
        return available.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }.prefix(4).map { $0 }
    }

    private var matchingCourses: [CourseInfo] {
        guard !courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let query = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clubFilter = clubName.trimmingCharacters(in: .whitespacesAndNewlines)
        let customClubNames = Set(clubs.filter { $0.country == country }.map(\.name))
        let available = courseCatalog.courses(in: country) + courses
            .filter { customClubNames.contains($0.clubName) }
            .map(CourseInfo.init(custom:))
        return available.filter {
            let matchesClub = clubFilter.isEmpty || $0.clubName.localizedCaseInsensitiveContains(clubFilter)
            return matchesClub && $0.name.localizedCaseInsensitiveContains(query)
        }.prefix(4).map { $0 }
    }

    private var totalHolePar: Int {
        holePars.reduce(0, +)
    }

    @ViewBuilder
    private func suggestionList(for items: [CourseClubInfo], onSelect: @escaping (CourseClubInfo) -> Void) -> some View {
        suggestionCard(titles: items.map(\.name)) { index in
            guard items.indices.contains(index) else { return }
            onSelect(items[index])
        }
    }

    @ViewBuilder
    private func suggestionList(for items: [CourseInfo], onSelect: @escaping (CourseInfo) -> Void) -> some View {
        suggestionCard(titles: items.map(\.name)) { index in
            guard items.indices.contains(index) else { return }
            onSelect(items[index])
        }
    }

    @ViewBuilder
    private func suggestionCard(titles: [String], onSelect: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    onSelect(index)
                } label: {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                if index < titles.count - 1 {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(PureLineStyle.line, lineWidth: 1)
        }
        .shadow(color: PureLineStyle.ink.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.trailing, 8)
    }

    private func resetHoleDetails() {
        holePars = Array(repeating: 4, count: holes)
        holeHandicapIndices = Array(1...max(holes, 1))
        if addHoleDetails {
            par = totalHolePar
        } else {
            par = 72
        }
    }

    private func updateHolePar(at index: Int, to value: Int) {
        guard holePars.indices.contains(index) else { return }
        holePars[index] = min(max(value, 3), 8)
        par = totalHolePar
    }

    private func applySourceTeePrefillIfNeeded() {
        guard let sourceTee else { return }
        isApplyingPrefill = true
        holes = sourceTee.holes
        par = sourceTee.par
        courseRating = sourceTee.courseRating
        slopeRating = sourceTee.slopeRating
        selectedRatingSex = sourceTee.ratingSex ?? profile?.sexOrDefault ?? .male

        guard let sourcePars = sourceTee.holeParsData,
              let sourceIndices = sourceTee.holeHandicapIndicesData,
              sourcePars.count == sourceTee.holes,
              sourceIndices.count == sourceTee.holes else {
            isApplyingPrefill = false
            return
        }

        addHoleDetails = true
        holePars = sourcePars
        holeHandicapIndices = sourceIndices
        isApplyingPrefill = false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HCPPureLineIntro(title: L("Add a custom course"), subtitle: L("Use the published ratings for your course, tee and rating category."))
                }

                Section("Location · Required") {
                    HStack(spacing: 14) {
                        Menu {
                            ForEach(availableRegions) { region in
                                Button(region.name) {
                                    selectedRegion = region.name
                                    if !region.countries.contains(where: { $0.localizedCaseInsensitiveCompare(country) == .orderedSame }) {
                                        country = region.countries.first ?? ""
                                    }
                                }
                            }
                        } label: {
                            Label(selectedRegion.isEmpty ? L("Region") : selectedRegion, systemImage: "globe")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("custom-course-region-picker")

                        Rectangle()
                            .fill(PureLineStyle.line)
                            .frame(width: 1, height: 24)
                            .accessibilityHidden(true)

                        Menu {
                            ForEach(availableCountries, id: \.self) { countryOption in
                                Button(countryOption) { country = countryOption }
                            }
                        } label: {
                            Label(country.isEmpty ? L("Country") : country, systemImage: "mappin.and.ellipse")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .disabled(selectedRegion.isEmpty)
                        .accessibilityIdentifier("custom-course-country-picker")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))

                    TextField("Club name", text: $clubName)
                        .overlay(alignment: .topLeading) {
                            if !matchingClubs.isEmpty {
                                suggestionList(for: matchingClubs) { club in
                                    clubName = club.name
                                }
                                .offset(y: 44)
                            }
                        }
                        .zIndex(1)
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Course & Tee · Required") {
                    TextField("Course name", text: $courseName)
                        .overlay(alignment: .topLeading) {
                            if !matchingCourses.isEmpty {
                                suggestionList(for: matchingCourses) { course in
                                    courseName = course.name
                                    if clubName.isEmpty {
                                        clubName = course.clubName
                                    }
                                }
                                .offset(y: 44)
                            }
                        }
                        .zIndex(1)
                    TextField("Tee", text: $teeName)
                    Picker("Holes", selection: $holes) {
                        Text("9").tag(9)
                        Text("18").tag(18)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(PureLineStyle.surface)

                Section("WHS Ratings · Required") {
                    Picker("Tee Rating Category", selection: $selectedRatingSex) {
                        ForEach(PlayerSex.allCases) { sex in
                            Text(sex == .male ? L("Men") : L("Women")).tag(sex)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        InfoLabel(
                            title: L("Par"),
                            explanation: L("Par is the expected number of strokes for a scratch golfer on this course or tee. Enter the total par across the selected 9 or 18 holes.")
                        )
                        Spacer()
                        TextField("Par", value: $par, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 64)
                    }
                    .disabled(addHoleDetails)
                    .opacity(addHoleDetails ? 0.45 : 1)
                    HStack {
                        InfoLabel(
                            title: L("Course Rating"),
                            explanation: L("Course Rating estimates the score a scratch golfer is expected to make on this tee under normal playing conditions. Lower values represent easier courses for a scratch golfer; higher values represent harder ones.")
                        )
                        Spacer()
                        TextField("Course Rating", value: $courseRating, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 72)
                    }
                    HStack {
                        InfoLabel(
                            title: L("Slope Rating"),
                            explanation: L("Slope Rating describes how much more difficult this tee is for a bogey golfer than for a scratch golfer. It is used with Course Rating to adjust the course handicap for different playing abilities.")
                        )
                        Spacer()
                        TextField("Slope Rating", value: $slopeRating, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 64)
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Hole Details · Optional") {
                    Toggle("Add hole details", isOn: $addHoleDetails)
                }
                .listRowBackground(PureLineStyle.surface)

                if addHoleDetails {
                    Section("Hole Details") {
                        Text("Each hole must have a unique HCP from 1 to \(holes).")
                            .font(.caption)
                            .foregroundStyle(PureLineStyle.muted)
                        ForEach(0..<holes, id: \ .self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Hole \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ViewThatFits(in: .horizontal) {
                                    HStack {
                                        holeParStepper(at: index)
                                        Spacer()
                                        holeHandicapStepper(at: index)
                                    }
                                    VStack(alignment: .leading, spacing: 8) {
                                        holeParStepper(at: index)
                                        holeHandicapStepper(at: index)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(PureLineStyle.surface)
                }
            }
            .hcpPureLineList()
            .navigationTitle("Add Custom Course")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCourse() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if !initialClubName.isEmpty {
                    clubName = initialClubName
                }
                if !initialCourseName.isEmpty {
                    courseName = initialCourseName
                }
                let preferredCountry = initialCountry.isEmpty ? (profile?.countryOrDefault ?? "Sweden") : initialCountry
                let region = availableRegions.first { region in
                    region.countries.contains { $0.localizedCaseInsensitiveCompare(preferredCountry) == .orderedSame }
                } ?? availableRegions.first { $0.name == "Europe" }
                selectedRegion = region?.name ?? "Europe"
                country = region?.countries.first(where: { $0.localizedCaseInsensitiveCompare(preferredCountry) == .orderedSame })
                    ?? region?.countries.first
                    ?? "Sweden"
                selectedRatingSex = profile?.sexOrDefault ?? .male
                if sourceTee == nil {
                    resetHoleDetails()
                } else {
                    applySourceTeePrefillIfNeeded()
                }
            }
            .onChange(of: addHoleDetails) {
                if !isApplyingPrefill {
                    resetHoleDetails()
                }
            }
            .onChange(of: holes) {
                if !isApplyingPrefill {
                    resetHoleDetails()
                }
            }
            .onChange(of: holePars) {
                if addHoleDetails {
                    par = totalHolePar
                }
            }
            .alert("Invalid hole handicaps", isPresented: $showHoleHcpWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Each hole must have a unique HCP from 1 to \(holes), and no value may be duplicated or outside that range.")
            }
            .alert("Course already exists", isPresented: $showDuplicateWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A \(selectedRatingSex.label.lowercased()) rating for this club, course, and tee already exists in this country.")
            }
        }
    }

    private func isDuplicate() -> Bool {
        let cleanClub = clubName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCourse = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTee = teeName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanClub.isEmpty, !cleanCourse.isEmpty, !cleanTee.isEmpty else { return false }

        let duplicatesCustomTee = tees.contains { tee in
            tee.clubName.localizedCaseInsensitiveCompare(cleanClub) == .orderedSame &&
            tee.courseName.localizedCaseInsensitiveCompare(cleanCourse) == .orderedSame &&
            tee.name.localizedCaseInsensitiveCompare(cleanTee) == .orderedSame &&
            (tee.ratingSex == nil || tee.ratingSex == selectedRatingSex) &&
            (clubs.first { $0.name.localizedCaseInsensitiveCompare(tee.clubName) == .orderedSame }?.country.localizedCaseInsensitiveCompare(country) == .orderedSame)
        }
        return duplicatesCustomTee || courseCatalog.containsRating(
            country: country,
            clubName: cleanClub,
            courseName: cleanCourse,
            teeName: cleanTee,
            sex: selectedRatingSex
        )
    }

    private func holeHandicapIndicesAreValid() -> Bool {
        let values = holeHandicapIndices.prefix(holes)
        let expected = Set(1...max(holes, 1))
        let actual = Set(values)
        return values.count == holes && actual == expected
    }

    @ViewBuilder
    private func holeParStepper(at index: Int) -> some View {
        if holePars.indices.contains(index) {
            Stepper(
                L("Par %@", "\(holePars[index])"),
                value: Binding(
                    get: { holePars[index] },
                    set: { updateHolePar(at: index, to: $0) }
                ),
                in: 3...8
            )
        }
    }

    @ViewBuilder
    private func holeHandicapStepper(at index: Int) -> some View {
        if holeHandicapIndices.indices.contains(index) {
            Stepper(
                L("HCP %@", "\(holeHandicapIndices[index])"),
                value: Binding(
                    get: { holeHandicapIndices[index] },
                    set: { holeHandicapIndices[index] = min(max($0, 1), 18) }
                ),
                in: 1...18
            )
        }
    }

    private var canSave: Bool {
        !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !clubName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !teeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (27...80).contains(par) &&
        (25...90).contains(courseRating) &&
        (55...160).contains(slopeRating)
    }

    private func saveCourse() {
        if addHoleDetails && !holeHandicapIndicesAreValid() {
            showHoleHcpWarning = true
            return
        }

        if isDuplicate() {
            showDuplicateWarning = true
            return
        }

        let cleanClubName = clubName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCourseName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTeeName = teeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedHolePars: [Int]? = addHoleDetails ? Array(holePars.prefix(holes)) : nil
        let savedHoleHandicapIndices: [Int]? = addHoleDetails ? Array(holeHandicapIndices.prefix(holes)) : nil

        modelContext.insert(GolfClub(name: cleanClubName, city: "", country: cleanCountry, isCustom: true))
        modelContext.insert(GolfCourse(clubName: cleanClubName, name: cleanCourseName, isCustom: true))
        modelContext.insert(
            TeeSet(
                clubName: cleanClubName,
                courseName: cleanCourseName,
                name: cleanTeeName,
                holes: holes,
                par: par,
                courseRating: courseRating,
                slopeRating: slopeRating,
                ratingSexRawValue: selectedRatingSex.rawValue,
                isCustom: true,
                holeParsData: savedHolePars,
                holeHandicapIndicesData: savedHoleHandicapIndices
            )
        )
        dismiss()
    }
}

private struct InfoLabel: View {
    let title: String
    let explanation: String

    @State private var isShowingInfo = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.body)
                    .foregroundStyle(PureLineStyle.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(title)")
            .sheet(isPresented: $isShowingInfo) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "questionmark.circle")
                                    .font(.title2)
                                    .foregroundStyle(PureLineStyle.accent)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(title)
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(PureLineStyle.ink)
                                    Text(explanation)
                                        .font(.body)
                                        .foregroundStyle(PureLineStyle.ink)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .pureLineCard()
                        }
                        .padding(18)
                    }
                    .background(PureLineStyle.canvas)
                    .tint(PureLineStyle.accent)
                    .navigationTitle("How It Works")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                isShowingInfo = false
                            }
                        }
                    }
                }
            }
        }
    }
}

struct HCPCustomCoursesEntryView: View {
    @Query(filter: #Predicate<GolfClub> { $0.isCustom == true }, sort: \GolfClub.name) private var clubs: [GolfClub]
    @Query(filter: #Predicate<GolfCourse> { $0.isCustom == true }, sort: \GolfCourse.name) private var courses: [GolfCourse]
    @Query(filter: #Predicate<TeeSet> { $0.isCustom == true }, sort: \TeeSet.name) private var tees: [TeeSet]
    @Query private var profiles: [PlayerProfile]
    @State private var courseCatalog: CourseCatalogStore?

    var body: some View {
        Group {
            if let courseCatalog {
                CustomCoursesView(courseCatalog: courseCatalog, profile: profiles.first, clubs: clubs, courses: courses, tees: tees)
            } else {
                ProgressView("Loading course catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PureLineStyle.canvas)
                    .navigationTitle("Custom Courses")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            guard courseCatalog == nil else { return }
            courseCatalog = await Task.detached(priority: .userInitiated) {
                CourseCatalogStore()
            }.value
        }
    }
}

private struct HCPSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let courseCatalog: CourseCatalogStore
    var profile: PlayerProfile?
    var clubs: [GolfClub]
    var courses: [GolfCourse]
    var tees: [TeeSet]

    @State private var selectedCountry = "Sweden"
    @State private var selectedScoringMode = RoundInputMode.adjustedGrossScore
    @State private var selectedSex = PlayerSex.male
    #if DEBUG
    @State private var showTestDataImportConfirm = false
    @State private var testDataMessage: String?
    @State private var exportedTestDataURL: URL?
    #endif

    private var customTeesCount: Int {
        tees.filter { $0.isCustom ?? false }.count
    }

    private var availableCountries: [String] {
        let customCountries = clubs.map(\.country).filter { !$0.isEmpty }
        return Array(Set(courseCatalog.countries + customCountries)).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    Picker("Tee Rating Category", selection: $selectedSex) {
                        ForEach(PlayerSex.allCases) { sex in
                            Text(sex == .male ? L("Men") : L("Women")).tag(sex)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedSex) {
                        updateSex(to: selectedSex)
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Round Defaults") {
                    Picker("Default Scoring Mode", selection: $selectedScoringMode) {
                        ForEach(RoundInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .background(PureLineStyle.surface)
                    .onChange(of: selectedScoringMode) {
                        updateScoringMode(to: selectedScoringMode)
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Region") {
                    Picker("Country / Region", selection: $selectedCountry) {
                        ForEach(availableCountries, id: \.self) { country in
                            Text(country).tag(country)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .background(PureLineStyle.surface)
                    .onChange(of: selectedCountry) {
                        updateCountry(to: selectedCountry)
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Course Data") {
                    NavigationLink {
                        CustomCoursesView(courseCatalog: courseCatalog, profile: profile, clubs: clubs, courses: courses, tees: tees)
                    } label: {
                        HStack {
                            Text("Custom Courses")
                            Spacer()
                            Text("\(customTeesCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section {
                    Link("Privacy Policy", destination: URL(string: "https://fairwayvector.com/hcp-projection/privacy-policy")!)
                }
                .listRowBackground(PureLineStyle.surface)

                #if DEBUG
                Section("Test Data") {
                    Button("Replace All Data With Test Data", role: .destructive) {
                        showTestDataImportConfirm = true
                    }
                    Button("Export Current Data") {
                        exportTestData()
                    }
                    if let exportedTestDataURL {
                        ShareLink(item: exportedTestDataURL) {
                            Text("Share Exported Snapshot")
                        }
                    }
                    if let testDataMessage {
                        Text(testDataMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(PureLineStyle.surface)
                #endif
            }
            .hcpPureLineList()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let profile {
                    let savedCountry = profile.countryOrDefault
                    selectedCountry = availableCountries.contains(savedCountry)
                        ? savedCountry
                        : (availableCountries.first ?? "Sweden")
                    selectedScoringMode = profile.defaultInputMode
                    selectedSex = profile.sexOrDefault
                    if profile.countryOrDefault != selectedCountry {
                        profile.selectedCountry = selectedCountry
                    }
                }
            }
            .onChange(of: availableCountries) {
                guard !availableCountries.contains(selectedCountry),
                      let fallback = availableCountries.first else { return }
                selectedCountry = fallback
                updateCountry(to: fallback)
            }
            #if DEBUG
            .confirmationDialog(
                L("Replace all data with the bundled test data?"),
                isPresented: $showTestDataImportConfirm,
                titleVisibility: .visible
            ) {
                Button("Replace Everything", role: .destructive) { importTestData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Existing profile, custom courses and rounds on this device will be deleted.")
            }
            #endif
        }
    }

    #if DEBUG
    private func importTestData() {
        do {
            let snapshot = try TestDataStore.importBundledSnapshot(into: modelContext)
            testDataMessage = "Imported \"\(snapshot.name)\" · \(snapshot.rounds.count) rounds."
        } catch {
            testDataMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func exportTestData() {
        do {
            let stamp = ISO8601DateFormatter().string(from: .now)
            let data = try TestDataStore.exportSnapshotJSON(from: modelContext, name: "Device snapshot \(stamp)")
            let url = URL.temporaryDirectory.appending(path: "hcp-testdata.json")
            try data.write(to: url, options: .atomic)
            exportedTestDataURL = url
            testDataMessage = "Exported \(data.count) bytes."
        } catch {
            testDataMessage = "Export failed: \(error.localizedDescription)"
        }
    }
    #endif

    private func updateScoringMode(to newMode: RoundInputMode) {
        if let profile {
            profile.defaultInputMode = newMode
        } else {
            let newProfile = PlayerProfile(
                name: "Player",
                selectedCountry: selectedCountry,
                defaultInputModeRawValue: newMode.rawValue,
                sexRawValue: selectedSex.rawValue
            )
            modelContext.insert(newProfile)
        }
    }

    private func updateCountry(to newCountry: String) {
        if let profile {
            profile.selectedCountry = newCountry
        } else {
            let newProfile = PlayerProfile(
                name: "Player",
                selectedCountry: newCountry,
                defaultInputModeRawValue: selectedScoringMode.rawValue,
                sexRawValue: selectedSex.rawValue
            )
            modelContext.insert(newProfile)
        }
    }

    private func updateSex(to newSex: PlayerSex) {
        if let profile {
            profile.sexOrDefault = newSex
        } else {
            let newProfile = PlayerProfile(
                name: "Player",
                selectedCountry: selectedCountry,
                defaultInputModeRawValue: selectedScoringMode.rawValue,
                sexRawValue: newSex.rawValue
            )
            modelContext.insert(newProfile)
        }
    }
}

struct RoundDetailView: View {
    var round: GolfRound
    var handicapIndex: Double?

    private var userNotes: String {
        let notes = round.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // Hide only the exact legacy import boilerplate; preserve user notes.
        let legacyPrefix = "Copied explicitly from saved scorecard. Total strokes include putts and penalties. PCC 0; local estimate, not an official submission. Index at play: "
        if round.sourceSavedRoundID != nil, notes.hasPrefix(legacyPrefix), notes.hasSuffix("."),
           Double(String(notes.dropFirst(legacyPrefix.count).dropLast())) != nil {
            return ""
        }
        return notes
    }

    private var differential: Double? {
        WHSCalculator.scoringEntry(for: round, currentHandicapIndex: handicapIndex)?.scoreDifferential
    }

    private var courseHandicap: Int {
        WHSCalculator.courseHandicap(handicapIndex: handicapIndex ?? 0, tee: round.teeSnapshot)
    }

    private var isNoCourseRound: Bool {
        round.courseName.isEmpty && round.clubName.isEmpty
    }

    var body: some View {
        List {
            Section(isNoCourseRound ? L("Round") : L("Course & Tee")) {
                if isNoCourseRound {
                    LabeledContent("Course", value: L("No Course"))
                } else {
                    LabeledContent("Course", value: round.courseName)
                    LabeledContent("Club", value: round.clubName)
                    LabeledContent("Tee", value: round.teeName)
                    LabeledContent("Holes", value: "\(round.holes)")
                    LabeledContent("Par", value: String(round.par))
                    LabeledContent("Course rating", value: round.courseRating.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("Slope rating", value: String(round.slopeRating))
                }
                LabeledContent("Date", value: round.date.formatted(date: .abbreviated, time: .omitted))
            }
            .listRowBackground(PureLineStyle.surface)

            if round.holes == 9 {
                Section {
                    HCPNineHoleNotice()
                }
                .listRowBackground(PureLineStyle.surface)
            }

            Section("Handicap Performance") {
                if let differential {
                    LabeledContent("HCP Score", value: WHSCalculator.formatHCPScore(differential))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PureLineStyle.ink)
                }
                if let handicapIndex {
                    LabeledContent("Playing Handicap Index", value: WHSCalculator.formatHCPScore(handicapIndex))
                }
                if !isNoCourseRound {
                    LabeledContent("Course Handicap", value: "\(courseHandicap)")
                }
                if round.pcc != 0 {
                    LabeledContent {
                        Text(round.pcc.formatted(.number.precision(.fractionLength(1))))
                    } label: {
                        InfoLabel(
                            title: L("PCC Adjustment"),
                            explanation: L("Playing Conditions Calculation. This adjusts the score differential when the course is playing noticeably easier or harder than normal because of weather, setup, or course conditions.")
                        )
                    }
                }
            }
            .listRowBackground(PureLineStyle.surface)

            if !isNoCourseRound {
                Section("Score Summary") {
                if let gross = round.adjustedGrossScore {
                    LabeledContent {
                        Text("\(gross)")
                            .monospacedDigit()
                    } label: {
                        InfoLabel(
                            title: L("Adjusted Gross Score"),
                            explanation: L("Adjusted Gross Score is the adjusted total for handicap purposes. It reflects your actual score after WHS limits are applied to unusually high hole scores, so it is the number used in handicap calculation.")
                        )
                    }
                }
                if let points = round.stablefordPoints {
                    LabeledContent("Stableford Points", value: L("%@ pts", "\(points)"))
                }
                if !userNotes.isEmpty {
                    LabeledContent("Notes", value: userNotes)
                }
                }
                .listRowBackground(PureLineStyle.surface)
            } else if !userNotes.isEmpty {
                Section("Notes") {
                    Text(userNotes)
                }
                .listRowBackground(PureLineStyle.surface)
            }

            if let holeScores = round.holeScores, !holeScores.isEmpty {
                let pars = round.holePars ?? TeeSet.defaultPars(for: round.holes, totalPar: round.par)
                let indices = round.holeHandicapIndices ?? Array(1...max(round.holes, 1))
                let safeHoleCount = min(holeScores.count, min(pars.count, indices.count))
                let calc = WHSCalculator.calculateHoleByHole(
                    holeScores: holeScores,
                    holePars: pars,
                    holeHandicapIndices: indices,
                    courseHandicap: courseHandicap
                )

                Section("Hole by Hole Breakdown") {
                    ForEach(0..<safeHoleCount, id: \.self) { i in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hole \(i + 1)")
                                    .font(.headline)
                                Text("Par \(pars[i]) · Index \(indices[i])")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if i < calc.holePoints.count {
                                Text("\(calc.holePoints[i]) pts")
                                    .font(.caption.bold().monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PureLineStyle.accent.opacity(0.08))
                                    .foregroundStyle(PureLineStyle.accent)
                                    .clipShape(Capsule())
                            }
                            Text("\(holeScores[i]) strokes")
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
                .listRowBackground(PureLineStyle.surface)
            }
        }
        .hcpPureLineList()
        .navigationTitle("Round details")
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct MetricCard: View {
    var title: String
    var value: String
    var systemImage: String
    var subtitle: String? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(PureLineStyle.accent)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PureLineStyle.muted)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(PureLineStyle.muted)
            }
            Text(value)
                .font(.system(size: valueSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(PureLineStyle.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard(padding: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct RoundRow: View {
    var round: GolfRound
    var isCountingRound: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var differential: Double? {
        WHSCalculator.scoringEntry(for: round)?.scoreDifferential
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    let titleLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(spacing: 6))
                    titleLayout {
                        Text(round.courseName.isEmpty ? L("No Course") : round.courseName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(PureLineStyle.ink)
                        if isCountingRound {
                            Text("Counts for HCP")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PureLineStyle.accent.opacity(0.08))
                                .foregroundStyle(PureLineStyle.accent)
                                .clipShape(Capsule())
                        }
                    }
                    if !round.clubName.isEmpty || !round.teeName.isEmpty {
                        Text([round.clubName, round.teeName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                VStack(alignment: .trailing, spacing: 4) {
                    if let differential {
                        Text("HCP score")
                            .font(.caption2)
                            .foregroundStyle(PureLineStyle.muted)
                        Text(WHSCalculator.formatHCPScore(differential))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(isCountingRound ? PureLineStyle.accent : PureLineStyle.ink)
                    }
                    Text(round.date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let differential {
                if round.handicapDifferential == nil {
                    Text("HCP score: \(WHSCalculator.formatHCPScore(differential)) · \(round.scoreSummaryText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(round.scoreSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TargetResultRow: View {
    var result: TargetResult
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(primaryText)
                        .font(.headline)
                    if result.change == 0 {
                        Text("No impact")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PureLineStyle.line.opacity(0.5))
                            .foregroundStyle(PureLineStyle.muted)
                            .clipShape(Capsule())
                    }
                }
                Text("HCP score: \(WHSCalculator.formatHCPScore(result.scoreDifferential))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: .trailing, spacing: 4) {
                Text("Projected index")
                    .font(.caption2)
                    .foregroundStyle(PureLineStyle.muted)
                Text(WHSCalculator.formatHCPScore(result.projectedHandicapIndex))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PureLineStyle.ink)
                Text(changeText)
                    .font(.caption)
                    .foregroundStyle(changeColor)
            }
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
        }
        .padding(.vertical, 8)
    }

    private var primaryText: String {
        switch result.inputMode {
        case .adjustedGrossScore, .holeByHole:
            L("Score %@", "\(result.value)")
        case .stablefordPoints:
            L("%@ points", "\(result.value)")
        }
    }

    private var changeText: String {
        if result.change == 0 {
            return L("±0.0 (Score not used)")
        }
        let prefix = result.change > 0 ? "+" : ""
        return "\(prefix)\(result.change.formatted(.number.precision(.fractionLength(1))))"
    }

    private var changeColor: Color {
        if result.change < 0 {
            return PureLineStyle.ink
        } else if result.change > 0 {
            return PureLineStyle.accent
        } else {
            return PureLineStyle.muted
        }
    }
}

private extension TeeSet {
    var displayName: String {
        "\(clubName) · \(courseName) · \(name)"
    }

    var snapshot: TeeSnapshot {
        TeeSnapshot(
            clubName: clubName,
            courseName: courseName,
            teeName: name,
            holes: holes,
            par: par,
            courseRating: courseRating,
            slopeRating: slopeRating
        )
    }
}

// Presentation styles are scoped to this file; shared settings remain unchanged.
