import SwiftUI

struct CourseSelectionView: View {
    let onStartCourse: (CourseReference) -> Void
    let onStartRound: ((CourseReference) -> Void)?
    let onResumeRound: ((PlayedRound) -> Void)?
    let showsRoundInProgress: Bool
    let isStartRoundFlow: Bool
    var onHome: () -> Void = {}
    @Environment(PlayedRoundStore.self) private var roundStore
    @State private var confirmDiscardRound = false

    init(showsRoundInProgress: Bool = false, isStartRoundFlow: Bool = false,
         onStartRound: ((CourseReference) -> Void)? = nil,
         onResumeRound: ((PlayedRound) -> Void)? = nil,
         onHome: @escaping () -> Void = {},
         onStartCourse: @escaping (CourseReference) -> Void) {
        self.showsRoundInProgress = showsRoundInProgress
        self.isStartRoundFlow = isStartRoundFlow
        self.onStartRound = onStartRound
        self.onResumeRound = onResumeRound
        self.onHome = onHome
        self.onStartCourse = onStartCourse
    }

    @State private var model = GolfAPICourseSelectionModel()
    @State private var isClubPagePresented = false
    @AppStorage(RecentProviderCourseStore.key) private var recentProviderCoursesData = Data()
    @AppStorage("map.recentCourseReference") private var recentCourseData = Data()
    @AppStorage("hcp.provider.recentCourseReference.v1") private var hcpRecentCourseData = Data()
    @AppStorage("map.development.recentCourseReference.v1") private var demoRecentCourseData = Data()
    private var isMock: Bool { DevelopmentAPIConfiguration.current.golfAPI == .mock }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PureLineHomeButton(onHome: onHome)
                GeometryReader { geometry in
                ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {
                    PureLinePageHeader(title: isStartRoundFlow ? "Start a round" : "Explore a course",
                        subtitle: "Choose your course and tee.")
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

                    if !model.hasSearched, !recentProviderCourses.isEmpty {
                        recentCoursesSection(recentProviderCourses)
                    }

                    CourseSelectionStatus(model: model)

                    if !model.clubs.isEmpty {
                        CourseClubCards(clubs: model.clubs, selectedClubID: model.selectedClubID,
                                        title: "CLUBS · \(model.clubs.count) OF \(model.totalClubCount)", onSelect: { club in
                                            model.selectClub(club)
                                            isClubPagePresented = true
                                        })
                        if model.hasMoreClubs { CourseCatalogMoreButton(model: model) }
                    }
                }
                .foregroundStyle(PureLineStyle.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(width: geometry.size.width, alignment: .leading)
                }
                .background(PureLineStyle.canvas)
                }
            }
            .background(PureLineStyle.canvas)
            .navigationDestination(isPresented: $isClubPagePresented) {
                if let club = model.selectedClub {
                    CourseClubSelectionPage(model: model, club: club,
                        isStartRoundFlow: isStartRoundFlow,
                        onStartCourse: { startCourse($0) },
                        onStartRound: { startRound($0) })
                }
            }
            .navigationTitle("Choose Course")
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
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

    private var recentProviderCourses: [CourseReference] {
        var saved = RecentProviderCourseStore.decode(recentProviderCoursesData)
        if saved.isEmpty {
            let legacy = [recentCourseData, hcpRecentCourseData]
                .compactMap { try? JSONDecoder().decode(CourseReference.self, from: $0) }
            if let paused = try? JSONDecoder().decode(CourseReference.self, from: demoRecentCourseData) {
                saved.append(paused)
            }
            saved = RecentProviderCourseStore.decode(RecentProviderCourseStore.merging(legacy, into: Data()))
            if !saved.isEmpty {
                recentProviderCoursesData = (try? JSONEncoder().encode(saved)) ?? Data()
            }
        }
        return saved
    }

    private func startCourse(_ reference: CourseReference) {
        if let data = try? JSONEncoder().encode(reference) {
            if isMock { demoRecentCourseData = data } else { recentCourseData = data }
            if !DevelopmentAPIConfiguration.isDemoCourse(reference.golfAPICourseID ?? "") {
                recentProviderCoursesData = RecentProviderCourseStore.recording(reference, in: recentProviderCoursesData)
            }
        }
        onStartCourse(reference)
    }

    private func startRound(_ reference: CourseReference) {
        recentProviderCoursesData = RecentProviderCourseStore.recording(reference, in: recentProviderCoursesData)
        onStartRound?(reference)
    }

    private func recentCoursesSection(_ references: [CourseReference]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CourseSelectionHeading(title: "RECENTLY SELECTED")
            ForEach(references, id: \.golfAPICourseID) { reference in
                Button {
                    if isStartRoundFlow {
                        startRound(reference)
                    } else {
                        startCourse(reference)
                    }
                } label: {
                    CourseRecentCard(reference: reference, status: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recent-course-button-\(reference.golfAPICourseID ?? "course")")
            }
        }
    }

}
