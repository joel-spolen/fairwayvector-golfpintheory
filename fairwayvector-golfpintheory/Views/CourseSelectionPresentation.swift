import SwiftUI

/// Shared Pure Line presentation only. Eligibility and provider access stay in the selection model.
struct CourseSearchControls: View {
    @Bindable var model: GolfAPICourseSelectionModel

    private var searchDisabled: Bool {
        model.isSearching || (model.selectedCountry.isEmpty && model.availableCountries.isEmpty
            && model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (model.purpose == .handicap && model.isLoadingCourse)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CourseSelectionHeading(title: "FIND A COURSE", tracking: 1.2)
            HStack(spacing: 14) {
                Menu {
                    ForEach(model.coverageRegions) { region in
                        Button(region.name) { model.selectRegion(region.name) }
                    }
                } label: {
                    Label(model.selectedRegion.isEmpty ? "Region" : model.selectedRegion, systemImage: "globe")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityLabel(model.selectedRegion.isEmpty ? "Region" : model.selectedRegion)
                        .accessibilityAddTraits(.isButton)
                }
                .accessibilityIdentifier("golf-coverage-region-picker")
                .disabled(model.isSearching)

                Rectangle().fill(PureLineStyle.line).frame(width: 1, height: 24).accessibilityHidden(true)

                Menu {
                    ForEach(model.availableCountries, id: \.self) { country in
                        Button(country) { model.selectCountry(country) }
                    }
                } label: {
                    Label(model.selectedCountry.isEmpty ? "Country" : model.selectedCountry, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityLabel(model.selectedCountry.isEmpty ? "Country" : model.selectedCountry)
                        .accessibilityAddTraits(.isButton)
                }
                .disabled(model.selectedRegion.isEmpty || model.isSearching)
                .accessibilityIdentifier("golf-country-picker")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                TextField("Search club name", text: $model.searchText)
                    .textContentType(.organizationName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .onSubmit { Task { await model.search() } }
                    .accessibilityIdentifier("golf-club-search-field")
                    .disabled(model.isSearching)
                Button {
                    Task { await model.search() }
                } label: {
                    if model.isSearching {
                        ProgressView().frame(width: 48, height: 44)
                    } else {
                        Image(systemName: "magnifyingglass").frame(width: 48, height: 44)
                    }
                }
                .buttonStyle(PureLinePrimaryButtonStyle(fillsWidth: false, minimumHeight: 44))
                .disabled(searchDisabled)
                .accessibilityLabel("Search golf clubs")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(PureLineStyle.line, lineWidth: 1))
            if model.isSearching {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Searching courses")
                    .accessibilityIdentifier("course-search-progress")
            }
        }
    }
}

struct CourseSelectionHeading: View {
    let title: String
    var tracking: CGFloat = 1

    var body: some View {
        Text(title).font(.caption.weight(.semibold)).tracking(tracking).foregroundStyle(PureLineStyle.muted)
    }
}

struct CourseClubCards: View {
    let clubs: [GolfAPIClub]
    let selectedClubID: String?
    let title: String
    let onSelect: (GolfAPIClub) -> Void
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CourseSelectionHeading(title: title)
            ForEach(clubs) { club in
                Button { onSelect(club) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(PureLineStyle.accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(club.clubName).font(.subheadline.weight(.semibold)).foregroundStyle(PureLineStyle.ink)
                            Text([club.city, club.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(PureLineStyle.muted)
                        }
                        Spacer()
                        Text("\(club.courses.count) courses").font(.caption2).foregroundStyle(PureLineStyle.muted)
                        Image(systemName: selectedClubID == club.id ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(PureLineStyle.accent)
                    }
                    .pureLineCard()
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(selectedClubID == club.id ? PureLineStyle.accent : Color.clear, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
    }
}

struct CourseCatalogMoreButton: View {
    let model: GolfAPICourseSelectionModel

    var body: some View {
        Button {
            Task { await model.loadMoreClubs() }
        } label: {
            HStack {
                Spacer()
                if model.isLoadingMore {
                    ProgressView().padding(.trailing, 8)
                    Text("Loading clubs…")
                } else {
                    Text("Load more clubs")
                    Image(systemName: "chevron.down")
                }
                Spacer()
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(model.isLoadingMore)
        .accessibilityIdentifier("load-more-clubs-button")
    }
}

struct CourseResultCards: View {
    let model: GolfAPICourseSelectionModel
    let club: GolfAPIClub

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CourseSelectionHeading(title: "COURSES AT \(club.clubName.uppercased())")
            ForEach(club.courses) { course in
                Button { Task { await model.selectCourse(course) } } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(course.courseName).font(.subheadline.weight(.semibold)).foregroundStyle(PureLineStyle.ink)
                            Text(model.purpose == .handicap
                                   ? "\(course.numHoles) holes"
                                 : "\(course.numHoles) holes\(course.hasGPS ? "" : " · GPS data not available")")
                                .font(.caption).foregroundStyle(PureLineStyle.muted)
                        }
                        Spacer()
                        if model.isLoadingCourse && model.selectedCourseID == course.id {
                            ProgressView()
                        } else {
                            Image(systemName: model.selectedCourseID == course.id ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundStyle(PureLineStyle.accent)
                        }
                    }
                    .pureLineCard()
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(model.selectedCourseID == course.id ? PureLineStyle.accent : Color.clear, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                // Let a tap explain why a listed course is unavailable instead
                // of silently ignoring it. The model rejects missing GPS before
                // downloading anything or spending a provider request.
                .disabled(model.isLoadingCourse)
                if model.selectedCourseID == course.id, let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(PureLineStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("selected-course-error")
                }
            }
        }
    }
}

struct CourseTeeSelectionCard: View {
    @Bindable var model: GolfAPICourseSelectionModel
    let detail: GolfAPICourseDetail
    @State private var showingRatingCategoryInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CourseSelectionHeading(title: "TEE SET")
            if model.purpose == .handicap {
                HStack {
                    Text("Rating category")
                    Spacer()
                    Text(model.selectedSex == "female" ? "Women" : "Men")
                        .fontWeight(.medium)
                    Button {
                        showingRatingCategoryInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(PureLineStyle.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rating category information")
                }
                .font(.subheadline)
                .foregroundStyle(PureLineStyle.muted)
                .alert("Rating category", isPresented: $showingRatingCategoryInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("The Men/Women rating category follows your player settings. Change it in Settings.")
                }
            } else {
                Picker("Rating category", selection: $model.selectedSex) {
                    Text("Men").tag("male")
                    Text("Women").tag("female")
                }
                .pickerStyle(.segmented)
                .onChange(of: model.selectedSex) {
                    model.selectedTeeID = (model.ratedTees.first ?? model.selectableTees.first)?.teeID
                }
                .accessibilityIdentifier("golf-rating-category-picker")
            }
            Picker("Tee", selection: Binding(
                get: { model.selectedTeeID ?? "" },
                set: { model.selectedTeeID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Select tee").tag("")
                ForEach(model.selectableTees) { tee in
                    Text("\(tee.teeName) · CR \(tee.rating(for: model.selectedSex).map { String(format: "%.1f", $0) } ?? "–") · Slope \(tee.slope(for: model.selectedSex).map(String.init) ?? "–")")
                        .tag(tee.teeID)
                }
            }
            .pickerStyle(.navigationLink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 12))

            Text(model.purpose == .handicap
                  ? "\(detail.numHoles) holes"
                 : "\(detail.numHoles) holes\(detail.hasGPS ? "" : " · GPS data not available")")
                .font(.caption).foregroundStyle(PureLineStyle.muted)
            if model.purpose == .map, let tee = model.selectedTee,
               tee.rating(for: model.selectedSex) == nil || tee.slope(for: model.selectedSex) == nil {
                Text("Ratings are unavailable for this tee and category. You can explore the course; net scoring and Handicap calculations require valid ratings.")
                    .font(.caption).foregroundStyle(PureLineStyle.muted)
            }
        }
        .pureLineCard()
    }
}

struct CourseSelectionSummaryCard: View {
    let selection: GolfAPICourseSelection

    var body: some View {
        let coursePars = selection.sex == "female" ? selection.details.parsWomen : selection.details.parsMen
        let pars = selection.tee.pars(for: selection.sex, fallback: coursePars)
        VStack(alignment: .leading, spacing: 12) {
            CourseSelectionHeading(title: "SELECTED COURSE")
            Text("\(selection.club.clubName) · \(selection.details.courseName)")
                .font(.headline).foregroundStyle(PureLineStyle.ink)
            Text("\(selection.tee.teeName) · \(selection.sex == "female" ? "Women" : "Men")")
                .font(.subheadline).foregroundStyle(PureLineStyle.muted)
            Rectangle().fill(PureLineStyle.line).frame(height: 1).accessibilityHidden(true)
            HStack(spacing: 18) {
                rating("COURSE RATING", selection.tee.rating(for: selection.sex).map { String(format: "%.1f", $0) } ?? "–")
                rating("SLOPE", selection.tee.slope(for: selection.sex).map(String.init) ?? "–")
                rating("PAR", pars.isEmpty ? "–" : "\(pars.reduce(0, +))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
    }

    private func rating(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(PureLineStyle.muted)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(PureLineStyle.ink)
        }
    }
}

struct CourseSelectionStatus: View {
    let model: GolfAPICourseSelectionModel
    var suppressNoMatches = false

    var body: some View {
        if !model.isConfigured {
            message("Supabase provider data is not configured in this app build.", image: "key.horizontal")
        }
        if let error = model.errorMessage,
           !(suppressNoMatches && error.hasPrefix("No golf clubs matched")) {
            message(error, image: "exclamationmark.triangle").accessibilityIdentifier("course-search-message")
        }
    }

    private func message(_ text: String, image: String) -> some View {
        Label(text, systemImage: image).font(.footnote).foregroundStyle(PureLineStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CourseSelectionLoading: View {
    var body: some View {
        ProgressView("Loading course and tee information…").frame(maxWidth: .infinity)
    }
}

struct CourseRecentCard: View {
    let reference: CourseReference
    let status: String?
    var showsTeeAndRating = true

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3).foregroundStyle(PureLineStyle.accent)
                .frame(width: 40, height: 40)
                .background(PureLineStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(reference.courseName).font(.subheadline.weight(.semibold)).foregroundStyle(PureLineStyle.ink)
                if reference.clubName != reference.courseName {
                    Text(reference.clubName).font(.caption).foregroundStyle(PureLineStyle.muted)
                }
                 Text(showsTeeAndRating
                     ? "\(reference.teeName) tee · \(reference.teeSex == "female" ? "Women" : "Men") · \(reference.holeCount) holes"
                     : "\(reference.holeCount) holes")
                    .font(.caption).foregroundStyle(PureLineStyle.muted)
                if let status { Text(status).font(.caption).foregroundStyle(PureLineStyle.accent) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(PureLineStyle.accent)
        }
        .pureLineCard()
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}