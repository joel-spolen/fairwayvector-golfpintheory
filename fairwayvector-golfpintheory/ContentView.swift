import SwiftUI
import UIKit

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
    @State private var scorecardRound: PlayedRound?
    @State private var finishingRound: PlayedRound?
    @State private var scoringHole: Int?
    @State private var roundPageIndex: Int
    @State private var pageDirection = 1
    @State private var roundError: String?
    @State private var isConfirmingRoundCancel = false
    @State private var transitionTargetPage: Int?
    @State private var pageProgress = 0.0
    @State private var pendingReviewHole: Int?
    @State private var pendingCourseHole: Int?

    @State private var store: CourseStore
    @State private var weatherStore = CourseWeatherStore()
    @State private var terrainStore = TerrainElevationStore()
    @State private var isShowingTerrainProfile = false
    @State private var isShowingCourseInfo = false
    @State private var terrainInspection = TerrainInspection()
    @State private var mapHeading = 0.0
    @State private var locationManager = LocationManager()
    @State private var holeIndex = 0
    @State private var tapPoint: GeoPoint?
    @State private var isShowingFlagEditor = false
    @State private var showsGreenSlope = false
    @State private var greenSlopes: [Int: GreenSlopeMap] = [:]
    @State private var greenSlopeUnavailable: Set<Int> = []
    @State private var showingPaywall = false
    #if DEBUG
    @State private var simulatedGolfer: GeoPoint?
    @State private var isShowingDevelopmentWedges = false
    @State private var isShowingDevelopmentProfile = false
    #endif
    @AppStorage("distanceUnit", store: .standard) private var unit: DistanceUnit = .meters
    @AppStorage("customFlagPositions") private var customFlagPositions = ""
    @ScaledMetric(relativeTo: .body) private var sidebarWidth = 94.0

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
        (activeRound?.displayOptions ?? .courseViewDefault).limited(isPro: ProStore.shared.isPro)
    }
    private var isShowingScoreEntry: Bool { activeRound != nil && roundPageIndex.isMultiple(of: 2) == false }

    private var visibleRoundPages: [Int] {
        // Keep the incoming page's identity when it becomes the current page.
        // Replacing transition-only branches would recreate its MapKit view.
        if let target = transitionTargetPage {
            return [roundPageIndex, target].sorted()
        }
        return [roundPageIndex]
    }

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
                    ForEach(visibleRoundPages, id: \.self) { page in
                        roundPage(page)
                            .frame(width: width, height: geometry.size.height)
                    }
                }
                .offset(x: horizontalPageOffset(width: width))
                .frame(width: width, height: geometry.size.height, alignment: .leading)
                // Clips the sliding pages at the sides only, so the map can run up under the status bar.
                .clipShape(OpenTopRectangle())
                .allowsHitTesting(transitionTargetPage == nil)
            }
                .background(PureLineStyle.canvas)
                .navigationTitle(isShowingScoreEntry ? L("Hole %@ scorecard", "\(scoringHole ?? 1)") : store.reference.courseName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        }
        .tint(PureLineStyle.accent)
        .task {
            locationManager.start()
            // A resumed round already has its course, but its elevation still has to be read.
            if resumesSnapshot {
                store.preloadGreenOutlines()
                await store.loadTerrain()
            } else {
                await store.load()
            }
            handleStartRequest()
        }
        .onChange(of: requestStartRound) { handleStartRequest() }
        // Golfers glance at the map between shots; auto-lock would force an unlock each time.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onChange(of: holeIndex) {
            clearSimulation()
            tapPoint = nil
            terrainStore.invalidateShot()
            if var round = activeRound, round.currentHole != holeIndex {
                round.currentHole = holeIndex
                do { try roundStore.updateDraft(round) } catch { roundError = UserFacingError.message(error) }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            clearSimulation(); terrainStore.deactivate()
        }
        .fullScreenCover(item: $finishingRound, onDismiss: {
            if roundStore.active == nil {
                roundModeEnabled = false
                onHome()
            }
        }) { round in
            RoundReviewView(initialRound: round)
        }
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
        .fullScreenCover(item: $scorecardRound, onDismiss: {
            requestCoursePortraitOrientation()
            if roundStore.active == nil { roundModeEnabled = false }
            if let number = pendingCourseHole {
                pendingCourseHole = nil
                if activeRound != nil {
                    showCourseHole(number)
                } else if let index = store.course?.holes.firstIndex(where: { $0.number == number }) {
                    holeIndex = index
                    roundPageIndex = index * 2
                }
            }
            if let number = pendingReviewHole, activeRound != nil {
                pendingReviewHole = nil
                scoringHole = number
                if let index = activeRound?.holes.firstIndex(where: { $0.number == number }) {
                    navigateRoundPage(to: index * 2 + 1)
                }
            }
        }) { round in
            RoundScorecardView(round: round, onEditHole: { number in
                pendingReviewHole = number
                scorecardRound = nil
            }, onViewHole: { number in
                pendingCourseHole = number
                scorecardRound = nil
            })
        }
        .alert("Round could not be stored", isPresented: Binding(get: { roundError != nil }, set: { if !$0 { roundError = nil } })) {
            Button("Retry draft save") {
                do { try roundStore.retryDraft(); roundError = nil } catch { roundError = UserFacingError.message(error) }
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
                    roundError = UserFacingError.message(error)
                }
            }
        } message: {
            Text("This discards the unsaved round and its scores. Saved scorecards are not affected.")
        }
        .sheet(isPresented: $isShowingTerrainProfile, onDismiss: { terrainInspection.point = nil }) {
            if let holes = store.course?.holes, !holes.isEmpty {
                let hole = holes[min(holeIndex, holes.count - 1)]
                HoleElevationProfileView(
                    store: terrainStore, holeNumber: hole.number, unit: unit,
                    usesGPS: terrainStore.usesGPS,
                    inspection: terrainInspection
                )
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .sheet(isPresented: $isShowingFlagEditor) {
            if let holes = store.course?.holes, !holes.isEmpty {
                let hole = holes[min(holeIndex, holes.count - 1)]
                if let flag = flagPosition(for: hole) {
                    FlagPlacementView(hole: hole, initialFlag: flag,
                        greenSlope: greenSlopes[hole.number],
                        slopeUnavailable: greenSlopeUnavailable.contains(hole.number),
                        showsSlope: courseDisplayOptions.showGreenSlope && store.terrain != nil ? $showsGreenSlope : nil,
                        terrain: store.terrain
                    ) { movedFlag in
                        saveFlagPosition(movedFlag, for: hole)
                        isShowingFlagEditor = false
                    }
                    .presentationDetents([.large])
                }
            }
        }
        .sheet(isPresented: $isShowingCourseInfo) { courseInformation }
        .sheet(isPresented: $showingPaywall) { ProPaywallView() }
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
        scorecardRound = activeRound
    }

    private func requestCoursePortraitOrientation() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.windows.contains(where: \.isKeyWindow) }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
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
            }, onNavigateHole: showCourseHole, onFinish: {
                finishingRound = activeRound
            })
        } else {
            content(for: activeRound == nil ? holeIndex : pageIndex / 2)
        }
    }

    private func handleStartRequest() {
        guard requestStartRound, store.course != nil else { return }
        requestStartRound = false
        if let draft = roundStore.active {
            roundError = L("A draft already exists for %@. Return to Choose Course and resume it or discard it before starting another.", "\(draft.reference.courseName)")
        } else { showingRoundSetup = true }
    }

    @ViewBuilder
    private func content(for requestedHoleIndex: Int) -> some View {
        if !store.isLoadingTerrain, let holes = store.course?.holes, !holes.isEmpty {
            let pageHoleIndex = min(max(requestedHoleIndex, 0), holes.count - 1)
            let hole = holes[pageHoleIndex]
            let origin = distanceOrigin(for: hole)
            let holeRequest = terrainRequest(for: hole, origin: nil, target: nil)
            GeometryReader { geometry in
                // A background, so only the map runs up under the status bar; controls keep the safe area.
                Color.clear
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background {
                        HoleMapView(
                            hole: hole,
                            flag: flagPosition(for: hole),
                            origin: origin?.point,
                            usesGPS: origin?.usesGPS == true,
                            tapPoint: $tapPoint,
                            onDoubleTapGreen: { point in
                                if ProStore.shared.isPro { saveFlagPosition(point, for: hole) } else { showingPaywall = true }
                            },
                            onHeadingChange: { mapHeading = $0 },
                            terrainInspection: terrainInspection,
                            onTargetInteractionBegan: { terrainStore.beginTargetInteraction() },
                            onTargetInteractionCancelled: { terrainStore.cancelTargetInteraction() },
                            onTargetCommitted: { point in
                                terrainInspection.point = nil
                                commitSelectedShot(for: hole, target: point)
                            },
                            simulatedUserLocation: origin?.isSimulated == true ? origin?.point : nil
                        )
                        .ignoresSafeArea(.container, edges: .top)
                    }
                // Ready before the switch is used, so showing it is instant; redone when the outline arrives.
                .task(id: isShowingFlagEditor && courseDisplayOptions.showGreenSlope ? GreenSlopeMap.region(for: hole) : nil) {
                    guard isShowingFlagEditor, courseDisplayOptions.showGreenSlope, let terrain = store.terrain,
                          greenSlopes[hole.number]?.basis != GreenSlopeMap.region(for: hole) else { return }
                    if let map = GreenSlopeMap.make(terrain: terrain, hole: hole) {
                        greenSlopes[hole.number] = map
                        greenSlopeUnavailable.remove(hole.number)
                    } else {
                        greenSlopeUnavailable.insert(hole.number)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    roundActionsMenu
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                }
                .overlay(alignment: .leading) {
                    ScrollView(.vertical) {
                        VStack(spacing: 9) {
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
                            if !ProStore.shared.isPro {
                                Button { showingPaywall = true } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: "scope")
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(PureLineStyle.accent)
                                        Text("Club advice")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(PureLineStyle.ink)
                                        ProBadge()
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .contentShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .background(PureLineStyle.canvas.opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityHint("Club advice, wind and elevation need Golf PinTheory Pro")
                            }

                            Button {
                                if ProStore.shared.isPro { isShowingFlagEditor = true } else { showingPaywall = true }
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: "flag")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(PureLineStyle.accent)
                                    Text("Green & pin")
                                        .font(.caption2.weight(.medium))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(PureLineStyle.ink)
                                    if !ProStore.shared.isPro { ProBadge() }
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .background(PureLineStyle.canvas.opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
                            .disabled(hole.greenCenter == nil)
                            .accessibilityHint("Opens the green to move the pin or show its slope")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                    }
                    .frame(width: min(sidebarWidth, 136), height: geometry.size.height)
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
                tapPoint = nil
                terrainInspection.point = nil
                clearSimulation()
                terrainStore.setTerrain(store.terrain, unavailableMessage: store.terrainMessage)
                terrainStore.open(terrainRequest(for: hole,
                    origin: distanceOrigin(for: hole), target: nil))
            }
            .onChange(of: store.terrain == nil) {
                terrainStore.setTerrain(store.terrain, unavailableMessage: store.terrainMessage)
                terrainStore.open(terrainRequest(for: hole, origin: distanceOrigin(for: hole), target: nil))
            }
            .task(id: courseWeatherLocation) {
                guard let location = courseWeatherLocation else { return }
                await weatherStore.load(for: location)
            }
        } else if store.isLoading || store.isLoadingTerrain || store.errorMessage == nil {
            ProgressView(store.isLoadingTerrain ? L("Downloading course elevation…") : L("Loading course…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Course unavailable", systemImage: "map")
            } description: {
                Text(store.errorMessage ?? "")
            } actions: {
                Button("Try again") { Task { await store.refresh() } }
                    .buttonStyle(PureLinePrimaryButtonStyle(fillsWidth: false, minimumHeight: 44, horizontalPadding: 18))
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
        #endif
    }

    private func commitSelectedShot(for hole: Hole, target: GeoPoint?) {
        let origin = distanceOrigin(for: hole)
        // Simulated origins use the same downloaded course elevation as real ones.
        terrainStore.commitShot(terrainRequest(for: hole, origin: origin, target: target))
    }

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
                    .replacingOccurrences(of: L("To target · "), with: "")
                    .replacingOccurrences(of: L("Tee → flag · "), with: ""))
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PureLineStyle.ink)
                if terrainStore.isShotLoading || terrainStore.isHoleLoading { ProgressView().controlSize(.mini) }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(PureLineStyle.ink)
        .background(PureLineStyle.canvas.opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("terrain-profile-button")
        .accessibilityLabel("Terrain details, \(terrainSummary)")
        .accessibilityHint("Opens the elevation chart")
    }

    private var terrainSummary: String {
        if terrainStore.shotPending { return L("Terrain · release target") }
        // Summary follows the committed shot, not the mode selected for chart inspection.
        if let request = terrainStore.committedRequest {
            if let profile = terrainStore.snapshot.shotProfile,
               let first = profile.samples.first, let last = profile.samples.last,
               let origin = request.origin, let target = request.target,
               TerrainGeometry.length(first.point, origin) <= TerrainGeometry.tolerance,
               TerrainGeometry.length(last.point, target) <= TerrainGeometry.tolerance,
               let delta = profile.elevationChangeMeters, delta.isFinite {
                return L("To target · %@", "\(terrainDeltaText(delta))")
            }
            return terrainStore.isShotLoading ? L("Loading terrain…") : L("Terrain unavailable")
        }
        if let delta = terrainStore.snapshot.holeProfile?.elevationChangeMeters {
            return L("Tee → flag · %@", "\(terrainDeltaText(delta))")
        }
        return terrainStore.isHoleLoading ? L("Loading terrain…") : L("Terrain unavailable")
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
        .tint(PureLineStyle.accent)
    }

    private var roundActionsMenu: some View {
        Menu {
            Button("Home", systemImage: "house.fill", action: onHome)
            if activeRound != nil {
                Button("Scorecard", systemImage: "list.bullet.rectangle") { openRoundReview() }
                Button("Save and exit", systemImage: "square.and.arrow.down") {
                    finishingRound = activeRound
                }
                Button("Cancel round", systemImage: "xmark.circle", role: .destructive) {
                    isConfirmingRoundCancel = true
                }
            } else {
                Button("Start round", systemImage: "flag.checkered") { showingRoundSetup = true }
                    .disabled(store.course == nil || store.isLoading || roundStore.active != nil)
                // Course and tee are fixed once a round has started.
                Button("Change course, club, or tee", systemImage: "arrow.triangle.2.circlepath", action: onChangeCourse)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
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
        VStack(spacing: 6) {
            originBadge(origin)
            sidebarDistance(L("FRONT"), from: origin?.point, to: hole.greenFront ?? hole.greenCenter, style: .secondary)
            sidebarDistance(L("CENTER"), from: origin?.point, to: hole.greenCenter, style: .primary)
            sidebarDistance(L("BACK"), from: origin?.point, to: hole.greenBack ?? hole.greenCenter, style: .secondary)
            if tapPoint != nil {
                Divider().overlay(PureLineStyle.line)
                sidebarDistance(L("TARGET"), from: origin?.point, to: tapPoint, style: .target)
                sidebarDistance(L("TARGET → FLAG"), from: tapPoint, to: flag, style: .secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity)
        .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shot distances")
    }

    private enum SidebarDistanceStyle { case primary, secondary, target }

    @ViewBuilder
    private func originBadge(_ origin: DistanceOrigin?) -> some View {
        if let origin {
            // Above 20 m the fix is too coarse for trustworthy yardages, so show the uncertainty.
            let (text, symbol, trusted): (String, String, Bool) = switch origin.source {
            case .gps(let accuracy):
                accuracy > 20 ? ("GPS ±\(unit.format(accuracy))", "location", false) : ("GPS", "location.fill", true)
            case .simulated: ("DEV", "figure.golf", true)
            case .teeNoFix, .teeFarAway: (L("From tee"), "mappin", false)
            }
            Label(text, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(trusted ? PureLineStyle.accent : PureLineStyle.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(trusted ? PureLineStyle.accent.opacity(0.1) : PureLineStyle.surface, in: Capsule())
        }
    }

    private func sidebarDistance(_ title: String, from start: GeoPoint?, to end: GeoPoint?,
                                 style: SidebarDistanceStyle) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .foregroundStyle(style == .target ? PureLineStyle.accent : PureLineStyle.muted)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(distanceValue(from: start, to: end))
                    .font(style == .primary ? .largeTitle.weight(.bold)
                          : style == .target ? .title.weight(.bold) : .title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(style == .target ? PureLineStyle.accent : PureLineStyle.ink)
                Text(unit.symbol)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(PureLineStyle.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(distanceAccessibilityValue(from: start, to: end))")
    }

    private func distanceValue(from start: GeoPoint?, to end: GeoPoint?) -> String {
        guard let start, let end else { return "–" }
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
        .accessibilityLabel(isPrevious ? L("Previous hole") : activeRound == nil ? L("Next hole") : L("Enter score for this hole"))
    }
}

/// Clips left, right and bottom, but leaves room above for content drawn under the status bar.
private struct OpenTopRectangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - 200, width: rect.width, height: rect.height + 200))
    }
}

#Preview {
    CourseMapView(reference: .hills)
        .environmentObject(TrajectoryCalculatorViewModel())
        .environment(PlayedRoundStore())
}
