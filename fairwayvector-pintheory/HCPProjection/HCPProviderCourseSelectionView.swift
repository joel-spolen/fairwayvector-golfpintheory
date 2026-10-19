import SwiftUI
import SwiftData

/// Inline selection content. The parent owns navigation, scrolling and confirmed scoring state.
/// No map, location manager, scorecard, draft or terrain side effects.
struct HCPProviderCourseSelectionView: View {
    @State private var model: GolfAPICourseSelectionModel
    @AppStorage("map.recentCourseReference") private var mapRecent = Data()
    @AppStorage("map.development.recentCourseReference.v1") private var pausedRecent = Data()
    @AppStorage("hcp.provider.recentCourseReference.v1") private var hcpRecent = Data()
    let profile: PlayerProfile?
    let clubs: [GolfClub]
    let courses: [GolfCourse]
    let tees: [TeeSet]
    @Binding var confirmedCustomTeeID: PersistentIdentifier?
    @State private var customClubID: PersistentIdentifier?
    @State private var customCourseName = ""
    @State private var customTeeID: PersistentIdentifier?
    let confirmedCourseID: String?
    let title: String
    let onAddCustom: ((String, String) -> Void)?
    let onSelect: (HCPProviderCourse) -> Void
    let onSelectCustom: (CourseTeeInfo) -> Void

    init(profile: PlayerProfile?, clubs: [GolfClub], courses: [GolfCourse], tees: [TeeSet],
         country: String, confirmedCourseID: String? = nil, title: String = "Where to?",
         onAddCustom: ((String, String) -> Void)? = nil,
         confirmedCustomTeeID: Binding<PersistentIdentifier?>,
         onSelectCustom: @escaping (CourseTeeInfo) -> Void,
         onSelect: @escaping (HCPProviderCourse) -> Void) {
        let sex = profile?.sexOrDefault ?? .male
        let model = GolfAPICourseSelectionModel(purpose: .handicap, sex: sex.rawValue)
        model.selectedCountry = country
        model.selectedRegion = model.coverageRegions.first { region in
            region.countries.contains { HCPCustomCourseSearch.normalizedCountry($0) == HCPCustomCourseSearch.normalizedCountry(country) }
        }?.name ?? "Europe"
        _model = State(initialValue: model)
        self.profile = profile
        self.clubs = clubs
        self.courses = courses
        self.tees = tees
        _confirmedCustomTeeID = confirmedCustomTeeID
        self.confirmedCourseID = confirmedCourseID
        self.title = title
        self.onAddCustom = onAddCustom
        self.onSelect = onSelect
        self.onSelectCustom = onSelectCustom
    }

    private var sex: PlayerSex { PlayerSex(rawValue: model.selectedSex) ?? profile?.sexOrDefault ?? .male }
    private var customMatches: [HCPCustomCourseSearch.Match] {
        HCPCustomCourseSearch.matches(clubs: clubs, courses: courses, tees: tees,
            query: model.searchText, country: model.selectedCountry, region: model.selectedRegion, sex: sex)
    }
    private var customMatch: HCPCustomCourseSearch.Match? {
        customMatches.first { $0.id == customClubID }
    }
    private var customTees: [TeeSet] {
        guard let match = customMatch else { return [] }
        return HCPCustomCourseSearch.availableTees(tees, club: match.club, courseName: customCourseName, sex: sex)
    }

    private var recent: CourseReference? {
        [hcpRecent, mapRecent, pausedRecent].compactMap { try? JSONDecoder().decode(CourseReference.self, from: $0) }
            .first { $0.golfAPICourseID != nil && !DevelopmentAPIConfiguration.isDemoCourse($0.golfAPICourseID ?? "") }
    }

    private var converted: HCPProviderCourse? {
        guard let selection = model.selection else { return nil }
        return try? HCPProviderCourse.convert(detail: selection.details, tee: selection.tee,
            sex: selection.sex, clubName: selection.club.clubName)
    }

