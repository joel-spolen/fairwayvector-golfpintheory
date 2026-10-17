import SwiftUI

struct CourseSelectionView: View {
    let onStartCourse: (CourseReference) -> Void
    let onStartRound: ((CourseReference) -> Void)?
    let onResumeRound: ((PlayedRound) -> Void)?
    let showsRoundInProgress: Bool
    let isStartRoundFlow: Bool
    @Environment(PlayedRoundStore.self) private var roundStore
    @State private var confirmDiscardRound = false

    init(showsRoundInProgress: Bool = false, isStartRoundFlow: Bool = false,
         onStartRound: ((CourseReference) -> Void)? = nil,
         onResumeRound: ((PlayedRound) -> Void)? = nil,
         onStartCourse: @escaping (CourseReference) -> Void) {
        self.showsRoundInProgress = showsRoundInProgress
        self.isStartRoundFlow = isStartRoundFlow
        self.onStartRound = onStartRound
        self.onResumeRound = onResumeRound
        self.onStartCourse = onStartCourse
    }

    @State private var model = GolfAPICourseSelectionModel()
    @AppStorage("map.recentCourseReference") private var recentCourseData = Data()
    @AppStorage("map.development.recentCourseReference.v1") private var demoRecentCourseData = Data()
    private var isMock: Bool { DevelopmentAPIConfiguration.current.golfAPI == .mock }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isStartRoundFlow ? "Start a round" : "Where to?")
                            .font(.largeTitle.weight(.semibold)).tracking(-1)
                        Text(isStartRoundFlow ? "Choose your course and tee." : "Find your course. Choose your tee.")
                            .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                    }
                    if showsRoundInProgress, let round = roundStore.active {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Round in progress", systemImage: "flag.checkered").font(.headline)
                            Text("\(round.reference.courseName) · \(round.reference.teeName) · hole \(round.holes[round.currentHole].number)")
                                .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                            Button("Resume round") { onResumeRound?(round) }
                                .buttonStyle(PureLinePrimaryButtonStyle())
                            Button("Discard unsaved round", role: .destructive) { confirmDiscardRound = true }
                                .font(.subheadline)
                        }
                        .pureLineCard()
                    }
                    if let message = roundStore.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(PureLineStyle.ink)
                        if roundStore.draftNeedsRetry {
                            Button("Retry saving draft") {
                                do { try roundStore.retryDraft() } catch { roundStore.errorMessage = error.localizedDescription }
                            }
                        } else { Button("Retry loading round storage") { roundStore.load() } }
                    }
                    CourseSearchControls(model: model)

                    if let recentCourse {
                        recentCourseShortcut(recentCourse)
                    }

                    CourseSelectionStatus(model: model)

                    if !model.clubs.isEmpty {
                        CourseClubCards(clubs: model.clubs, selectedClubID: model.selectedClubID,
                                        title: "CLUBS · \(model.clubs.count)", onSelect: model.selectClub)
                    }

                    if let club = model.selectedClub {
                        CourseResultCards(model: model, club: club)
                    }

                    if model.isLoadingCourse {
                        CourseSelectionLoading()
                    }

                    if let detail = model.courseDetail {
                        CourseTeeSelectionCard(model: model, detail: detail)
                    }

                    if let selection = model.selection {
                        CourseSelectionSummaryCard(selection: selection)
                        Button {
                            startCourse(selection.reference)
                        } label: {
                            Label("View Course", systemImage: "map.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(PureLinePrimaryButtonStyle())
                        .tint(PureLineStyle.accent)
                        .accessibilityIdentifier("view-course-button")
                        if let onStartRound {
                            Button("Start round", systemImage: "flag.checkered") { onStartRound(selection.reference) }
                                .buttonStyle(PureLinePrimaryButtonStyle())
                        }
                    }

                }
                .foregroundStyle(PureLineStyle.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(PureLineStyle.canvas)
            .navigationTitle("Choose Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(PureLineStyle.accent)
        .confirmationDialog("Discard the unsaved round?", isPresented: $confirmDiscardRound, titleVisibility: .visible) {
            Button("Discard round", role: .destructive) {
                do { try roundStore.discardDraft() } catch { roundStore.errorMessage = error.localizedDescription }
            }
        } message: {
            Text("All unsaved player scores will be removed. Saved Statistics and Handicap history remain.")
        }
    }

    private var recentCourse: CourseReference? {
        if isMock {
            let live = try? JSONDecoder().decode(CourseReference.self, from: recentCourseData)
            // A usable live recent takes precedence over any previous demo shortcut.
            if let live, model.hasSavedCourse(live) { return live }
            let paused = try? JSONDecoder().decode(CourseReference.self, from: demoRecentCourseData)
            if let paused, model.hasSavedCourse(paused) { return paused }
            return live ?? paused
        }
        let saved = try? JSONDecoder().decode(CourseReference.self, from: recentCourseData)
        return saved.flatMap { DevelopmentAPIConfiguration.isDemoCourse($0.golfAPICourseID ?? "") ? nil : $0 }
    }

    private func startCourse(_ reference: CourseReference) {
        if let data = try? JSONEncoder().encode(reference) {
            if isMock { demoRecentCourseData = data } else { recentCourseData = data }
        }
        onStartCourse(reference)
    }

    private func recentCourseShortcut(_ reference: CourseReference, title: String = "RECENTLY SELECTED") -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(PureLineStyle.muted)

            Button {
                if isStartRoundFlow, let onStartRound {
                    onStartRound(reference)
                } else {
                    startCourse(reference)
                }
            } label: {
                CourseRecentCard(reference: reference, status: nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recent-course-button")
            .accessibilityHint(isStartRoundFlow
                ? "Continues to round setup for this course and tee"
                : "Opens this course with your previously selected tee set")
        }
    }
}
