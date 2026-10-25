import SwiftData
import SwiftUI

struct UnifiedSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PlayedRoundStore.self) private var playedRoundStore
    @EnvironmentObject private var accountSession: PinTheoryAccountSession
    @Query private var profiles: [PlayerProfile]
    @AppStorage("distanceUnit", store: .standard) private var mapUnit: DistanceUnit = .meters
    @AppStorage("wedgeMatrix.distanceUnit", store: .standard) private var wedgeUnit = WedgeDistanceUnit.yards.rawValue
    @EnvironmentObject private var trajectoryModel: TrajectoryCalculatorViewModel
    @State private var aboutSheet: AboutSheet?
    @State private var showingSyncFailure = false

    private enum AboutSheet: String, Identifiable {
        case company

        var id: String { rawValue }
    }

    private var profile: PlayerProfile? { profiles.first }
    private var countries: [String] {
        let apiCountries = Set(GolfAPICoverage.regions.flatMap(\.countries))
        return Array(apiCountries.union([profile?.countryOrDefault ?? "Sweden"])).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tee played from") {
                    Picker("Tee rating", selection: Binding(
                        get: { profile?.sexOrDefault ?? .male },
                        set: { sex in updateProfile { $0.sexOrDefault = sex } }
                    )) {
                        Text("Men").tag(PlayerSex.male)
                        Text("Women").tag(PlayerSex.female)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Distance units") {
                    Picker("Distance", selection: Binding(
                        get: { mapUnit },
                        set: { unit in
                            mapUnit = unit
                            wedgeUnit = unit == .meters ? WedgeDistanceUnit.meters.rawValue : WedgeDistanceUnit.yards.rawValue
                            trajectoryModel.unitPreferences.globalDefault = unit == .meters ? .metric : .imperial
                        }
                    )) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Applies to course distances, wedge carries, and trajectory defaults.")
                        .font(.footnote)
                        .foregroundStyle(PureLineStyle.muted)
                    NavigationLink("Advanced settings") {
                        TrajectoryUnitSettingsView(unitPreferences: trajectoryModel.unitPreferences)
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Country / Region") {
                    Picker("Country / Region", selection: Binding(
                        get: { profile?.countryOrDefault ?? "Sweden" },
                        set: { country in updateProfile { $0.selectedCountry = country } }
                    )) {
                        ForEach(countries, id: \.self) { country in
                            Text(country).tag(country)
                        }
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Handicap rounds") {
                    Picker("Default scoring", selection: Binding(
                        get: { profile?.defaultInputMode ?? .adjustedGrossScore },
                        set: { mode in updateProfile { $0.defaultInputMode = mode } }
                    )) {
                        ForEach(RoundInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Custom course") {
                    NavigationLink("Courses") {
                        HCPCustomCoursesEntryView()
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section("Cloud sync") {
                    Toggle("Sync across devices", isOn: Binding(
                        get: { accountSession.hasOptedIntoSavedDataSync },
                        set: { enabled in
                            accountSession.setSavedDataSyncEnabled(enabled, roundStore: playedRoundStore,
                                profile: profile, trajectoryProfileStore: trajectoryModel.playerProfileStore,
                                modelContext: modelContext)
                        }
                    ))
                    .disabled(accountSession.isSyncingSavedData)
                    .accessibilityIdentifier("account-cloud-sync")
                }
                .listRowBackground(PureLineStyle.surface)

                Section("About") {
                    Button {
                        aboutSheet = .company
                    } label: {
                        Label("Golf PinTheory", systemImage: "info.circle")
                    }
                    Link(destination: URL(string: "https://golfpintheory.com/privacy-policy/")!) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                }
                .listRowBackground(PureLineStyle.surface)
            }
            .scrollContentBackground(.hidden)
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(PureLineStyle.accent)
        .alert("Cloud sync could not finish", isPresented: Binding(
            get: { showingSyncFailure && accountSession.savedDataSyncFailure != nil },
            set: { showingSyncFailure = $0 }
        )) {
            Button("OK", role: .cancel) {
                showingSyncFailure = false
                accountSession.dismissSyncFailure()
            }
        } message: {
            Text(accountSession.savedDataSyncFailure ?? "")
        }
        .onAppear { showingSyncFailure = accountSession.savedDataSyncFailure != nil }
        .onChange(of: accountSession.savedDataSyncFailure) { _, failure in
            showingSyncFailure = failure != nil
        }
        .sheet(item: $aboutSheet) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .company:
                        FairwayVectorAboutView()
                            .navigationTitle("Golf PinTheory")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { aboutSheet = nil }
                    }
                }
            }
            .tint(PureLineStyle.accent)
            .preferredColorScheme(.light)
        }
    }

    private func updateProfile(_ edit: (PlayerProfile) -> Void) {
        if let profile {
            edit(profile)
        } else {
            let newProfile = PlayerProfile(name: "Player")
            modelContext.insert(newProfile)
            edit(newProfile)
        }
    }

}

