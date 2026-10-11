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
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Button {
                            destination = nil
                        } label: {
                            Label("Home", systemImage: "chevron.left")
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("return-home-button")
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .foregroundStyle(PureLineStyle.accent)
                    .background(PureLineStyle.canvas)
                }
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
            CourseMapFlowView(requestStartRound: $requestStartRound)
        case .handicap:
            HCPProjectionEntryView()
        case .practice:
            PracticeView(destination: $practiceDestination, trajectoryModel: trajectoryModel)
        case .statistics:
            RoundStatisticsView()
        case .bag:
            InTheBagView(trajectoryModel: trajectoryModel)
        }
    }
}

private struct CourseMapFlowView: View {
    @State private var selection: CourseReference?
    @State private var resumedRound: PlayedRound?
    @Binding var requestStartRound: Bool
    @Environment(PlayedRoundStore.self) private var roundStore

    var body: some View {
        if let selection {
            CourseMapView(reference: selection, requestStartRound: $requestStartRound, resumedRound: resumedRound) {
                self.selection = nil
                resumedRound = nil
            }
        } else {
            CourseSelectionView(showsRoundInProgress: requestStartRound, onStartRound: { reference in
                requestStartRound = true
                if roundStore.active == nil { selection = reference }
            }, onResumeRound: { round in
                requestStartRound = false; resumedRound = round; selection = round.reference
            }, onStartCourse: { selection = $0 })
        }
    }
}

#Preview {
    ContentView()
}
