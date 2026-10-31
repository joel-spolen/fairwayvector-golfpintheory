import SwiftData
import OSLog
import SwiftUI

struct SyncableLocalDataFingerprint: Encodable {
    struct Golfer: Encodable {
        let name: String
        let lowHandicapIndex: Double?
    }
    struct Club: Encodable {
        let name: String
        let city: String
        let country: String
    }
    struct Course: Encodable {
        let clubName: String
        let name: String
    }
    struct Tee: Encodable {
        let clubName: String
        let courseName: String
        let name: String
        let holes: Int
        let par: Int
        let courseRating: Double
        let slopeRating: Int
        let ratingSex: String?
        let holePars: [Int]?
        let holeHandicapIndices: [Int]?
    }
    struct HandicapRound: Encodable {
        let syncID: UUID?
        let date: Date
        let clubName: String
        let courseName: String
        let teeName: String
        let holes: Int
        let inputMode: String
        let adjustedGrossScore: Int?
        let stablefordPoints: Int?
        let handicapDifferential: Double?
        let par: Int
        let courseRating: Double
        let slopeRating: Int
        let pcc: Double
        let notes: String
        let holeScores: [Int]?
        let holePars: [Int]?
        let holeHandicapIndices: [Int]?
        let sourceSavedRoundID: String?
    }

    let golfer: Golfer?
    let clubs: [Club]
    let courses: [Course]
    let tees: [Tee]
    let handicapRounds: [HandicapRound]
}

/// Observes only account-owned fields approved for sync; unrelated preferences
/// and provider/catalog changes do not schedule uploads.
private struct SyncableLocalDataMonitor: View {
    let isEnabled: Bool
    let onChanged: () -> Void

    @Query private var profiles: [PlayerProfile]
    @Query private var clubs: [GolfClub]
    @Query private var courses: [GolfCourse]
    @Query private var tees: [TeeSet]
    @Query private var rounds: [GolfRound]
    private var fingerprint: Data {
        let snapshot = SyncableLocalDataFingerprint(
            golfer: profiles.first.map { .init(name: $0.name, lowHandicapIndex: $0.lowHandicapIndex) },
            clubs: clubs.filter { $0.isCustom == true }
                .map { .init(name: $0.name, city: $0.city, country: $0.country) }
                .sorted { "\($0.country)|\($0.city)|\($0.name)" < "\($1.country)|\($1.city)|\($1.name)" },
            courses: courses.filter { $0.isCustom == true }
                .map { .init(clubName: $0.clubName, name: $0.name) }
                .sorted { "\($0.clubName)|\($0.name)" < "\($1.clubName)|\($1.name)" },
            tees: tees.filter { $0.isCustom == true }
                .map { .init(clubName: $0.clubName, courseName: $0.courseName, name: $0.name,
                    holes: $0.holes, par: $0.par, courseRating: $0.courseRating,
                    slopeRating: $0.slopeRating, ratingSex: $0.ratingSexRawValue,
                    holePars: $0.holeParsData, holeHandicapIndices: $0.holeHandicapIndicesData) }
                .sorted { "\($0.clubName)|\($0.courseName)|\($0.name)" < "\($1.clubName)|\($1.courseName)|\($1.name)" },
            handicapRounds: rounds.map { .init(syncID: $0.syncID, date: $0.date,
                clubName: $0.clubName, courseName: $0.courseName, teeName: $0.teeName,
                holes: $0.holes, inputMode: $0.inputModeRawValue,
                adjustedGrossScore: $0.adjustedGrossScore, stablefordPoints: $0.stablefordPoints,
                handicapDifferential: $0.handicapDifferential, par: $0.par,
                courseRating: $0.courseRating, slopeRating: $0.slopeRating, pcc: $0.pcc,
                notes: $0.notes, holeScores: $0.holeScoresData, holePars: $0.holeParsData,
                holeHandicapIndices: $0.holeHandicapIndicesData, sourceSavedRoundID: $0.sourceSavedRoundID) }
                .sorted { ($0.syncID?.uuidString ?? "") < ($1.syncID?.uuidString ?? "") })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(snapshot)) ?? Data()
    }

    var body: some View {
        Color.clear
            .onChange(of: fingerprint) { _, _ in
                if isEnabled { onChanged() }
            }
            .accessibilityHidden(true)
    }
}

