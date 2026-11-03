import StoreKit
import SwiftData
import SwiftUI

struct UnifiedSettingsView: View {
    var onOpenAccount: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PlayedRoundStore.self) private var playedRoundStore
    @EnvironmentObject private var accountSession: PinTheoryAccountSession
    @Query private var profiles: [PlayerProfile]
    @AppStorage("distanceUnit", store: .standard) private var mapUnit: DistanceUnit = .meters
    @AppStorage("wedgeMatrix.distanceUnit", store: .standard) private var wedgeUnit = WedgeDistanceUnit.yards.rawValue
    @AppStorage(AppLanguage.preferenceKey, store: .standard)
    private var languagePreference = AppLanguage.followSystemValue
    @EnvironmentObject private var trajectoryModel: TrajectoryCalculatorViewModel
    @State private var aboutSheet: AboutSheet?
    @State private var showingSyncFailure = false
    @State private var showingPaywall = false
    @State private var showingManageSubscription = false

    private enum AboutSheet: String, Identifiable {
        case company

        var id: String { rawValue }
    }

    private var profile: PlayerProfile? { profiles.first }
    private var countries: [String] {
        let apiCountries = Set(GolfAPICoverage.regions.flatMap(\.countries))
        return Array(apiCountries.union([profile?.countryOrDefault ?? GolfAPICoverage.preferredCountry()])).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(action: onOpenAccount) {
                        Label(AppLanguage.localized("Account"), systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("settings-account-button")
                }
                .listRowBackground(PureLineStyle.surface)

                Section(String("Golf PinTheory Pro")) {
                    if ProStore.shared.isPro {
                        Label(AppLanguage.localized("Pro is active"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(PureLineStyle.accent)
                        Button(AppLanguage.localized("Manage subscription")) { showingManageSubscription = true }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Text(AppLanguage.localized("Unlock Pro"))
                                Spacer()
                                ProBadge()
                            }
                        }
                        Button(AppLanguage.localized("Restore purchases")) {
                            Task { await ProStore.shared.restore() }
                        }
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section(AppLanguage.localized("Language")) {
                    Picker(AppLanguage.localized("App language"), selection: $languagePreference) {
                        Text(AppLanguage.localized("Follow iPhone language")).tag(AppLanguage.followSystemValue)
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                    .accessibilityIdentifier("app-language-picker")
                }
                .listRowBackground(PureLineStyle.surface)

                Section(AppLanguage.localized("Tee played from")) {
                    Picker(AppLanguage.localized("Tee rating"), selection: Binding(
                        get: { profile?.sexOrDefault ?? .male },
                        set: { sex in updateProfile { $0.sexOrDefault = sex } }
                    )) {
                        Text(AppLanguage.localized("Men")).tag(PlayerSex.male)
                        Text(AppLanguage.localized("Women")).tag(PlayerSex.female)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(PureLineStyle.surface)

                Section(AppLanguage.localized("Distance units")) {
                    Picker(AppLanguage.localized("Distance"), selection: Binding(
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
                    Text(AppLanguage.localized("Applies to course distances, wedge carries, and trajectory defaults."))
                        .font(.footnote)
                        .foregroundStyle(PureLineStyle.muted)
                    NavigationLink(AppLanguage.localized("Advanced settings")) {
                        TrajectoryUnitSettingsView(unitPreferences: trajectoryModel.unitPreferences)
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section(AppLanguage.localized("Country / Region")) {
                    Picker(AppLanguage.localized("Country / Region"), selection: Binding(
                        get: { profile?.countryOrDefault ?? GolfAPICoverage.preferredCountry() },
                        set: { country in updateProfile { $0.selectedCountry = country } }
                    )) {
                        ForEach(countries, id: \.self) { country in
                            Text(country).tag(country)
                        }
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section(AppLanguage.localized("Handicap rounds")) {
                    Picker(AppLanguage.localized("Default scoring"), selection: Binding(
                        get: { profile?.defaultInputMode ?? .adjustedGrossScore },
                        set: { mode in updateProfile { $0.defaultInputMode = mode } }
                    )) {
                        ForEach(RoundInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section(AppLanguage.localized("Custom course")) {
                    NavigationLink(AppLanguage.localized("Courses")) {
                        HCPCustomCoursesEntryView()
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section(AppLanguage.localized("Cloud sync")) {
                    Toggle(AppLanguage.localized("Sync across devices"), isOn: Binding(
                        get: { accountSession.hasOptedIntoSavedDataSync },
                        set: { enabled in
                            accountSession.setSavedDataSyncEnabled(enabled, roundStore: playedRoundStore,
                                profile: profile, trajectoryProfileStore: trajectoryModel.playerProfileStore,
                                modelContext: modelContext)
                        }
                    ))
                    .disabled(accountSession.isSyncingSavedData || !ProStore.shared.isPro)
                    .accessibilityIdentifier("account-cloud-sync")
                    if !ProStore.shared.isPro {
                        HStack(spacing: 8) {
                            ProBadge()
                            Text(AppLanguage.localized("Sync across your devices"))
                                .font(.footnote)
                                .foregroundStyle(PureLineStyle.muted)
                        }
                    }
                }
                .listRowBackground(PureLineStyle.surface)

                Section(AppLanguage.localized("About")) {
                    Button {
                        aboutSheet = .company
                    } label: {
                        Label("Golf PinTheory", systemImage: "info.circle")
                    }
                    Link(destination: URL(string: "https://golfpintheory.com/privacy-policy/")!) {
                        Label(AppLanguage.localized("Privacy policy"), systemImage: "hand.raised")
                    }
                    LabeledContent(AppLanguage.localized("Elevation data"), value: "© Lantmäteriet (CC BY 4.0), GPXZ")
                        .font(.footnote)
                }
                .listRowBackground(PureLineStyle.surface)
            }
            .scrollContentBackground(.hidden)
            .background(PureLineStyle.canvas)
            .foregroundStyle(PureLineStyle.ink)
            .navigationTitle(AppLanguage.localized("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.localized("Done")) { dismiss() }
                }
            }
        }
        .tint(PureLineStyle.accent)
        .sheet(isPresented: $showingPaywall) { ProPaywallView() }
        .manageSubscriptionsSheet(isPresented: $showingManageSubscription)
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
