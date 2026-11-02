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

                    Text("Pick the range closest to your handicap. It's used to suggest clubs until you add your own distances in In the bag.")
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
        let previous = profileStore.profile
        profileStore.update { profile in
            profile.isSetupComplete = true
            profile.detailLevel = .easy
            profile.handicapBand = selectedBand
        }
        // Without a fresh timestamp, cloud sync treats the older remote profile as newer.
        if profileStore.profile != previous { profileStore.markClubProfileSaved() }
        onClose()
    }
}

#Preview {
    TrajectoryProfileSetupWizardView(profileStore: PlayerProfileStore(), unitPreferences: UnitPreferences(), onClose: {})
}