struct ContentView: View {
    private let syncLogger = Logger(subsystem: "com.fairwayvector.app.pintheory", category: "CloudSync")
    let accountData: PinTheoryAccountData
    @EnvironmentObject private var accountSession: PinTheoryAccountSession

    private enum Destination: String, Identifiable {
        case course
        case handicap
        case practice
        case statistics
        case bag
        case account

        var id: String { rawValue }
    }

    @AppStorage("distanceUnit", store: .standard) private var distanceUnit: DistanceUnit = .meters
    @AppStorage("wedgeMatrix.distanceUnit", store: .standard) private var wedgeDistanceUnit = WedgeDistanceUnit.yards.rawValue
    @State private var destination: Destination?
    @State private var showingSettings = false
    @State private var practiceDestination: PracticeDestination = .trajectory
    @StateObject private var trajectoryModel: TrajectoryCalculatorViewModel
    @State private var roundStore: PlayedRoundStore
    @State private var requestStartRound = false
    @State private var automaticSyncTask: Task<Void, Never>?

    init(accountData: PinTheoryAccountData) {
        self.accountData = accountData
        _trajectoryModel = StateObject(wrappedValue: TrajectoryCalculatorViewModel(
            playerProfileStore: PlayerProfileStore(userDefaults: accountData.defaults)))
        _roundStore = State(initialValue: PlayedRoundStore(url: accountData.roundsURL))
    }

    var body: some View {
        ZStack {
            PureLineHomeView(
                onOpenCourseMap: { requestStartRound = false; destination = .course },
                onStartRound: { requestStartRound = true; destination = .course },
                onOpenHandicap: { destination = .handicap },
                onOpenBag: { destination = .bag },
                onOpenWedge: {
                    practiceDestination = .wedge
                    destination = .practice
                },
                onOpenTrajectory: {
                    practiceDestination = .trajectory
                    destination = .practice
                },
                onOpenStatistics: { destination = .statistics },
                onOpenSettings: { showingSettings = true },
                onOpenAccount: { destination = .account }
            )

        }
        .background {
            KeyboardDismissOnTap()
        }
        .environment(\.colorScheme, .light)
        .overlay { SharedHandicapSync(trajectoryModel: trajectoryModel).allowsHitTesting(false) }
        .environmentObject(trajectoryModel)
        .environment(roundStore)
        .modelContainer(accountData.modelContainer)
        .overlay {
            SyncableLocalDataMonitor(isEnabled: accountSession.hasOptedIntoSavedDataSync) {
                scheduleAutomaticSync()
            }
            .modelContainer(accountData.modelContainer)
            .frame(width: 0, height: 0)
        }
        .fullScreenCover(item: $destination, onDismiss: { requestStartRound = false }) { screen in
            feature(screen)
                .environmentObject(trajectoryModel)
                .environment(roundStore)
                .modelContainer(accountData.modelContainer)
                .defaultAppStorage(accountData.defaults)
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showingSettings) {
            UnifiedSettingsView()
            .environmentObject(trajectoryModel)
            .environment(roundStore)
            .modelContainer(accountData.modelContainer)
            .defaultAppStorage(accountData.defaults)
            .preferredColorScheme(.light)
        }
        .onChange(of: distanceUnit, initial: true) { _, unit in
            wedgeDistanceUnit = unit == .meters ? WedgeDistanceUnit.meters.rawValue : WedgeDistanceUnit.yards.rawValue
            trajectoryModel.unitPreferences.globalDefault = unit == .meters ? .metric : .imperial
        }
        .task { await syncSavedDataIfEnabled() }
        .onChange(of: roundStore.savedRevision) { _, _ in
            scheduleAutomaticSync()
        }
        // Unlike an environment override, this also controls presented screens.
        .preferredColorScheme(.light)
        .defaultAppStorage(accountData.defaults)
    }

    @ViewBuilder private func feature(_ screen: Destination) -> some View {
        switch screen {
        case .course:
            CourseMapFlowView(onHome: { destination = nil }, requestStartRound: $requestStartRound)
        case .handicap:
            HCPProjectionEntryView(onHome: { destination = nil })
        case .practice:
            PracticeView(destination: $practiceDestination, trajectoryModel: trajectoryModel, onHome: { destination = nil })
        case .statistics:
            RoundStatisticsView()
        case .bag:
            InTheBagView(trajectoryModel: trajectoryModel, onHome: { destination = nil }, onSave: {
                Task { @MainActor in await syncSavedDataIfEnabled() }
            })
        case .account:
            PinTheoryAccountView(onHome: { destination = nil })
        }
    }

