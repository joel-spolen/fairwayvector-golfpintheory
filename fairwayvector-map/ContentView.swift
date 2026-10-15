import SwiftUI

struct CourseMapView: View {
    let reference: CourseReference
    let onChangeCourse: () -> Void
    let onHome: () -> Void
    @EnvironmentObject private var trajectoryModel: TrajectoryCalculatorViewModel
    @Environment(PlayedRoundStore.self) private var roundStore
    @Binding private var requestStartRound: Bool
    private let resumesSnapshot: Bool
    @State private var roundModeEnabled: Bool
    @State private var showingRoundSetup = false
    @State private var showingRoundReview = false
    @State private var scoringHole: Int?
    @State private var roundPageIndex: Int
    @State private var pageDirection = 1
    @State private var roundError: String?
    @State private var isConfirmingRoundCancel = false
    @State private var transitionTargetPage: Int?
    @State private var pageProgress = 0.0
    @State private var reviewingRound: PlayedRound?
    @State private var pendingReviewHole: Int?

    @State private var store: CourseStore
    @State private var weatherStore = CourseWeatherStore()
    @State private var terrainStore = TerrainElevationStore()
    @State private var isShowingTerrainProfile = false
    @State private var isShowingCourseInfo = false
    @State private var terrainInspectionPoint: GeoPoint?
    @State private var mapHeading = 0.0
    @State private var locationManager = LocationManager()
    @State private var holeIndex = 0
    @State private var tapPoint: GeoPoint?
    @State private var isShowingFlagEditor = false
    @State private var adviceContentHeight: CGFloat = 150
    #if DEBUG
    @State private var simulatedGolfer: GeoPoint?
    @State private var simulationError: String?
    @State private var isShowingDevelopmentWedges = false
    @State private var isShowingDevelopmentProfile = false
    @AppStorage("wedgeMatrix.wedges") private var developmentStoredWedges = ""
    #endif
    @AppStorage("distanceUnit") private var unit: DistanceUnit = .meters
    @AppStorage("customFlagPositions") private var customFlagPositions = ""

    init(reference: CourseReference, requestStartRound: Binding<Bool> = .constant(false),
         resumedRound: PlayedRound? = nil, onHome: @escaping () -> Void = {},
         onChangeCourse: @escaping () -> Void = {}) {
        self.reference = reference
        self.onChangeCourse = onChangeCourse
        self.onHome = onHome
        _requestStartRound = requestStartRound
        resumesSnapshot = resumedRound != nil
        _roundModeEnabled = State(initialValue: resumedRound != nil)
        _holeIndex = State(initialValue: resumedRound?.currentHole ?? 0)
        _roundPageIndex = State(initialValue: (resumedRound?.currentHole ?? 0) * 2)
        _store = State(initialValue: CourseStore(reference: reference, initialCourse: resumedRound?.course))
    }

    private var activeRound: PlayedRound? {
        guard roundModeEnabled, let round = roundStore.active, round.reference == reference else { return nil }
        return round
    }
    private var courseDisplayOptions: RoundDisplayOptions {
        activeRound?.displayOptions ?? .courseViewDefault
    }
    private var isShowingScoreEntry: Bool { activeRound != nil && roundPageIndex.isMultiple(of: 2) == false }

