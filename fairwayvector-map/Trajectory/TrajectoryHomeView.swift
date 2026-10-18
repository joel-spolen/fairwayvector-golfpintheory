import SwiftUI

struct TrajectoryHomeView: View {
    @ObservedObject var viewModel: TrajectoryCalculatorViewModel
    let onClose: () -> Void
    let onOpenLastCalculation: () -> Void
    let onExampleShot: () -> Void
    let onOpenClub: () -> Void
    let onOpenTrajectory: () -> Void
    var onHome: () -> Void = {}
    @State private var showHowItWorks = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TrajectoryPageHeader(
                        title: "Know which club to hit.",
                        subtitle: "Personalized club recommendations and realistic shot trajectories for your game."
                    )
                    primaryActions

                    if viewModel.prediction == nil {
                        emptyRecentState
                    }

                    if let prediction = viewModel.prediction {
                        flightPreview
                        lastCalculation(prediction: prediction)
                    } else {
                        flightPreview
                    }

                    Button {
                        showHowItWorks = true
                    } label: {
                        Label("How It Works", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PureLineStyle.accent)
                    .frame(height: 52)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .background(PureLineStyle.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .tint(PureLineStyle.accent)
            .sheet(isPresented: $showHowItWorks) {
                HowItWorksView()
            }
        }
        .accessibilityIdentifier("home-screen")
    }

    private var primaryActions: some View {
        VStack(spacing: 16) {
            Button {
                onOpenClub()
            } label: {
                Label("Suggest a Club", systemImage: "figure.golf")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(PureLinePrimaryButtonStyle())

            Button {
                onOpenTrajectory()
            } label: {
                HStack {
                    Label("Calculate Trajectory", systemImage: "chart.xyaxis.line")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PureLineStyle.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var flightPreview: some View {
        LiveFlightPreview(trajectory: viewModel.prediction?.physics.trajectory)
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .padding()
            .pureLineCard()
            .accessibilityLabel(viewModel.prediction == nil ? "Example flight path" : "Latest flight path")
    }

    private func lastCalculation(prediction: HybridPrediction) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Latest Calculation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PureLineStyle.muted)
            HStack {
                VStack(alignment: .leading) {
                    Text("Carry Distance")
                        .font(.caption)
                        .foregroundStyle(PureLineStyle.muted)
                    Text(Units.formattedDistance(meters: prediction.hybrid["carry_m"] ?? 0, system: viewModel.unitPreferences.unitSystem(for: .distance)))
                        .font(.largeTitle.bold())
                        .foregroundStyle(PureLineStyle.accent)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Ball Speed")
                        .font(.caption)
                        .foregroundStyle(PureLineStyle.muted)
                    Text(Units.formattedSpeed(mps: viewModel.lastCalculationBallSpeedMps ?? 0, system: viewModel.unitPreferences.unitSystem(for: .ballSpeed)))
                        .font(.headline)
                        .foregroundStyle(PureLineStyle.ink)
                }
            }
            Button {
                onOpenLastCalculation()
            } label: {
                Label("Open Trajectory", systemImage: "arrow.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PureLineStyle.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
        .accessibilityIdentifier("home-latest-calculation")
    }

    private var emptyRecentState: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ready when you are")
                    .font(.headline)
                    .foregroundStyle(PureLineStyle.ink)
                Text("Try an example shot or set your own launch conditions in the Trajectory tab.")
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.muted)
            }
            Button {
                onExampleShot()
            } label: {
                Label("Try Example Shot", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(PureLinePrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
        .accessibilityIdentifier("home-empty-state")
    }
}

private struct LiveFlightPreview: View {
    let trajectory: GolfTrajectory?

    var body: some View {
        GeometryReader { proxy in
            let points = displayPoints(in: proxy.size)

            ZStack(alignment: .bottomLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height - 12))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height - 12))
                }
                .stroke(FairwayVectorColors.gold.opacity(0.65), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(FairwayVectorColors.flightBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(FairwayVectorColors.orange)
                        .frame(width: 14, height: 14)
                        .position(last)
                }
            }
        }
    }

    private func displayPoints(in size: CGSize) -> [CGPoint] {
        let samples: [(Double, Double)]
        if let trajectory, trajectory.xM.count > 1, trajectory.xM.count == trajectory.zM.count {
            samples = Array(zip(trajectory.xM, trajectory.zM))
        } else {
            samples = (0...40).map { index in
                let x = Double(index) / 40.0
                let height = max(0.0, 4.0 * x * (1.0 - x))
                let descent = 0.10 * pow(x, 2.4)
                return (x, max(0.0, height - descent))
            }
        }

        let maxX = max(samples.map(\.0).max() ?? 1, 1)
        let maxY = max(samples.map(\.1).max() ?? 1, 1)
        return samples.map { x, y in
            CGPoint(
                x: 6 + CGFloat(x / maxX) * max(size.width - 12, 1),
                y: size.height - 12 - CGFloat(y / maxY) * max(size.height - 28, 1)
            )
        }
    }
}

private struct HomeFlightPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - 24))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - 24),
            control: CGPoint(x: rect.midX, y: rect.minY + 4)
        )
        return path
    }
}

struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    explanationRow(icon: "person.crop.circle", title: "Set your profile", text: "Use Simple, Medium, or Advanced profile settings to seed club defaults from handicap, carry distances, or launch data.")
                    explanationRow(icon: "slider.horizontal.3", title: "Enter your shot", text: "Choose a club profile or adjust ball speed, launch, spin, wind, and course conditions manually.")
                    explanationRow(icon: "function", title: "Calculate the flight", text: "fairwayvector-trajectory combines a flight simulation with calibrated corrections.")
                    explanationRow(icon: "chart.xyaxis.line", title: "Read the result", text: "Review carry, apex, landing data, and the side and top-down flight paths.")
                }
                .padding()
            }
            .background(PureLineStyle.canvas)
            .navigationTitle("How It Works")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func explanationRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(PureLineStyle.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PureLineStyle.ink)
                Text(text)
                    .font(.body)
                    .foregroundStyle(PureLineStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    TrajectoryHomeView(viewModel: TrajectoryCalculatorViewModel(), onClose: {}, onOpenLastCalculation: {}, onExampleShot: {}, onOpenClub: {}, onOpenTrajectory: {})
}