    @MainActor
    private func syncSavedDataIfEnabled() async {
        guard accountSession.hasOptedIntoSavedDataSync else {
            syncLogger.debug("Startup sync skipped: disabled in Settings")
            return
        }
        syncLogger.info("Startup sync requested")
        let context = accountData.modelContainer.mainContext
        let profile = (try? context.fetch(FetchDescriptor<PlayerProfile>()))?.first
        await accountSession.enableAndSyncSavedData(roundStore: roundStore, profile: profile,
            trajectoryProfileStore: trajectoryModel.playerProfileStore, modelContext: context)
    }

    @MainActor
    private func scheduleAutomaticSync() {
        guard accountSession.hasOptedIntoSavedDataSync else { return }
        syncLogger.info("Saved syncable data changed; scheduling sync")
        automaticSyncTask?.cancel()
        automaticSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            // This task owns only the debounce timer. A later save must not
            // cancel an upload/pull already in progress.
            automaticSyncTask = nil
            Task { @MainActor in await syncSavedDataIfEnabled() }
        }
    }

}

private struct CourseMapFlowView: View {
    let onHome: () -> Void
    @State private var selection: CourseReference?
    @State private var resumedRound: PlayedRound?
    @State private var isStartingRoundFlow = false
    @State private var setupReference: CourseReference?
    @State private var setupCourse: Course?
    @State private var isLoadingSetupCourse = false
    @State private var setupCourseError: String?
    @Binding var requestStartRound: Bool
    @Environment(PlayedRoundStore.self) private var roundStore
    @EnvironmentObject private var trajectoryModel: TrajectoryCalculatorViewModel

    var body: some View {
        if let setupReference, let setupCourse {
            RoundSetupView(selectedCourseReference: setupReference, course: setupCourse,
                dismissOnCompletion: false,
                onStarted: {
                    resumedRound = roundStore.active
                    selection = setupReference
                    self.setupCourse = nil
                    self.setupReference = nil
                    isStartingRoundFlow = false
                    requestStartRound = false
                },
                onCancel: {
                    self.setupCourse = nil
                    self.setupReference = nil
                    isStartingRoundFlow = true
                })
            .environmentObject(trajectoryModel)
        } else if isLoadingSetupCourse {
            VStack(spacing: 14) {
                ProgressView()
                Text("Preparing round")
                    .font(.headline)
                    .foregroundStyle(PureLineStyle.ink)
                Text("Loading the selected course and tee…")
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PureLineStyle.canvas)
        } else if let setupCourseError {
            ContentUnavailableView {
                Label("Course unavailable", systemImage: "map")
            } description: {
                Text(setupCourseError)
            } actions: {
                Button("Try again") {
                    if let setupReference { prepareRoundSetup(for: setupReference) }
                }
                Button("Back to course selection") {
                    self.setupReference = nil
                    self.setupCourseError = nil
                    isStartingRoundFlow = true
                }
            }
        } else if let selection {
            CourseMapView(reference: selection, requestStartRound: $requestStartRound,
                          resumedRound: resumedRound, onHome: onHome) {
                    self.selection = nil
                    resumedRound = nil
                }
        } else {
            CourseSelectionView(showsRoundInProgress: isStartingRoundFlow || requestStartRound,
                isStartRoundFlow: isStartingRoundFlow || requestStartRound, onStartRound: { reference in
                isStartingRoundFlow = true
                requestStartRound = true
                if roundStore.active == nil { prepareRoundSetup(for: reference) }
            }, onResumeRound: { round in
                isStartingRoundFlow = false
                requestStartRound = false
                resumedRound = round
                selection = round.reference
            }, onHome: onHome, onStartCourse: {
                isStartingRoundFlow = false
                selection = $0
            })
        }
    }

    private func prepareRoundSetup(for reference: CourseReference) {
        setupReference = reference
        setupCourseError = nil
        isLoadingSetupCourse = true
        Task { @MainActor in
            let courseStore = CourseStore(reference: reference)
            await courseStore.load()
            isLoadingSetupCourse = false
            if let course = courseStore.course {
                setupCourse = course
            } else {
                setupCourseError = courseStore.errorMessage ?? L("The selected course could not be loaded.")
            }
        }
    }
}

// The authenticated shell requires a login-owned PinTheoryAccountData instance.
// It deliberately has no unauthenticated/default initializer or disk-backed preview.