    private func horizontalPageOffset(width: CGFloat) -> CGFloat {
        guard transitionTargetPage != nil else { return 0 }
        if pageDirection > 0 { return -width * pageProgress }
        return -width * (1 - pageProgress)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let width = geometry.size.width
                HStack(spacing: 0) {
                    if let targetPage = transitionTargetPage, pageDirection < 0 {
                        roundPage(targetPage)
                            .frame(width: width, height: geometry.size.height)
                            .allowsHitTesting(pageProgress > 0.5)
                        roundPage(roundPageIndex)
                            .frame(width: width, height: geometry.size.height)
                            .allowsHitTesting(pageProgress <= 0.5)
                    } else {
                        roundPage(roundPageIndex)
                            .frame(width: width, height: geometry.size.height)
                            .allowsHitTesting(pageProgress <= 0.5)
                        if let targetPage = transitionTargetPage {
                            roundPage(targetPage)
                                .frame(width: width, height: geometry.size.height)
                                .allowsHitTesting(pageProgress > 0.5)
                        }
                    }
                }
                .offset(x: horizontalPageOffset(width: width))
                .frame(width: width, height: geometry.size.height, alignment: .leading)
                .clipped()
                .allowsHitTesting(transitionTargetPage == nil)
            }
                .background(PureLineStyle.canvas)
                .navigationTitle(isShowingScoreEntry ? "Hole \(scoringHole ?? 1) scorecard" : store.reference.courseName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .toolbar {
                    if !isShowingScoreEntry {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Change course", systemImage: "chevron.left", action: onChangeCourse)
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("Change course, club, or tee")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                roundMenu
                                Button("Course & tee information", systemImage: "info.circle") { isShowingCourseInfo = true }
                                Button("Terrain profile", systemImage: "mountain.2") { isShowingTerrainProfile = true }
                                    .disabled(store.course == nil)
                                Button("Move flag", systemImage: "flag") { isShowingFlagEditor = true }
                                    .disabled(store.course == nil)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body.weight(.semibold))
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Course options, scorecard and tools")
                        }
                    }
                }
        }
        .tint(PureLineStyle.accent)
        .task {
            locationManager.start()
            if !resumesSnapshot { await store.load() }
            handleStartRequest()
        }
        .onChange(of: requestStartRound) { handleStartRequest() }
        .onChange(of: holeIndex) {
            clearSimulation()
            tapPoint = nil
            terrainStore.invalidateShot()
            if var round = activeRound, round.currentHole != holeIndex {
                round.currentHole = holeIndex
                do { try roundStore.updateDraft(round) } catch { roundError = error.localizedDescription }
            }
        }
        .onDisappear { clearSimulation(); terrainStore.deactivate() }
        .fullScreenCover(isPresented: $showingRoundSetup) {
            if let course = store.course {
                RoundSetupView(selectedCourseReference: reference, course: course,
                    onStarted: {
                        roundModeEnabled = true
                        holeIndex = 0
                        roundPageIndex = 0
                    },
                    onCancel: { onChangeCourse() })
            }
        }
        .sheet(isPresented: $showingRoundReview, onDismiss: {
            if roundStore.active == nil { roundModeEnabled = false }
            if let number = pendingReviewHole, activeRound != nil {
                pendingReviewHole = nil
                scoringHole = number
                if let index = activeRound?.holes.firstIndex(where: { $0.number == number }) {
                    navigateRoundPage(to: index * 2 + 1)
                }
            }
        }) {
            // Keep presentation stable when Save moves the draft to saved history.
            if let round = reviewingRound {
                RoundReviewView(initialRound: round, onEditHole: { number in
                    // Switch the map after review dismisses; do not stack scoring sheets.
                    pendingReviewHole = number
                })
            }
        }
        .alert("Round could not be stored", isPresented: Binding(get: { roundError != nil }, set: { if !$0 { roundError = nil } })) {
            Button("Retry draft save") {
                do { try roundStore.retryDraft(); roundError = nil } catch { roundError = error.localizedDescription }
            }
            Button("Keep draft", role: .cancel) { roundError = nil }
        } message: { Text(roundError ?? "") }
        .confirmationDialog("Cancel this round?", isPresented: $isConfirmingRoundCancel, titleVisibility: .visible) {
            Button("Cancel round", role: .destructive) {
                do {
                    try roundStore.discardDraft()
                    roundModeEnabled = false
                    onHome()
                } catch {
                    roundError = error.localizedDescription
                }
            }
        } message: {
            Text("This discards the unsaved round and its scores. Saved scorecards are not affected.")
        }
        .sheet(isPresented: $isShowingTerrainProfile, onDismiss: { terrainInspectionPoint = nil }) {
            if let holes = store.course?.holes, !holes.isEmpty {
                let hole = holes[min(holeIndex, holes.count - 1)]
                HoleElevationProfileView(
                    store: terrainStore, holeNumber: hole.number, unit: unit,
                    usesGPS: terrainStore.usesGPS,
                    inspectionPoint: $terrainInspectionPoint
                )
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .sheet(isPresented: $isShowingFlagEditor) {
            if let holes = store.course?.holes, !holes.isEmpty {
                let hole = holes[min(holeIndex, holes.count - 1)]
                if let flag = flagPosition(for: hole) {
                    FlagPlacementView(hole: hole, initialFlag: flag) { movedFlag in
                        saveFlagPosition(movedFlag, for: hole)
                        isShowingFlagEditor = false
                    }
                    .presentationDetents([.large])
                }
            }
        }
        .sheet(isPresented: $isShowingCourseInfo) { courseInformation }
        #if DEBUG
        .sheet(isPresented: $isShowingDevelopmentWedges) {
            NavigationStack {
                WedgeMatrixView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingDevelopmentWedges = false } } }
            }
        }
        .sheet(isPresented: $isShowingDevelopmentProfile) {
            if trajectoryModel.playerProfileStore.needsSetup {
                TrajectoryProfileSetupWizardView(profileStore: trajectoryModel.playerProfileStore,
                    unitPreferences: trajectoryModel.unitPreferences, onClose: { isShowingDevelopmentProfile = false })
            } else {
                NavigationStack {
                    TrajectoryProfileSettingsView(profileStore: trajectoryModel.playerProfileStore,
                        unitPreferences: trajectoryModel.unitPreferences, settingsViewModel: trajectoryModel)
                        .navigationTitle("Clubs & launch profile")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingDevelopmentProfile = false } } }
                }
            }
        }
        #endif
    }

    private func openRoundReview() {
        reviewingRound = activeRound
        showingRoundReview = reviewingRound != nil
    }

    private func showScoreEntry(for number: Int) {
        guard let index = activeRound?.holes.firstIndex(where: { $0.number == number }) else { return }
        scoringHole = number
        navigateRoundPage(to: index * 2 + 1)
    }

    private func showCourseHole(_ number: Int) {
        guard let index = activeRound?.holes.firstIndex(where: { $0.number == number }) else { return }
        scoringHole = nil
        navigateRoundPage(to: index * 2)
    }

    private func navigateRoundPage(to requestedIndex: Int) {
        guard let round = activeRound else { return }
        guard transitionTargetPage == nil else { return }
        let lastPage = max(0, round.holes.count * 2 - 1)
        let destination = min(max(requestedIndex, 0), lastPage)
        guard destination != roundPageIndex else { return }
        pageDirection = destination > roundPageIndex ? 1 : -1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transitionTargetPage = destination
            pageProgress = 0
        }
        withAnimation(.easeInOut(duration: 0.32), completionCriteria: .removed) {
            pageProgress = 1
        } completion: {
            var completion = Transaction()
            completion.disablesAnimations = true
            withTransaction(completion) {
                roundPageIndex = destination
                holeIndex = destination / 2
                scoringHole = destination.isMultiple(of: 2) ? nil : round.holes[destination / 2].number
                transitionTargetPage = nil
                pageProgress = 0
            }
        }
    }

    @ViewBuilder
    private func roundPage(_ pageIndex: Int) -> some View {
        if let round = activeRound, pageIndex.isMultiple(of: 2) == false,
           round.holes.indices.contains(pageIndex / 2) {
            let number = round.holes[pageIndex / 2].number
            RoundHoleEntryView(round: round, holeNumber: number, onSave: { savedHoleNumber, entries in
                guard var updated = activeRound else { throw RoundStorageError.incomplete }
                for (playerID, score) in entries {
                    updated.setScore(score, player: playerID, hole: savedHoleNumber)
                }
                try roundStore.updateDraft(updated)
            }, onNavigateHole: showCourseHole)
        } else {
            content(for: activeRound == nil ? holeIndex : pageIndex / 2)
        }
    }

    private func handleStartRequest() {
        guard requestStartRound, store.course != nil else { return }
        requestStartRound = false
        if let draft = roundStore.active {
            roundError = "A draft already exists for \(draft.reference.courseName). Return to Choose Course and resume it or discard it before starting another."
        } else { showingRoundSetup = true }
    }

    private var roundMenu: some View {
        Menu {
            if activeRound != nil {
                Button("Score current hole", systemImage: "square.and.pencil") {
                    if let number = activeRound?.holes[holeIndex].number { showScoreEntry(for: number) }
                }
                Button("Review / finish round", systemImage: "list.bullet.rectangle") { openRoundReview() }
                Button("Pause round & choose course", systemImage: "pause.circle", action: onChangeCourse)
            } else {
                Button("Start round", systemImage: "flag.checkered") { showingRoundSetup = true }
                    .disabled(store.course == nil || store.isLoading || roundStore.active != nil)
            }
            Button(store.reference.golfAPICourseID == nil ? "Refresh course" : "Check for course updates", systemImage: "arrow.clockwise") {
                Task { await store.refresh() }
            }.disabled(store.isLoading || activeRound != nil)
        } label: {
            Label(activeRound == nil ? "Round" : "Scorecard", systemImage: activeRound == nil ? "flag.checkered" : "list.bullet.rectangle")
                .font(.caption.weight(.semibold)).frame(minHeight: 44)
        }.accessibilityIdentifier("course-round-menu")
    }

    @ViewBuilder
    private func content(for requestedHoleIndex: Int) -> some View {
        if let holes = store.course?.holes, !holes.isEmpty {
            let pageHoleIndex = min(max(requestedHoleIndex, 0), holes.count - 1)
            let hole = holes[pageHoleIndex]
            let origin = distanceOrigin(for: hole)
            let holeRequest = terrainRequest(for: hole, origin: nil, target: nil)
            GeometryReader { geometry in
                HoleMapView(
                    hole: hole,
                    flag: flagPosition(for: hole),
                    origin: origin?.point,
                    usesGPS: origin?.usesGPS == true,
                    tapPoint: $tapPoint,
                    onDoubleTapGreen: { point in saveFlagPosition(point, for: hole) },
                    onHeadingChange: { mapHeading = $0 },
                    terrainInspectionPoint: terrainInspectionPoint,
                    onTargetInteractionBegan: { terrainStore.beginTargetInteraction() },
                    onTargetInteractionCancelled: { terrainStore.cancelTargetInteraction() },
                    onTargetCommitted: { point in
                        terrainInspectionPoint = nil
                        commitSelectedShot(for: hole, target: point)
                    },
                    simulatedUserLocation: origin?.isSimulated == true ? origin?.point : nil
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .topTrailing) {
                    roundActionsMenu
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                }
                .overlay(alignment: .leading) {
                    ScrollView(.vertical) {
                        VStack(spacing: 9) {
                            Button {
                                isShowingFlagEditor = true
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: "flag")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.white)
                                    Text("Pin position")
                                        .font(.caption2.weight(.medium))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.white)
                                }
                                .padding(6)
                                .frame(width: 78)
                                .frame(minHeight: 64)
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .background(PureLineStyle.accent, in: RoundedRectangle(cornerRadius: 14))
                            .disabled(hole.greenCenter == nil)
                            .accessibilityHint("Opens an enlarged green where you can tap to place the flag")

                            distanceSidebar(hole: hole, origin: origin, flag: flagPosition(for: hole))

                            if courseDisplayOptions.showWind, let location = courseWeatherLocation {
                                CourseWeatherCard(location: location, store: weatherStore,
                                                  mapHeading: mapHeading, compact: true)
                            }
                            if courseDisplayOptions.showElevation { terrainPanel }
                            if courseDisplayOptions.showClubSelection {
                                CourseShotRecommendationView(terrainStore: terrainStore, weatherStore: weatherStore,
                                    weatherLocation: courseWeatherLocation, selectedTarget: tapPoint,
                                    unit: unit, usesWind: courseDisplayOptions.showWind,
                                    usesElevation: courseDisplayOptions.showElevation,
                                    model: trajectoryModel, compact: true,
                                    allowsScoringMode: courseDisplayOptions.scoringMode)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                    }
                    .frame(width: 94, height: geometry.size.height)
                    .scrollIndicators(.hidden)
                    .padding(.leading, 6)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomHoleMenu(hole: hole, holeCount: holes.count, pageHoleIndex: pageHoleIndex)
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                            .fill(PureLineStyle.canvas)
                            .ignoresSafeArea(edges: .bottom)
                            .shadow(color: .black.opacity(0.06), radius: 16, y: -4)
                    }
            }
            .task(id: holeRequest) {
                // Opening geometry/tee/hole/saved flag reads terrain cache ONLY.
                tapPoint = nil
                terrainInspectionPoint = nil
                clearSimulation()
                terrainStore.open(terrainRequest(for: hole,
                    origin: distanceOrigin(for: hole), target: nil))
            }
            .task(id: courseWeatherLocation) {
                guard let location = courseWeatherLocation else { return }
                await weatherStore.load(for: location)
            }
        } else if store.isLoading || store.errorMessage == nil {
            ProgressView("Loading course…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Course unavailable", systemImage: "map")
            } description: {
                Text(store.errorMessage ?? "")
            } actions: {
                Button("Try again") { Task { await store.refresh() } }
                    .padding(.horizontal, 18)
                    .buttonStyle(PureLinePrimaryButtonStyle(fillsWidth: false, minimumHeight: 44))
            }
        }
    }

    private func distanceOrigin(for hole: Hole) -> DistanceOrigin? {
        #if DEBUG
        if let simulatedGolfer { return DistanceOrigin(point: simulatedGolfer, source: .simulated) }
        #endif
        return DistanceOrigin.resolve(location: locationManager.location, hole: hole)
    }

    private func clearSimulation() {
        #if DEBUG
        simulatedGolfer = nil
        simulationError = nil
        #endif
    }

    private func commitSelectedShot(for hole: Hole, target: GeoPoint?) {
        let origin = distanceOrigin(for: hole)
        // Simulated target release also remains cache-only in live GPXZ mode.
        terrainStore.commitShot(terrainRequest(for: hole, origin: origin, target: target),
            allowPaid: origin?.isSimulated != true || DevelopmentAPIConfiguration.current.gpxz == .mock)
    }

    #if DEBUG
    private var developmentScoringPlan: ScoringShotPlan {
        let wedges = developmentStoredWedges.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([Wedge].self, from: $0) } ?? []
        return ScoringShotPlan.make(profile: trajectoryModel.playerProfileStore.profile, wedges: wedges)
    }

    private func simulationIssue(hole: Hole, plan: ScoringShotPlan) -> String? {
        guard trajectoryModel.playerProfileStore.profile.isSetupComplete else {
            return "Set up Practice / Profile, then enter a personal Mid/Stock Full wedge carry."
        }
        guard plan.maxFullCarryM != nil else {
            return "Enter a personal Mid/Stock Full carry in Wedge calibration & matrix, or calibrate a Practice wedge. No stock range is assumed. \(plan.guidance)"
        }
        guard let target = tapPoint ?? flagPosition(for: hole), let tee = hole.tee,
              DevelopmentScoringPosition.distanceRange(plan: plan, target: target, tee: tee) != nil else {
            return "Choose a valid target away from the tee; the personal range must allow at least 0.2 m of simulated distance."
        }
        return nil
    }

    private var developmentHole: Hole? {
        guard let holes = store.course?.holes, !holes.isEmpty else { return nil }
        return holes[min(holeIndex, holes.count - 1)]
    }

    private var developmentToolsMenu: some View {
        Menu {
            Button("Random scoring position", systemImage: "dice") {
                if let hole = developmentHole { randomScoringPosition(hole: hole) }
            }
            .disabled(developmentHole == nil || store.isLoading || terrainStore.isHoleLoading || terrainStore.isShotLoading || terrainStore.shotPending
                || developmentHole.map { simulationIssue(hole: $0, plan: developmentScoringPlan) != nil } == true)
            .accessibilityIdentifier("random-scoring-position")
            Button("Use device GPS", systemImage: "location") {
                guard let hole = developmentHole else { return }
                clearSimulation()
                terrainInspectionPoint = nil
                terrainStore.commitShot(terrainRequest(for: hole, origin: distanceOrigin(for: hole), target: tapPoint), allowPaid: false)
            }
            .disabled(simulatedGolfer == nil || terrainStore.shotPending || developmentHole == nil)
            .accessibilityIdentifier("use-device-gps")
            Section("Personal calibration") {
                Button("Configure wedge calibration & matrix", systemImage: "slider.horizontal.3") { isShowingDevelopmentWedges = true }
                Button("Configure Practice / Profile", systemImage: "person.crop.circle") { isShowingDevelopmentProfile = true }
                Button("Development guidance", systemImage: "info.circle") { isShowingCourseInfo = true }
            }
        } label: {
            VStack(spacing: 0) {
                Image(systemName: "dice").font(.body)
                Text("DEV").font(.system(size: 8, weight: .bold))
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Development tools")
        .accessibilityHint("Random scoring position, reset to device GPS, and personal wedge calibration")
        .accessibilityIdentifier("development-tools")
    }

    private func randomScoringPosition(hole: Hole) {
        let plan = developmentScoringPlan
        guard simulationIssue(hole: hole, plan: plan) == nil,
              let target = tapPoint ?? flagPosition(for: hole), let tee = hole.tee,
              let point = DevelopmentScoringPosition.make(plan: plan, target: target, tee: tee,
                fraction: Double.random(in: 0...1), jitterDeg: Double.random(in: -20...20)) else {
            simulationError = "No valid scoring position could be generated. Review your target and personal wedge calibration."
            isShowingCourseInfo = true
            return
        }
        simulationError = nil
        simulatedGolfer = point
        tapPoint = target
        terrainInspectionPoint = nil
        commitSelectedShot(for: hole, target: target)
    }
    #endif

    private var courseWeatherLocation: GeoPoint? {
        if let location = store.reference.location { return location }
        var points: [GeoPoint] = []
        for hole in store.course?.holes ?? [] {
            points.append(contentsOf: hole.path)
            points.append(contentsOf: hole.green)
            for polygon in hole.fairways { points.append(contentsOf: polygon) }
            for polygon in hole.roughs { points.append(contentsOf: polygon) }
            for polygon in hole.tees { points.append(contentsOf: polygon) }
        }
        guard !points.isEmpty else { return nil }
        let count = Double(points.count)
        let latitudeTotal = points.reduce(0.0) { total, point in total + point.lat }
        let longitudeTotal = points.reduce(0.0) { total, point in total + point.lon }
        return GeoPoint(
            lat: latitudeTotal / count,
            lon: longitudeTotal / count
        )
    }

    private func terrainRequest(for hole: Hole, origin: DistanceOrigin?, target: GeoPoint?) -> TerrainRequest {
        let flag = flagPosition(for: hole)
        var path = hole.path
        if let flag {
            if path.count >= 2 { path[path.count - 1] = flag }
            else if let tee = hole.tee { path = [tee, flag] }
        }
        return TerrainRequest(
            courseID: store.terrainCourseID ?? "",
            holeNumber: hole.number, path: path, flag: flag,
            origin: origin?.point, target: target ?? flag,
            usesPointOnlyGeometry: hole.usesPointOnlyGeometry || path.count <= 2,
            usesGPS: origin?.usesGPS == true,
            isSimulatedOrigin: origin?.isSimulated == true
        )
    }

    private var terrainPanel: some View {
        Button { isShowingTerrainProfile = true } label: {
            VStack(spacing: 3) {
                Image(systemName: "mountain.2")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PureLineStyle.accent)
                Text(terrainSummary
                    .replacingOccurrences(of: "To target · ", with: "")
                    .replacingOccurrences(of: "Tee → flag · ", with: ""))
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PureLineStyle.ink)
                if terrainStore.isShotLoading || terrainStore.isHoleLoading { ProgressView().controlSize(.mini) }
            }
            .padding(6)
            .frame(width: 78)
            .frame(minHeight: 64)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(PureLineStyle.ink)
        .background(PureLineStyle.canvas.opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("terrain-profile-button")
        .accessibilityLabel("Terrain details, \(terrainSummary)")
        .accessibilityHint("Opens the full chart, source, budget, errors and confirmed retry")
    }

    private var terrainSummary: String {
        if terrainStore.shotPending { return "Terrain · release target" }
        // Summary follows the committed shot, not the mode selected for chart inspection.
        if let request = terrainStore.committedRequest {
            if let profile = terrainStore.snapshot.shotProfile,
               let first = profile.samples.first, let last = profile.samples.last,
               let origin = request.origin, let target = request.target,
               TerrainGeometry.length(first.point, origin) <= TerrainGeometry.tolerance,
               TerrainGeometry.length(last.point, target) <= TerrainGeometry.tolerance,
               let delta = profile.elevationChangeMeters, delta.isFinite {
                return "To target · \(terrainDeltaText(delta))"
            }
            return terrainStore.isShotLoading ? "Loading terrain…" : "Terrain unavailable"
        }
        if let delta = terrainStore.snapshot.holeProfile?.elevationChangeMeters {
            return "Tee → flag · \(terrainDeltaText(delta))"
        }
        return terrainStore.isHoleLoading ? "Loading terrain…" : "Terrain unavailable"
    }

    private func terrainDeltaText(_ meters: Double) -> String {
        let value = unit == .meters ? meters : meters / 0.9144
        return String(format: "%+.1f %@", value, unit.symbol)
    }

    private func bottomHoleMenu(hole: Hole, holeCount: Int, pageHoleIndex: Int) -> some View {
        VStack(spacing: 4) {
        HStack(alignment: .center, spacing: 10) {
            holeNavigationButton(isPrevious: true, count: holeCount, pageHoleIndex: pageHoleIndex)
            Button { isShowingCourseInfo = true } label: {
                Text("Hole \(hole.number) · Par \(hole.par.map(String.init) ?? "–") · HCP \(hole.handicapIndex.map(String.init) ?? "–") · \(hole.length > 0 ? unit.format(hole.length) : "–")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PureLineStyle.ink)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens course, tee and hole information")
            .frame(maxWidth: .infinity)
            holeNavigationButton(isPrevious: false, count: holeCount, pageHoleIndex: pageHoleIndex)
        }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(PureLineStyle.canvas)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var courseInformation: some View {
        NavigationStack {
            Form {
                Section("Course & tee") {
                    LabeledContent("Club", value: store.reference.clubName)
                    LabeledContent("Course", value: store.reference.courseName)
                    LabeledContent("Location", value: store.reference.city.isEmpty ? store.reference.region : store.reference.city)
                    LabeledContent("Tee", value: "\(store.reference.teeName) · \(store.reference.teeSex.capitalized)")
                    LabeledContent("Holes / par", value: "\(store.reference.holeCount) / \(store.reference.totalPar)")
                    LabeledContent("Rating / slope", value: String(format: "%.1f / %d", store.reference.courseRating, store.reference.slopeRating))
                }
            }
            .navigationTitle("Course information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingCourseInfo = false } } }
        }
        .tint(FairwayVectorColors.navy)
    }

    private var roundActionsMenu: some View {
        Menu {
            Button("Home", systemImage: "house.fill", action: onHome)
            if activeRound != nil {
                Button("Scorecard", systemImage: "list.bullet.rectangle") { openRoundReview() }
                Button("Cancel round", systemImage: "xmark.circle", role: .destructive) {
                    isConfirmingRoundCancel = true
                }
            } else {
                Button("Start round", systemImage: "flag.checkered") { showingRoundSetup = true }
                    .disabled(store.course == nil || store.isLoading || roundStore.active != nil)
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.medium))
                .foregroundStyle(PureLineStyle.accent)
                .frame(width: 44, height: 44)
                .background(PureLineStyle.canvas.opacity(0.94), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Round actions")
        .accessibilityIdentifier("course-round-actions-menu")
    }

    private func distanceSidebar(hole: Hole, origin: DistanceOrigin?, flag: GeoPoint?) -> some View {
        VStack(spacing: 7) {
            sidebarDistance("FRONT", from: origin?.point, to: hole.greenFront ?? hole.greenCenter)
            sidebarDistance("TARGET", from: origin?.point, to: tapPoint, highlighted: true)
            sidebarDistance("BACK", from: origin?.point, to: hole.greenBack ?? hole.greenCenter)
            sidebarDistance("CENTER", from: origin?.point, to: hole.greenCenter)
            sidebarDistance("TARGET → FLAG", from: tapPoint, to: tapPoint == nil ? nil : flag)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity)
        .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shot distances")
    }

    private func sidebarDistance(_ title: String, from start: GeoPoint?, to end: GeoPoint?, highlighted: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(PureLineStyle.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(distanceValue(from: start, to: end))
                    .font(.system(size: highlighted ? 17 : 14, weight: highlighted ? .semibold : .medium).monospacedDigit())
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .foregroundStyle(highlighted ? PureLineStyle.accent : PureLineStyle.ink)
                Text(unit.symbol)
                    .font(.system(size: 8))
                    .foregroundStyle(PureLineStyle.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(distanceAccessibilityValue(from: start, to: end))")
    }

    private func distanceValue(from start: GeoPoint?, to end: GeoPoint?) -> String {
        guard let start, let end else { return "N/A" }
        return "\(unit.value(GolfGeometry.distance(start, end)))"
    }

    private func distanceAccessibilityValue(from start: GeoPoint?, to end: GeoPoint?) -> String {
        guard let start, let end else { return "unavailable" }
        return unit.format(GolfGeometry.distance(start, end))
    }

    private func flagPosition(for hole: Hole) -> GeoPoint? {
        if let data = customFlagPositions.data(using: .utf8),
           let positions = try? JSONDecoder().decode([String: GeoPoint].self, from: data),
           let custom = positions["\(store.reference.cacheKey)-\(hole.number)"] {
            return custom
        }
        return hole.flag ?? hole.greenCenter
    }

    private func saveFlagPosition(_ position: GeoPoint, for hole: Hole) {
        let key = "\(store.reference.cacheKey)-\(hole.number)"
        let data = customFlagPositions.data(using: .utf8) ?? Data()
        var positions = (try? JSONDecoder().decode([String: GeoPoint].self, from: data)) ?? [:]
        positions[key] = position
        guard let encoded = try? JSONEncoder().encode(positions),
              let value = String(data: encoded, encoding: .utf8) else { return }
        customFlagPositions = value
    }

    private func holeSummary(_ hole: Hole) -> some View {
        VStack(spacing: 5) {
            Text("HOLE \(hole.number)")
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(FairwayVectorColors.navy)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                summaryValue("PAR", hole.par.map(String.init) ?? "–")
                summaryValue("HCP", hole.handicapIndex.map(String.init) ?? "–")
                summaryValue("LENGTH", hole.length > 0 ? unit.format(hole.length) : "–")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .multilineTextAlignment(.center)
    }

    private func summaryValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(FairwayVectorColors.slate)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(FairwayVectorColors.charcoal)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func holeNavigationButton(isPrevious: Bool, count: Int, pageHoleIndex: Int? = nil) -> some View {
        let currentHoleIndex = pageHoleIndex ?? holeIndex
        let unavailable: Bool
        if activeRound != nil {
            unavailable = isPrevious ? roundPageIndex == 0 : roundPageIndex >= count * 2 - 1
        } else {
            unavailable = isPrevious ? currentHoleIndex == 0 : currentHoleIndex >= count - 1
        }
        return Button {
            if activeRound != nil {
                navigateRoundPage(to: roundPageIndex + (isPrevious ? -1 : 1))
            } else {
                holeIndex = currentHoleIndex + (isPrevious ? -1 : 1)
            }
        } label: {
            Image(systemName: isPrevious ? "chevron.left" : "chevron.right")
                .font(.body.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
                .background(PureLineStyle.surface, in: Circle())
        }
            .buttonStyle(.plain)
            .foregroundStyle(unavailable ? PureLineStyle.muted.opacity(0.4) : PureLineStyle.accent)
        .disabled(unavailable)
        .accessibilityLabel(isPrevious ? "Previous hole" : activeRound == nil ? "Next hole" : "Enter score for this hole")
    }
}

private struct MapAdviceHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 150
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

#Preview {
    CourseMapView(reference: .hills)
        .environmentObject(TrajectoryCalculatorViewModel())
        .environment(PlayedRoundStore())
}
