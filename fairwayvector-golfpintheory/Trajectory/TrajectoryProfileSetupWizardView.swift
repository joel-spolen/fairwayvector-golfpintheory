import SwiftUI

struct TrajectoryProfileSetupWizardView: View {
    @ObservedObject var profileStore: PlayerProfileStore
    let unitPreferences: UnitPreferences
    let onClose: () -> Void
    @State private var selectedBand: HandicapBand

    init(profileStore: PlayerProfileStore, unitPreferences: UnitPreferences, onClose: @escaping () -> Void) {
        self.profileStore = profileStore
        self.unitPreferences = unitPreferences
        self.onClose = onClose
        let profile = profileStore.profile
        _selectedBand = State(initialValue: profile.handicapBand)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PureLineStyle.canvas
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    Text("Set your starting profile")
                        .font(.title2.bold())
                        .foregroundStyle(PureLineStyle.ink)

                    Text("Choose the handicap range that best matches your game. It is used for club selection. To enter personal distances and launch data, open In the bag > Club distances & launch from Home.")
                        .font(.subheadline)
                        .foregroundStyle(PureLineStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Handicap range")
                            .font(.headline)
                            .foregroundStyle(PureLineStyle.ink)
                        Picker("Handicap range", selection: $selectedBand) {
                            ForEach(HandicapBand.allCases) { band in
                                Text(band.label).tag(band)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    .pureLineCard()

                    Spacer()
                }
                .padding()
            }
            .foregroundStyle(PureLineStyle.ink)
            .tint(PureLineStyle.accent)
            .navigationTitle("Profile setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { finishSetup() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func finishSetup() {
        profileStore.update { profile in
            profile.isSetupComplete = true
            profile.detailLevel = .easy
            profile.handicapBand = selectedBand
        }
        onClose()
    }
}

#Preview {
    TrajectoryProfileSetupWizardView(profileStore: PlayerProfileStore(), unitPreferences: UnitPreferences(), onClose: {})
}