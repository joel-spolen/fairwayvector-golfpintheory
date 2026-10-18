import SwiftData
import SwiftUI

struct ContentView: View {
    private enum Destination: String, Identifiable {
        case course
        case handicap
        case practice
        case statistics
        case bag

        var id: String { rawValue }
    }

    @AppStorage("map.hasSeenSplash") private var hasSeenSplash = false
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .meters
    @AppStorage("wedgeMatrix.distanceUnit") private var wedgeDistanceUnit = WedgeDistanceUnit.yards.rawValue
    @State private var isShowingSplash = true
    @State private var destination: Destination?
    @State private var showingSettings = false
    @State private var practiceDestination: PracticeDestination = .trajectory
    @StateObject private var trajectoryModel = TrajectoryCalculatorViewModel()
    @State private var roundStore = PlayedRoundStore()
    @State private var requestStartRound = false

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
                onOpenSettings: { showingSettings = true }
            )

            if isShowingSplash {
                SplashView(isReturningUser: hasSeenSplash) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingSplash = false
                        hasSeenSplash = true
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background {
            KeyboardDismissOnTap()
        }
        .environment(\.colorScheme, .light)
        .overlay { SharedHandicapSync(trajectoryModel: trajectoryModel).allowsHitTesting(false) }
        .environmentObject(trajectoryModel)
        .environment(roundStore)
        .modelContainer(HCPProjectionEntryView.sharedModelContainer)
        .fullScreenCover(item: $destination, onDismiss: { requestStartRound = false }) { screen in
            feature(screen)
                .environmentObject(trajectoryModel)
                .environment(roundStore)
                .modelContainer(HCPProjectionEntryView.sharedModelContainer)
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showingSettings) {
            UnifiedSettingsView()
            .environmentObject(trajectoryModel)
            .modelContainer(HCPProjectionEntryView.sharedModelContainer)
            .preferredColorScheme(.light)
        }
        .onChange(of: distanceUnit, initial: true) { _, unit in
            wedgeDistanceUnit = unit == .meters ? WedgeDistanceUnit.meters.rawValue : WedgeDistanceUnit.yards.rawValue
            trajectoryModel.unitPreferences.globalDefault = unit == .meters ? .metric : .imperial
        }
        // Unlike an environment override, this also controls presented screens.
        .preferredColorScheme(.light)
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
            InTheBagView(trajectoryModel: trajectoryModel, onHome: { destination = nil })
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
                setupCourseError = courseStore.errorMessage ?? "The selected course could not be loaded."
            }
        }
    }
}

#Preview {
    ContentView()
}