    var body: some View {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.largeTitle.weight(.semibold)).tracking(-1)
                        Text("Find your course. Choose your tee.")
                            .font(.subheadline).foregroundStyle(PureLineStyle.muted)
                    }
                    CourseSearchControls(model: model)

                    if let onAddCustom {
                        Button {
                            onAddCustom(model.searchText.trimmingCharacters(in: .whitespacesAndNewlines), model.selectedCountry)
                        } label: {
                            Label("Add custom course", systemImage: "plus.circle")
                        }
                        .font(.subheadline).foregroundStyle(PureLineStyle.accent)
                    }

                    customResults

                    if model.selectedClubID == nil, customMatch == nil, let recent {
                        VStack(alignment: .leading, spacing: 12) {
                            CourseSelectionHeading(title: "RECENTLY SELECTED")
                            Button {
                                clearCustomDraft()
                                Task { await model.selectReference(recent) }
                            } label: {
                                CourseRecentCard(reference: recent, status: nil, showsTeeAndRating: false)
                            }
                            .buttonStyle(.plain).disabled(model.isLoadingCourse)
                            .accessibilityIdentifier("recent-course-button")
                            .accessibilityHint("Revalidates this course and tee for the selected rating category")
                        }
                    }
                    CourseSelectionStatus(model: model, suppressNoMatches: !customMatches.isEmpty)
                    if !model.clubs.isEmpty {
                        CourseClubCards(clubs: model.clubs, selectedClubID: model.selectedClubID,
                                        title: "CLUBS · \(model.clubs.count)", onSelect: { club in
                                            clearCustomDraft()
                                            model.selectClub(club)
                                        },
                                        isDisabled: model.isLoadingCourse)
                    }
                    if customMatch == nil, let club = model.selectedClub {
                        CourseResultCards(model: model, club: club)
                    }
                    if model.isLoadingCourse { CourseSelectionLoading() }
                    if customMatch == nil, let detail = model.courseDetail {
                        CourseTeeSelectionCard(model: model, detail: detail)
                    }
                    if customMatch == nil, let selection = model.selection, let converted {
                        if confirmedCourseID != converted.id {
                            CourseSelectionSummaryCard(selection: selection)
                        }
                        if converted.tee.holeHandicapIndicesData == nil {
                            Text("Provider stroke indices unavailable or invalid. Hole-by-hole scoring is disabled; no indices are invented.")
                                .font(.caption).foregroundStyle(PureLineStyle.muted)
                        }
                        Button("Use tee") {
                            guard let selection = model.selection else { return }
                            confirmedCustomTeeID = nil
                            hcpRecent = (try? JSONEncoder().encode(selection.reference)) ?? Data()
                            onSelect(converted)
                        }
                        .buttonStyle(PureLinePrimaryButtonStyle())
                    }

                }
                .foregroundStyle(PureLineStyle.ink)
                .padding(.vertical, 12)
                // Avoid Form/List automatic button behavior applying an entire row action.
                .buttonStyle(.borderless)
                .tint(PureLineStyle.accent)
                .onChange(of: profile?.sexOrDefault ?? .male) { _, newSex in
                    model.selectedSex = newSex.rawValue
                    model.selectedTeeID = nil
                    customTeeID = nil
                }
                .onChange(of: model.searchText) { clearCustomDraft() }
                .onChange(of: model.selectedCountry) { clearCustomDraft() }
                .onChange(of: model.selectedRegion) { clearCustomDraft() }
    }

    private func clearCustomDraft() {
        customClubID = nil
        customCourseName = ""
        customTeeID = nil
    }

    @ViewBuilder
    private var customResults: some View {
        if !customMatches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CourseSelectionHeading(title: "CUSTOM · \(customMatches.count)")
                ForEach(customMatches) { match in
                    Button {
                        customClubID = match.id
                        customCourseName = match.courseNames.count == 1 ? match.courseNames[0] : ""
                        customTeeID = nil
                        model.selectedTeeID = nil
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "flag").foregroundStyle(PureLineStyle.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(match.club.name).font(.subheadline.weight(.semibold))
                                Text([match.club.city, match.club.country, "Custom"].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(PureLineStyle.muted)
                                Text(match.courseNames.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(PureLineStyle.muted)
                            }
                            Spacer()
                            Image(systemName: customClubID == match.id ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundStyle(PureLineStyle.accent)
                        }
                        .pureLineCard()
                    }
                    .buttonStyle(.plain).disabled(model.isLoadingCourse)
                }
                if let match = customMatch {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Custom · \(match.club.name)").font(.headline)
                        Picker("Course", selection: $customCourseName) {
                            Text("Select Course").tag("")
                            ForEach(match.courseNames, id: \.self) { Text($0).tag($0) }
                        }
                        .onChange(of: customCourseName) { customTeeID = nil }
                        if !customCourseName.isEmpty {
                            Picker("Tee", selection: $customTeeID) {
                                Text("Select Tee").tag(Optional<PersistentIdentifier>.none)
                                ForEach(customTees) { tee in
                                    Text("\(tee.name) · \(tee.ratingSex?.label ?? "Universal")")
                                        .tag(Optional(tee.persistentModelID))
                                }
                            }
                            if customTees.isEmpty {
                                  Text(onAddCustom == nil
                                      ? "No saved tees are available for your profile rating category."
                                      : "No saved tees are available for your profile rating category. Add a custom course or tee.")
                                    .font(.caption).foregroundStyle(PureLineStyle.muted)
                            }
                        }
                        if let tee = customTees.first(where: { $0.persistentModelID == customTeeID }) {
                            Text("\(tee.holes) holes · Par \(tee.par) · CR \(tee.courseRating.formatted(.number.precision(.fractionLength(1)))) · Slope \(tee.slopeRating)")
                                .font(.caption).foregroundStyle(PureLineStyle.muted)
                            Button("Use tee") {
                                confirmedCustomTeeID = tee.persistentModelID
                                onSelectCustom(CourseTeeInfo(custom: tee))
                            }
                            .buttonStyle(PureLinePrimaryButtonStyle())
                        }
                    }
                    .pureLineCard()
                }
            }
        }
    }
}