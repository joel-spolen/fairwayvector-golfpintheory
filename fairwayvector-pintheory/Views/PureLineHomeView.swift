import SwiftUI

struct PureLineHomeView: View {
    let onOpenCourseMap: () -> Void
    let onStartRound: () -> Void
    let onOpenHandicap: () -> Void
    let onOpenBag: () -> Void
    let onOpenWedge: () -> Void
    let onOpenTrajectory: () -> Void
    let onOpenStatistics: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        Label("BY FAIRWAYVECTOR", systemImage: "location.north.circle")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.8)
                        Spacer()
                        Button(action: onOpenSettings) {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.medium))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PureLineStyle.accent)
                        .accessibilityLabel("Global settings")
                        .accessibilityIdentifier("global-settings-button")
                    }
                    .foregroundStyle(PureLineStyle.muted)
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("A clearer way\nto play.")
                            .font(.system(.largeTitle, design: .default).weight(.semibold))
                            .tracking(-1.2)
                            .foregroundStyle(PureLineStyle.ink)
                        Text("Your course. Your game. One place.")
                            .font(.subheadline)
                            .foregroundStyle(PureLineStyle.muted)
                    }

                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ON THE COURSE")
                                    .font(.caption2.weight(.semibold)).tracking(1.5)
                                    .foregroundStyle(PureLineStyle.accent)
                                Text("Make your next\nround count.")
                                    .font(.title2.weight(.semibold)).tracking(-0.6)
                                    .foregroundStyle(PureLineStyle.ink)
                            }
                            Spacer()
                            Image(systemName: "flag")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(PureLineStyle.accent)
                                .frame(width: 56, height: 56)
                                .background(.white, in: Circle())
                        }
                        Text("Explore the hole, plan your shot, and keep your scorecard close.")
                            .font(.subheadline)
                            .foregroundStyle(PureLineStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: onStartRound) {
                            HStack {
                                Text("Start round")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.padding(.horizontal, 20)
                        }
                        .buttonStyle(PureLinePrimaryButtonStyle())
                        Button(action: onOpenCourseMap) {
                            HStack {
                                Label("Explore a course", systemImage: "map")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PureLineStyle.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .pureLineCard(padding: 24)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Build your game")
                            .font(.title3.weight(.semibold)).tracking(-0.4)
                            .padding(.bottom, 10)
                        destination("Handicap", detail: "Round history & score projections", symbol: "chart.line.uptrend.xyaxis", action: onOpenHandicap)
                        Divider().overlay(PureLineStyle.line)
                        destination("In the bag", detail: "Set up your clubs and wedges", symbol: "bag", action: onOpenBag)
                        Divider().overlay(PureLineStyle.line)
                        destination("Wedge Matrix", detail: "Your distances. Every swing.", symbol: "target", action: onOpenWedge)
                        Divider().overlay(PureLineStyle.line)
                        destination("Trajectory", detail: "Understand your next shot", symbol: "chart.xyaxis.line", action: onOpenTrajectory)
                    }
                    .foregroundStyle(PureLineStyle.ink)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("See your game")
                            .font(.title3.weight(.semibold)).tracking(-0.4)
                            .padding(.bottom, 10)
                        destination("Rounds & statistics", detail: "Review your scores and spot the trends", symbol: "chart.xyaxis.line", action: onOpenStatistics)
                            .accessibilityIdentifier("home-rounds-statistics-button")
                    }
                    .foregroundStyle(PureLineStyle.ink)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "location")
                            .foregroundStyle(PureLineStyle.accent)
                        Text("Enable location for live GPS distances. Loaded course data stays available offline.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(PureLineStyle.muted)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
            .background(PureLineStyle.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(PureLineStyle.accent)
        .accessibilityIdentifier("map-home-screen")
    }

    private func destination(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(PureLineStyle.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(PureLineStyle.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption).foregroundStyle(PureLineStyle.muted)
            }
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}