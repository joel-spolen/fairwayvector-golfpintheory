import SwiftUI

/// Second step after selecting a club. Keeps the club list uncluttered while
/// preserving the same course, tee and action flow for Explore, Play and HCP.
struct CourseClubSelectionPage: View {
    @Bindable var model: GolfAPICourseSelectionModel
    let club: GolfAPIClub
    let isStartRoundFlow: Bool
    var onStartCourse: ((CourseReference) -> Void)?
    var onStartRound: ((CourseReference) -> Void)?
    var onUseHandicapTee: ((HCPProviderCourse) -> Void)?
    @Environment(\.dismiss) private var dismiss

    private var handicapSelection: HCPProviderCourse? {
        guard model.purpose == .handicap, let selection = model.selection else { return nil }
        return try? HCPProviderCourse.convert(detail: selection.details, tee: selection.tee,
            sex: selection.sex, clubName: selection.club.clubName)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Label("Clubs", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("course-club-back-button")
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 48)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    PureLinePageHeader(title: club.clubName,
                        subtitle: [club.city, club.state, club.country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    CourseResultCards(model: model, club: club)
                    if model.isLoadingCourse { CourseSelectionLoading() }
                    if let detail = model.courseDetail {
                        CourseTeeSelectionCard(model: model, detail: detail)
                    }
                    if let selection = model.selection {
                        CourseSelectionSummaryCard(selection: selection)
                        if model.purpose == .handicap, let handicapSelection {
                            Button("Use tee") {
                                onUseHandicapTee?(handicapSelection)
                                dismiss()
                            }
                                .buttonStyle(PureLinePrimaryButtonStyle())
                                .accessibilityIdentifier("use-provider-tee-button")
                        } else if model.purpose == .map, isStartRoundFlow {
                            if let onStartRound {
                                Button("Start round", systemImage: "flag.checkered") {
                                    onStartRound(selection.reference)
                                }
                                .buttonStyle(PureLinePrimaryButtonStyle())
                                .accessibilityIdentifier("start-round-button")
                            }
                        } else if model.purpose == .map {
                            if let onStartCourse {
                                Button {
                                    onStartCourse(selection.reference)
                                } label: {
                                    Label("View Course", systemImage: "map.fill")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 52)
                                }
                                .buttonStyle(PureLinePrimaryButtonStyle())
                                .tint(PureLineStyle.accent)
                                .accessibilityIdentifier("view-course-button")
                            }
                        }
                    }
                }
                .foregroundStyle(PureLineStyle.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PureLineStyle.canvas)
        }
        .background(PureLineStyle.canvas)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
