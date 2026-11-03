import SwiftData
import SwiftUI

struct PureLineHomeView: View {
    let onOpenCourseMap: () -> Void
    let onStartRound: () -> Void
    let onResumeRound: () -> Void
    let onOpenHandicap: () -> Void
    let onOpenBag: () -> Void
    let onOpenWedge: () -> Void
    let onOpenTrajectory: () -> Void
    let onOpenStatistics: () -> Void
    let onOpenSettings: () -> Void
    @ObservedObject var profileStore: PlayerProfileStore
    @Environment(PlayedRoundStore.self) private var roundStore
    @Query private var handicapRounds: [GolfRound]
    @Query private var profiles: [PlayerProfile]
    @AppStorage("onboarding.statisticsOpened.v1") private var statisticsOpened = false
    @AppStorage("onboarding.getStartedDismissed.v1") private var getStartedDismissed = false

    private var gettingStarted: (clubs: Bool, round: Bool, statistics: Bool) {
        (GettingStartedProgress.clubDistancesEntered(profile: profileStore.profile, wedges: profileStore.wedges),
         !roundStore.saved.isEmpty || !handicapRounds.isEmpty,
         statisticsOpened)
    }

    private var handicapIndex: Double? {
        let low = profiles.first?.lowHandicapIndex
        return WHSCalculator.handicapIndex(
            from: WHSCalculator.scoringEntries(from: handicapRounds, lowHandicapIndex: low), lowHandicapIndex: low)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        Label("BY FAIRWAYVECTOR", systemImage: "location.north.circle")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.8)
                        Spacer()
                        Button(action: onOpenSettings) {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.medium))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PureLineStyle.accent)
                        .accessibilityLabel("Global settings")
                        .accessibilityIdentifier("global-settings-button")
                    }
                    .foregroundStyle(PureLineStyle.muted)
                    .padding(.top, 12)

                    if let round = roundStore.active {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Round in progress", systemImage: "flag.checkered").font(.headline)
                            Text("\(round.reference.courseName) · \(round.reference.teeName) · hole \(round.holes[round.currentHole].number)")
                                .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                            Button("Resume round", action: onResumeRound)
                                .buttonStyle(PureLinePrimaryButtonStyle())
                                .accessibilityIdentifier("home-resume-round")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pureLineCard(padding: 24)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Know your numbers.\nPlay better golf.")
                            .font(.system(.largeTitle, design: .default).weight(.semibold))
                            .tracking(-1.2)
                            .foregroundStyle(PureLineStyle.ink)
                        Text("Distances, club advice and stats that show where your strokes go.")
                            .font(.subheadline)
                            .foregroundStyle(PureLineStyle.muted)
                    }

                    let steps = gettingStarted
                    if !getStartedDismissed, !(steps.clubs && steps.round && steps.statistics) {
                        getStartedCard(steps)
                    }

                    if let handicapIndex {
                        Button(action: onOpenHandicap) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Handicap Index")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(PureLineStyle.muted)
                                    Text(WHSCalculator.formatHCPScore(handicapIndex))
                                        .font(.title.weight(.semibold)).monospacedDigit()
                                        .foregroundStyle(PureLineStyle.ink)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PureLineStyle.muted)
                            }
                            .contentShape(Rectangle())
                            .pureLineCard(padding: 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("home-handicap-index")
                    }

                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ON THE COURSE")
                                    .font(.caption2.weight(.semibold)).tracking(1.5)
                                    .foregroundStyle(PureLineStyle.accent)
                                Text("Make your next\nround count.")
                                    .font(.title2.weight(.semibold)).tracking(-0.6)
                                    .foregroundStyle(PureLineStyle.ink)
                            }
                            Spacer()
                            Image(systemName: "flag")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(PureLineStyle.accent)
                                .frame(width: 56, height: 56)
                                .background(.white, in: Circle())
                        }
                        Text("Explore the hole, plan your shot, and keep your scorecard close.")
                            .font(.subheadline)
                            .foregroundStyle(PureLineStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: onStartRound) {
                            HStack {
                                Text("Start round")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.padding(.horizontal, 20)
                        }
                        .buttonStyle(PureLinePrimaryButtonStyle())
                        Button(action: onOpenCourseMap) {
                            HStack {
                                Label("Explore a course", systemImage: "map")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PureLineStyle.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .pureLineCard(padding: 24)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Build your game")
                            .font(.title3.weight(.semibold)).tracking(-0.4)
                            .padding(.bottom, 10)
                        destination(L("In the bag"), detail: L("Set up your clubs and wedges"), symbol: "bag", action: onOpenBag)
                        Divider().overlay(PureLineStyle.line)
                        destination(L("Wedge Matrix"), detail: L("Your distances. Every swing."), symbol: "target", action: onOpenWedge)
                        Divider().overlay(PureLineStyle.line)
                        destination(L("Trajectory"), detail: L("Club choice and ball flight from your own numbers"), symbol: "chart.xyaxis.line", action: onOpenTrajectory)
                    }
                    .foregroundStyle(PureLineStyle.ink)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("See your game")
                            .font(.title3.weight(.semibold)).tracking(-0.4)
                            .padding(.bottom, 10)
                        destination(L("Rounds & statistics"), detail: statisticsDetail, symbol: "chart.xyaxis.line", action: openStatistics)
                            .accessibilityIdentifier("home-rounds-statistics-button")
                        Divider().overlay(PureLineStyle.line)
                        destination(L("Handicap"), detail: L("Round history & score projections"), symbol: "chart.line.uptrend.xyaxis", action: onOpenHandicap)
                    }
                    .foregroundStyle(PureLineStyle.ink)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "location")
                            .foregroundStyle(PureLineStyle.accent)
                        Text("Enable location for live GPS distances. Loaded course data stays available offline.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(PureLineStyle.muted)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
            .background(PureLineStyle.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(PureLineStyle.accent)
        .accessibilityIdentifier("map-home-screen")
    }

    private func openStatistics() {
        statisticsOpened = true
        onOpenStatistics()
    }

    private var statisticsDetail: String {
        let records = RoundPerformanceRecord.combined(played: roundStore.saved, handicap: handicapRounds)
        if case .changes(let workOn?, _) = RecentFormAnalysis.analyze(records) {
            return L("Work on: %@", workOn.area.title)
        }
        return L("Review your scores and spot the trends")
    }

    private func getStartedCard(_ steps: (clubs: Bool, round: Bool, statistics: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Get started").font(.headline)
                Spacer()
                Button { getStartedDismissed = true } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(PureLineStyle.muted)
                .accessibilityLabel("Hide")
            }
            getStartedStep(L("Enter your club distances"), detail: L("Better club advice on the course"),
                           done: steps.clubs, action: onOpenBag)
            Divider().overlay(PureLineStyle.line)
            getStartedStep(L("Play or record a round"), detail: L("Start a round, or add one in Handicap"),
                           done: steps.round, action: onStartRound)
            Divider().overlay(PureLineStyle.line)
            getStartedStep(L("See your statistics"), detail: L("Find where your strokes go"),
                           done: steps.statistics, action: openStatistics)
        }
        .pureLineCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-get-started")
    }

    private func getStartedStep(_ title: String, detail: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? PureLineStyle.accent : PureLineStyle.muted)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(PureLineStyle.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PureLineStyle.muted)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(PureLineStyle.ink)
        .accessibilityValue(done ? L("Done") : L("Not done"))
    }

    private func destination(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(PureLineStyle.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(PureLineStyle.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption).foregroundStyle(PureLineStyle.muted)
            }
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}