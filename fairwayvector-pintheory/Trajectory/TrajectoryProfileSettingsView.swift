import SwiftUI
import UIKit

struct TrajectoryProfileSettingsView: View {
    @ObservedObject var profileStore: PlayerProfileStore
    @ObservedObject var unitPreferences: UnitPreferences
    var settingsViewModel: TrajectoryCalculatorViewModel?
    @State private var unitRefreshID = UUID()

    var body: some View {
        Form {
            Section("Active Level") {
                Picker("Level", selection: detailLevelBinding) {
                    ForEach(ProfileDetailLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Text(activeDetailDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(PureLineStyle.surface)

            activeDetailSettings
        }
        .id(unitRefreshID)
        .scrollContentBackground(.hidden)
        .background(PureLineStyle.canvas)
        .tint(PureLineStyle.accent)
        .foregroundStyle(PureLineStyle.ink)
        .preferredColorScheme(.light)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // Effective units include field overrides; the global default alone is insufficient.
        .onChange(of: [unitPreferences.unitSystem(for: .distance), unitPreferences.unitSystem(for: .ballSpeed)]) { _, _ in
            unitRefreshID = UUID()
        }
    }

    @ViewBuilder
    private var activeDetailSettings: some View {
        switch profileStore.profile.detailLevel {
        case .easy:
            EasyProfileView(profileStore: profileStore)
        case .medium:
            MediumProfileView(profileStore: profileStore, unitPreferences: unitPreferences)
        case .expert:
            ExpertProfileView(profileStore: profileStore, unitPreferences: unitPreferences)
        }
    }

    private var detailLevelBinding: Binding<ProfileDetailLevel> {
        Binding(
            get: { profileStore.profile.detailLevel },
            set: { level in
                profileStore.update { profile in
                    profile.detailLevel = level
                    profile.isSetupComplete = true
                }
            }
        )
    }

    private var activeDetailDescription: String {
        switch profileStore.profile.detailLevel {
        case .easy:
            return "Simple uses only your selected handicap range for club defaults."
        case .medium:
            return "Medium uses entered carry distances to estimate reasonable carry values for the rest of the bag."
        case .expert:
            return "Advanced uses entered launch data directly and estimates missing values from the launch data you have entered."
        }
    }
}

private struct EasyProfileView: View {
    @ObservedObject var profileStore: PlayerProfileStore

    var body: some View {
        Group {
            Section {
                Picker("Range", selection: handicapBandBinding) {
                    ForEach(HandicapBand.allCases) { band in
                        Text(band.label).tag(band)
                    }
                }
            } header: {
                Text("Handicap")
            }
            .listRowBackground(PureLineStyle.surface)
        }
    }

    private var handicapBandBinding: Binding<HandicapBand> {
        Binding(
            get: { profileStore.profile.handicapBand },
            set: { band in
                profileStore.update { $0.handicapBand = band }
            }
        )
    }
}

private struct MediumProfileView: View {
    @ObservedObject var profileStore: PlayerProfileStore
    let unitPreferences: UnitPreferences
    @State private var carryDrafts: [TrajectoryGolfClub: Double] = [:]

    var body: some View {
        Group {
                Section {
                ForEach(ownedClubs) { club in
                    let effective = ClubProfileDefaults.effectiveProfile(for: club, playerProfile: previewProfile)
                    let override = previewProfile.override(for: club)
                    ProfileDistanceRow(
                        title: club.label,
                        value: override.carryDistanceM,
                        unitPreferences: unitPreferences,
                        fallbackMeters: effective.carryDistanceM.value,
                        onDraftChange: { meters in
                            updateCarry(meters, for: club)
                        },
                        onChange: { meters in
                            updateCarry(meters, for: club)
                        }
                    )
                }
            } header: {
                Text("Club Carry Distances")
            }
            .listRowBackground(PureLineStyle.surface)
        }
    }

    private var previewProfile: TrajectoryPlayerProfile {
        var profile = profileStore.profile
        for (club, carryDistanceM) in carryDrafts {
            var override = profile.override(for: club)
            override.carryDistanceM = carryDistanceM
            profile.setOverride(override, for: club)
        }
        return profile
    }

    private var ownedClubs: [TrajectoryGolfClub] {
        TrajectoryGolfClub.allCases.filter { profileStore.profile.availableClubs.contains($0) && !$0.isWedge }
    }

    private func updateCarry(_ carryDistanceM: Double?, for club: TrajectoryGolfClub) {
        profileStore.update { profile in
            var override = profile.override(for: club)
            override.carryDistanceM = carryDistanceM
            profile.setOverride(override, for: club)
        }
        if let carryDistanceM {
            carryDrafts[club] = carryDistanceM
        } else {
            carryDrafts.removeValue(forKey: club)
        }
    }
}

private struct ExpertProfileView: View {
    @ObservedObject var profileStore: PlayerProfileStore
    let unitPreferences: UnitPreferences
    @State private var selectedClub: TrajectoryGolfClub = .driver

    var body: some View {
        Group {
            Section("Club") {
                NavigationLink {
                    ClubCarouselView(
                        selection: $selectedClub,
                        clubs: ownedClubs
                    )
                } label: {
                    HStack {
                        Image(systemName: "figure.golf")
                            .foregroundStyle(PureLineStyle.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Club")
                                .font(.caption)
                                .foregroundStyle(PureLineStyle.muted)
                            Text(selectedClub.label)
                                .font(.headline)
                                .foregroundStyle(PureLineStyle.ink)
                        }
                        Spacer()
                    }
                }
            }
            .listRowBackground(PureLineStyle.surface)

            Section {
                let effective = profileStore.effectiveProfile(for: selectedClub)
                let override = profileStore.profile.override(for: selectedClub)
                ProfileSpeedRow(
                    title: "Ball Speed",
                    value: override.ballSpeedMps,
                    unitPreferences: unitPreferences,
                    fallbackMps: effective.ballSpeedMps.value,
                    onChange: { updateOverride(\.ballSpeedMps, value: $0) }
                )
                ProfileOptionalNumberRow(
                    title: "Launch Angle",
                    value: override.launchAngleDeg,
                    unit: "deg",
                    defaultValue: override.launchAngleDeg == nil ? String(format: "%.1f deg", effective.launchAngleDeg.value) : nil,
                    decimalPlaces: 1,
                    onChange: { updateOverride(\.launchAngleDeg, value: $0) }
                )
                ProfileOptionalNumberRow(
                    title: "Spin Rate",
                    value: override.spinRateRpm,
                    unit: "rpm",
                    defaultValue: override.spinRateRpm == nil ? String(format: "%.0f rpm", effective.spinRateRpm.value) : nil,
                    decimalPlaces: 0,
                    onChange: { updateOverride(\.spinRateRpm, value: $0) }
                )
                ProfileOptionalNumberRow(
                    title: "Spin Axis",
                    value: override.spinAxisDeg,
                    unit: "deg",
                    defaultValue: override.spinAxisDeg == nil ? String(format: "%.1f deg", effective.spinAxisDeg.value) : nil,
                    decimalPlaces: 1,
                    onChange: { updateOverride(\.spinAxisDeg, value: $0) }
                )
            } header: {
                Text("Launch Data")
            }
            .listRowBackground(PureLineStyle.surface)

        }
        .onAppear {
            ensureSelectedClubIsAvailable()
        }
    }

    private func updateOverride(_ keyPath: WritableKeyPath<ClubLaunchOverride, Double?>, value: Double?) {
        profileStore.update { profile in
            var override = profile.override(for: selectedClub)
            override[keyPath: keyPath] = value
            profile.setOverride(override, for: selectedClub)
        }
    }

    private var ownedClubs: [TrajectoryGolfClub] {
        let clubs = TrajectoryGolfClub.allCases.filter { profileStore.profile.availableClubs.contains($0) && !$0.isWedge }
        return clubs.isEmpty ? [selectedClub] : clubs
    }

    private func ensureSelectedClubIsAvailable() {
        guard selectedClub.isWedge || !profileStore.profile.availableClubs.contains(selectedClub),
              let highestAvailableClub = ownedClubs.first else { return }
        selectedClub = highestAvailableClub
    }
}

struct BagClubsView: View {
    @ObservedObject var profileStore: PlayerProfileStore
    @AppStorage("wedgeMatrix.wedges") private var storedWedges = ""

    var body: some View {
        List {
            Text("These clubs are available when using Trajectory calculations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.white)

            Section {
                ForEach(TrajectoryGolfClub.allCases.filter { !$0.isWedge }) { club in
                    Toggle(club.label, isOn: binding(for: club))
                }
                .listRowBackground(Color.white)
            } header: {
                Text("Clubs")
            } footer: {
                Text("Available clubs can use the carry and launch settings in Club Distances & Launch.")
            }

            Section {
                ForEach(TrajectoryGolfClub.allCases.filter { $0.isWedge }) { club in
                    Toggle(isOn: binding(for: club)) {
                        HStack {
                            Text(club.label)
                            Spacer()
                            Text("WEDGE")
                                .font(.caption2.weight(.semibold))
                                .tracking(0.8)
                                .foregroundStyle(PureLineStyle.accent)
                        }
                    }
                }
                .listRowBackground(Color.white)
            } header: {
                Text("Wedges")
            } footer: {
                Text("Wedge carry values are edited in the Wedge Bag. They are not editable in Club Distances & Launch.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .tint(PureLineStyle.accent)
    }

    private func binding(for club: TrajectoryGolfClub) -> Binding<Bool> {
        Binding(
            get: {
                if club.isWedge,
                   let wedge = Wedge.catalog(from: storedWedges).first(where: { TrajectoryGolfClub.wedge(named: $0.name) == club }) {
                    return wedge.isInBag
                }
                return profileStore.profile.availableClubs.contains(club)
            },
            set: { isOwned in
                profileStore.update { profile in
                    if isOwned {
                        profile.availableClubs.insert(club)
                    } else {
                        profile.availableClubs.remove(club)
                    }
                }
                if club.isWedge {
                    var wedges = Wedge.catalog(from: storedWedges, availableClubs: profileStore.profile.availableClubs)
                    guard let index = wedges.firstIndex(where: { TrajectoryGolfClub.wedge(named: $0.name) == club }) else { return }
                    wedges[index].isInBag = isOwned
                    if let data = try? JSONEncoder().encode(wedges),
                       let encoded = String(data: data, encoding: .utf8) {
                        storedWedges = encoded
                    }
                }
            }
        )
    }
}

private extension View {
    func profileFormStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(PureLineStyle.canvas)
            .tint(PureLineStyle.accent)
    }
}

private struct ProfileDistanceRow: View {
    let title: String
    let value: Double?
    let unitPreferences: UnitPreferences
    let fallbackMeters: Double
    var onDraftChange: (Double?) -> Void = { _ in }
    let onChange: (Double?) -> Void

    var body: some View {
        ProfileOptionalNumberRow(
            title: title,
            value: displayValue(value),
            unit: distanceSystem == .imperial ? "yd" : "m",
            defaultValue: value == nil ? defaultText : nil,
            decimalPlaces: 0,
            refreshID: "\(title)-\(distanceSystem.rawValue)",
            onDraftChange: { display in
                guard let display else {
                    onDraftChange(nil)
                    return
                }
                onDraftChange(distanceSystem == .imperial ? Units.metersFromYards(display) : display)
            },
            onChange: { display in
                guard let display else {
                    onChange(nil)
                    return
                }
                onChange(distanceSystem == .imperial ? Units.metersFromYards(display) : display)
            }
        )
    }

    private var distanceSystem: UnitSystem {
        unitPreferences.unitSystem(for: .distance)
    }

    private var defaultText: String {
        switch distanceSystem {
        case .imperial: return String(format: "%.0f yd", Units.yardsFromMeters(fallbackMeters))
        case .metric: return String(format: "%.0f m", fallbackMeters)
        }
    }

    private func displayValue(_ meters: Double?) -> Double? {
        guard let meters else { return nil }
        switch distanceSystem {
        case .imperial: return Units.yardsFromMeters(meters)
        case .metric: return meters
        }
    }
}

private struct ProfileSpeedRow: View {
    let title: String
    let value: Double?
    let unitPreferences: UnitPreferences
    let fallbackMps: Double
    let onChange: (Double?) -> Void

    var body: some View {
        ProfileOptionalNumberRow(
            title: title,
            value: displayValue(value),
            unit: speedSystem == .imperial ? "mph" : "m/s",
            defaultValue: value == nil ? defaultText : nil,
            decimalPlaces: 1,
            refreshID: "\(title)-\(speedSystem.rawValue)",
            onChange: { display in
                guard let display else {
                    onChange(nil)
                    return
                }
                onChange(speedSystem == .imperial ? Units.mpsFromMph(display) : display)
            }
        )
    }

    private var speedSystem: UnitSystem {
        unitPreferences.unitSystem(for: .ballSpeed)
    }

    private var defaultText: String {
        switch speedSystem {
        case .imperial: return String(format: "%.1f mph", Units.mphFromMps(fallbackMps))
        case .metric: return String(format: "%.1f m/s", fallbackMps)
        }
    }

    private func displayValue(_ mps: Double?) -> Double? {
        guard let mps else { return nil }
        switch speedSystem {
        case .imperial: return Units.mphFromMps(mps)
        case .metric: return mps
        }
    }
}

private struct ProfileOptionalNumberRow: View {
    let title: String
    let value: Double?
    let unit: String?
    let defaultValue: String?
    let decimalPlaces: Int
    var refreshID: String = ""
    var onDraftChange: (Double?) -> Void = { _ in }
    let onChange: (Double?) -> Void
    @State private var draftText = ""
    @State private var hasLoadedDraft = false
    @State private var isEditing = false

    var body: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PureLineStyle.ink)
                    if let defaultValue {
                        Text("Default: \(defaultValue)")
                            .font(.caption)
                            .foregroundStyle(PureLineStyle.muted)
                    }
                }
                Spacer()
                DoneAccessoryNumberField(
                    placeholder: unit ?? "",
                    text: $draftText,
                    onEditingChanged: { editing in
                        isEditing = editing
                        if !editing {
                            commitDraft()
                        }
                    }
                )
                .frame(width: 96, height: 34)
                if let unit {
                    Text(unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PureLineStyle.muted)
                }
            }
            .padding(.vertical, 5)
        }
        .id(refreshID)
        .onAppear {
            guard !hasLoadedDraft else { return }
            draftText = formattedText
            hasLoadedDraft = true
        }
        .onChange(of: value) { _, _ in
            guard !isEditing else { return }
            draftText = formattedText
        }
        .onChange(of: refreshID) { _, _ in
            guard !isEditing else { return }
            draftText = formattedText
        }
        .onChange(of: draftText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                onDraftChange(nil)
            } else if let value = Double(trimmed) {
                onDraftChange(value)
            }
        }
    }

    private var formattedText: String {
        guard let value else { return "" }
        return String(format: "%.\(decimalPlaces)f", value)
    }

    private func commitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onChange(nil)
        } else if let value = Double(trimmed) {
            onChange(value)
        } else {
            draftText = formattedText
        }
    }
}

private struct DoneAccessoryNumberField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.placeholder = placeholder
        textField.keyboardType = .decimalPad
        textField.textAlignment = .right
        textField.borderStyle = .none
        textField.backgroundColor = UIColor(PureLineStyle.canvas)
        textField.textColor = UIColor(PureLineStyle.ink)
        textField.delegate = context.coordinator
        textField.inputAccessoryView = context.coordinator.toolbar(for: textField)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        textField.placeholder = placeholder
        if textField.text != text {
            textField.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEditingChanged: onEditingChanged)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        private let onEditingChanged: (Bool) -> Void

        init(text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void) {
            _text = text
            self.onEditingChanged = onEditingChanged
        }

        func toolbar(for textField: UITextField) -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.items = [
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(title: "Done", style: .prominent, target: textField, action: #selector(UITextField.resignFirstResponder))
            ]
            return toolbar
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            onEditingChanged(true)
            if let endPosition = textField.endOfDocument as UITextPosition? {
                textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            text = textField.text ?? ""
            onEditingChanged(false)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            text = textField.text ?? ""
        }
    }
}

#Preview {
    NavigationStack {
        TrajectoryProfileSettingsView(profileStore: PlayerProfileStore(), unitPreferences: UnitPreferences())
    }
}