private struct FairwayVectorAboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "location.north.circle")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(PureLineStyle.accent)
                    .accessibilityHidden(true)

                Text("Golf, made clearer.")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(PureLineStyle.ink)

                Text("Golf PinTheory is a golf app from FairwayVector, a Sweden-based software company.")
                    .font(.body)
                    .foregroundStyle(PureLineStyle.ink)

                Text("We bring together course information, handicap planning, club setup and shot insights to help golfers make more informed decisions on and off the course.")
                    .font(.body)
                    .foregroundStyle(PureLineStyle.muted)

                Text("Our focus is software designed specifically for the golf domain: practical tools that make the game easier to understand and plan.")
                    .font(.body)
                    .foregroundStyle(PureLineStyle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .pureLineCard()
            .padding(18)
        }
        .background(PureLineStyle.canvas)
    }
}

private struct FairwayVectorPrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy Policy")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(PureLineStyle.ink)
                    Text("Last updated: 2026-08-24")
                        .font(.caption)
                        .foregroundStyle(PureLineStyle.muted)
                    Text("fairwayvector-hcp-projection is an offline golf handicap projection calculator. It does not collect, store, transmit, or share any personal data.")
                        .font(.body)
                        .foregroundStyle(PureLineStyle.ink)
                        .padding(.top, 8)
                }

                policySection("Data Collection", text: "fairwayvector-hcp-projection does not collect any data. All handicap calculations and projections are performed entirely on your device. The app does not use the network, analytics, advertising, or tracking of any kind.")
                policySection("Data Storage", text: "The information the app saves, including player profiles, course data, rounds, and preferences, is stored locally on your device via Apple’s standard SwiftData and system storage mechanisms. This information never leaves your device.")
                policySection("Third-Party Services", text: "fairwayvector-hcp-projection does not integrate with any third-party SDKs, analytics providers, or advertising networks.")
                policySection("Children’s Privacy", text: "Since no data is collected from any user, this app is safe for use by individuals of all ages.")
                policySection("Changes to This Policy", text: "If this policy changes in the future, an updated version will be posted with a revised ‘Last updated’ date.")
                policySection("Contact", text: "Questions about this policy can be directed to the developer via the support contact listed on the app’s App Store page.")

                Text("© 2026 Fairway Vector")
                    .font(.caption)
                    .foregroundStyle(PureLineStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .background(PureLineStyle.canvas)
    }

    private func policySection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PureLineStyle.ink)
            Text(text)
                .font(.body)
                .foregroundStyle(PureLineStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrajectoryUnitSettingsView: View {
    @ObservedObject var unitPreferences: UnitPreferences

    var body: some View {
        Form {
            ForEach(UnitField.allCases) { field in
                Picker(field.label, selection: Binding(
                    get: { unitPreferences.override(for: field)?.rawValue ?? "default" },
                    set: { unitPreferences.setOverride(UnitSystem(rawValue: $0), for: field) }
                )) {
                    Text("Use Default").tag("default")
                    ForEach(UnitSystem.allCases) { unit in
                        Text(unit.label).tag(unit.rawValue)
                    }
                }
                .listRowBackground(PureLineStyle.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PureLineStyle.canvas)
        .foregroundStyle(PureLineStyle.ink)
        .tint(PureLineStyle.accent)
        .navigationTitle("Flight units")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
