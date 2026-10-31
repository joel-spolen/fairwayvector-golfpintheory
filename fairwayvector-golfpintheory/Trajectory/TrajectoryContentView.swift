//
//  ContentView.swift
//  fairwayvector-trajectory
//
//  Created by FairwayVector on 2026-08-22.
//

import SwiftUI

struct TrajectoryRootView: View {
    private enum Tab: String, CaseIterable {
        case home
        case calculator
        case club

        var title: String {
            switch self {
            case .home: L("Overview")
            case .calculator: L("Trajectory")
            case .club: L("Club Selector")
            }
        }
    }

    @ObservedObject var viewModel: TrajectoryCalculatorViewModel
    var onHome: () -> Void = {}
    @State private var selectedTab: Tab = .home

    var body: some View {
        VStack(spacing: 0) {
            PureLineHomeButton(onHome: onHome)
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(selectedTab == tab ? PureLineStyle.accent : PureLineStyle.muted)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding(.horizontal, 4)
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(PureLineStyle.canvas)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(PureLineStyle.line, lineWidth: 1)
                                        }
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                }
            }
            .padding(4)
            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(PureLineStyle.canvas)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Trajectory tools")

            Group {
                switch selectedTab {
                case .home:
                    TrajectoryHomeView(
                        viewModel: viewModel,
                        onClose: {},
                        onOpenLastCalculation: {
                            viewModel.restoreLastCalculationInputs()
                            selectedTab = .calculator
                        },
                        onExampleShot: { viewModel.randomizeExampleShot() },
                        onOpenClub: { selectedTab = .club },
                        onOpenTrajectory: { selectedTab = .calculator },
                        onHome: onHome
                    )
                case .calculator:
                    TrajectoryCalculatorView(viewModel: viewModel, onHome: onHome)
                case .club:
                    TrajectoryClubView(viewModel: viewModel, onOpenTrajectory: { selectedTab = .calculator }, onHome: onHome)
                }
            }
        }
        .tint(PureLineStyle.accent)
    }
}

struct TrajectoryPageHeader: View {
    let title: String
    let subtitle: String
    var onReset: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                PureLinePageHeader(title: title, subtitle: subtitle)
                if let onReset {
                    Button(action: onReset) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PureLineStyle.accent)
                    .accessibilityLabel("Reset inputs")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .background(PureLineStyle.canvas)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    TrajectoryRootView(viewModel: TrajectoryCalculatorViewModel())
}
