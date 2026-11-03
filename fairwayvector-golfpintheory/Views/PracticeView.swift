import SwiftUI

enum PracticeDestination: String, CaseIterable {
    case trajectory
    case wedge
}

struct PracticeView: View {
    @Binding var destination: PracticeDestination
    @ObservedObject var trajectoryModel: TrajectoryCalculatorViewModel
    var onHome: () -> Void = {}

    var body: some View {
        Group {
            if !ProStore.shared.isPro {
                VStack(spacing: 0) {
                    PureLineHomeButton(onHome: onHome)
                    ProLockedView(title: destination == .trajectory ? L("Trajectory") : L("Wedge Matrix"))
                }
                .background(PureLineStyle.canvas)
            } else {
                switch destination {
                case .trajectory:
                    TrajectoryRootView(viewModel: trajectoryModel, onHome: onHome)
                case .wedge:
                    WedgeMatrixView(onHome: onHome)
                }
            }
        }
        .tint(PureLineStyle.accent)
    }
}
