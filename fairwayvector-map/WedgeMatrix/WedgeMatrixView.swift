import SwiftUI
import UIKit

struct WedgeMatrixView: View {
    private enum Section: String, CaseIterable {
        case overview, selector, matrix

        var title: String {
            switch self {
            case .overview: "Overview"
            case .selector: "Selector"
            case .matrix: "Matrix"
            }
        }
    }

    var onHome: () -> Void = {}

    @AppStorage("wedgeMatrix.wedges") private var storedWedges = ""
    @AppStorage("wedgeMatrix.distanceUnit") private var selectedUnitRawValue = WedgeDistanceUnit.yards.rawValue
    @State private var wedges: [Wedge] = Wedge.defaults
    @State private var selectedTrajectory: WedgeTrajectory = .stock
    @State private var targetDistance = 92.0
    @State private var selectorElevationMeters = 0.0
    @State private var selectorPinFraction = 0.5
    @State private var section: Section = .overview

    private var bagWedges: [Wedge] {
        wedges.filter(\.isInBag)
    }

    private var selectedUnit: WedgeDistanceUnit {
        WedgeDistanceUnit(rawValue: selectedUnitRawValue) ?? .yards
    }

    var body: some View {
        VStack(spacing: 0) {
            PureLineHomeButton(onHome: onHome)
            HStack(spacing: 4) {
                ForEach(Section.allCases, id: \.self) { item in
                    Button {
                        section = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(section == item ? PureLineStyle.accent : PureLineStyle.muted)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background {
                                if section == item {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(PureLineStyle.canvas)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14)
                                                .strokeBorder(PureLineStyle.line, lineWidth: 1)
                                        }
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? [.isSelected] : [])
                }
            }
            .padding(4)
            .background(PureLineStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(PureLineStyle.canvas)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Wedge tools")

            Group {
                switch section {
                case .overview:
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                WedgePageHeader(title: "Your wedge setup", subtitle: "Review your carry numbers and the wedges currently in your bag.", horizontalInset: 0)
                                WedgeHomeOverviewCard(wedges: wedges, bagWedges: bagWedges)
                                WedgeCurrentBagCard(wedges: bagWedges, unit: selectedUnit)
                                WedgeBagNotesCard()
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 18)
                            .padding(.bottom, 18)
                        }
                        .background(PureLineStyle.canvas)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                    }

                case .selector:
                    NavigationStack {
                        WedgeClubSelectorView(
                            wedges: bagWedges,
                            unit: selectedUnit,
                            targetDistance: $targetDistance,
                            elevationMeters: $selectorElevationMeters,
                            pinFraction: $selectorPinFraction,
                            pageTitle: "Choose a wedge",
                            pageSubtitle: "Set the distance, green elevation and pin position to find a club and swing."
                        )
                        .background(PureLineStyle.canvas)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                    }

                case .matrix:
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                WedgePageHeader(title: "Wedge matrix", subtitle: "Compare carry distances across swing lengths and trajectories.", horizontalInset: 0)
                                WedgeTrajectoryPicker(selectedTrajectory: $selectedTrajectory)
                                WedgeMatrixCard(wedges: bagWedges, trajectory: selectedTrajectory, unit: selectedUnit)
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 18)
                            .padding(.bottom, 18)
                        }
                        .background(PureLineStyle.canvas)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                    }

                }
            }
        }
        .background(PureLineStyle.canvas)
        .tint(PureLineStyle.accent)
        .onAppear(perform: loadStoredWedges)
        .onChange(of: wedges) { _, newValue in
            guard let data = try? JSONEncoder().encode(newValue),
                  let encoded = String(data: data, encoding: .utf8) else { return }
            storedWedges = encoded
        }
    }

    private func loadStoredWedges() {
        wedges = Wedge.catalog(from: storedWedges)
    }
}

struct WedgeBagSetupView: View {
    @AppStorage("wedgeMatrix.wedges") private var storedWedges = ""
    @AppStorage("wedgeMatrix.distanceUnit") private var selectedUnitRawValue = WedgeDistanceUnit.yards.rawValue
    @State private var wedges: [Wedge] = Wedge.defaults
    @ObservedObject var profileStore: PlayerProfileStore

    init(profileStore: PlayerProfileStore) {
        self.profileStore = profileStore
    }

    private var selectedUnit: WedgeDistanceUnit {
        WedgeDistanceUnit(rawValue: selectedUnitRawValue) ?? .yards
    }

    var body: some View {
        WedgeBagManagementList(wedges: $wedges, unit: selectedUnit)
        .onAppear(perform: loadStoredWedges)
        .onChange(of: wedges) { _, newValue in
            guard let data = try? JSONEncoder().encode(newValue),
                  let encoded = String(data: data, encoding: .utf8) else { return }
            storedWedges = encoded
            syncProfileBag(from: newValue)
        }
    }

    private func loadStoredWedges() {
        wedges = Wedge.catalog(from: storedWedges, availableClubs: profileStore.profile.availableClubs)
        if let data = try? JSONEncoder().encode(wedges),
           let encoded = String(data: data, encoding: .utf8) {
            storedWedges = encoded
        }
        syncProfileBag(from: wedges)
    }

    private func syncProfileBag(from wedges: [Wedge]) {
        let inBag = Set(wedges.compactMap { wedge -> TrajectoryGolfClub? in
            guard wedge.isInBag else { return nil }
            return TrajectoryGolfClub.wedge(named: wedge.name)
        })
        profileStore.update { profile in
            for club in TrajectoryGolfClub.allCases where club.isWedge {
                if inBag.contains(club) {
                    profile.availableClubs.insert(club)
                } else {
                    profile.availableClubs.remove(club)
                }
            }
        }
    }
}

struct WedgePageHeader: View {
    let title: String
    let subtitle: String
    var horizontalInset: CGFloat = 18

    var body: some View {
        PureLinePageHeader(title: title, subtitle: subtitle)
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 18)
        .background(PureLineStyle.canvas)
    }
}

private struct WedgeHomeOverviewCard: View {
    var wedges: [Wedge]
    var bagWedges: [Wedge]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WedgeMetricCard(title: "Wedges", value: "\(wedges.count)", systemImage: "list.bullet")
                WedgeMetricCard(title: "In Bag", value: "\(bagWedges.count)", systemImage: "bag")
            }
        }
        .pureLineCard()
    }
}

private struct WedgeCurrentBagCard: View {
    var wedges: [Wedge]
    var unit: WedgeDistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Bag")
                .font(.headline)

            if wedges.isEmpty {
                Text("No wedges selected for the bag.")
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(wedges) { wedge in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wedge.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(PureLineStyle.ink)
                            if let brand = wedge.brandDisplay {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundStyle(PureLineStyle.muted)
                            }
                        }
                        Spacer()
                        Text(unit.format(wedge.fullCarry))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PureLineStyle.ink)
                            .monospacedDigit()
                    }
                    .padding(12)
                    .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .pureLineCard()
    }
}

private struct WedgeBagNotesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Matrix notes", systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(PureLineStyle.ink)
            VStack(alignment: .leading, spacing: 10) {
                WedgeNoteRow(value: "50%", text: "Clock-face or waist-high swings")
                WedgeNoteRow(value: "75%", text: "Controlled three-quarter tempo")
                WedgeNoteRow(value: "Full", text: "Stock full carry, not total distance")
            }
        }
        .pureLineCard()
    }
}

private struct WedgeNoteRow: View {
    var value: String
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(Color.white)
                .frame(width: 48)
                .padding(.vertical, 6)
                .background(PureLineStyle.accent, in: Capsule())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(PureLineStyle.muted)
            Spacer()
        }
    }
}

private struct WedgeMetricCard: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(PureLineStyle.accent)
                .frame(width: 34, height: 34)
                .background(PureLineStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(PureLineStyle.muted)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(PureLineStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pureLineCard()
    }
}

private struct WedgeTrajectoryPicker: View {
    @Binding var selectedTrajectory: WedgeTrajectory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trajectory")
                .font(.headline)
            Picker("Trajectory", selection: $selectedTrajectory) {
                ForEach(WedgeTrajectory.allCases) { trajectory in
                    Label(trajectory.title, systemImage: trajectory.systemImage).tag(trajectory)
                }
            }
            .pickerStyle(.segmented)
        }
        .pureLineCard()
    }
}

private struct WedgeMatrixCard: View {
    var wedges: [Wedge]
    var trajectory: WedgeTrajectory
    var unit: WedgeDistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(trajectory.title) Trajectory")
                        .font(.headline)
                    Text("Carry distances adjusted for \(trajectory.title.lowercased()) shots")
                        .font(.caption)
                        .foregroundStyle(PureLineStyle.muted)
                }
                Spacer()
                Image(systemName: "flag.checkered")
                    .font(.title3)
                    .foregroundStyle(PureLineStyle.accent)
            }

            if wedges.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bag.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(PureLineStyle.muted)
                    Text("No Wedges In Bag")
                        .font(.headline)
                    Text("Choose wedges in Clubs in my bag to include them here.")
                        .font(.subheadline)
                        .foregroundStyle(PureLineStyle.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Club")
                            .font(.caption.bold())
                            .foregroundStyle(PureLineStyle.muted)
                            .frame(width: 72, alignment: .leading)
                        ForEach(SwingLength.allCases) { swing in
                            Text(swing.title)
                                .font(.caption.bold())
                                .foregroundStyle(PureLineStyle.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    ForEach(wedges) { wedge in
                        HStack(spacing: 8) {
                            Text(wedge.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(PureLineStyle.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .frame(width: 72, alignment: .leading)

                            ForEach(SwingLength.allCases) { swing in
                                let carry = wedge.carry(for: trajectory, swing: swing)
                                Text("\(unit.format(carry)) \(unit.abbreviation)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(PureLineStyle.ink)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(swing == .full ? PureLineStyle.accent.opacity(0.1) : PureLineStyle.canvas,
                                                in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }
        }
        .pureLineCard()
    }
}

private struct WedgeBagManagementList: View {
    @Binding var wedges: [Wedge]
    var unit: WedgeDistanceUnit

    var body: some View {
        List {
            Section {
                WedgePageHeader(
                    title: "Your wedge bag",
                    subtitle: "Manage the clubs you carry. Tap a club to edit its distances."
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(PureLineStyle.canvas)
                .listRowSeparator(.hidden)
            }
            .listSectionMargins(.top, 18)
            .listSectionMargins(.horizontal, 0)

            Section {
                ForEach(wedges) { wedge in
                    if let wedgeBinding = binding(for: wedge) {
                        HStack {
                            NavigationLink {
                                WedgeClubDetailView(wedge: wedgeBinding, unit: unit)
                            } label: {
                                WedgeClubInventoryRow(wedge: wedge, unit: unit)
                            }
                            .disabled(!wedge.isInBag)
                            Toggle("In Bag", isOn: wedgeBinding.isInBag)
                                .labelsHidden()
                                .tint(PureLineStyle.accent)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Club Inventory")
                    Spacer()
                    Text("In Bag")
                        .font(.caption.weight(.semibold))
                }
            }
            .listRowBackground(PureLineStyle.surface)
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .background(PureLineStyle.canvas)
    }

    private func binding(for wedge: Wedge) -> Binding<Wedge>? {
        guard wedges.contains(where: { $0.id == wedge.id }) else { return nil }
        return Binding(
            get: { wedges.first(where: { $0.id == wedge.id }) ?? wedge },
            set: { updatedWedge in
                guard let index = wedges.firstIndex(where: { $0.id == wedge.id }) else { return }
                wedges[index] = updatedWedge
            }
        )
    }

}

private struct WedgeClubInventoryRow: View {
    var wedge: Wedge
    var unit: WedgeDistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(TrajectoryGolfClub.wedge(named: wedge.name)?.label ?? wedge.name)
                .font(.subheadline.bold())
                .foregroundStyle(PureLineStyle.ink)
            if let brand = wedge.brandDisplay {
                Text(brand)
                    .font(.caption)
                    .foregroundStyle(PureLineStyle.muted)
            }
            Text("Stock: \(unit.format(wedge.fullCarry)) \(unit.abbreviation)")
                .font(.caption)
                .foregroundStyle(PureLineStyle.muted)
        }
    }
}

private struct WedgeClubDetailView: View {
    @Binding var wedge: Wedge
    let unit: WedgeDistanceUnit
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Wedge

    init(wedge: Binding<Wedge>, unit: WedgeDistanceUnit) {
        _wedge = wedge
        self.unit = unit
        _draft = State(initialValue: wedge.wrappedValue)
    }

    private var hasChanges: Bool {
        draft != wedge
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WedgeClubDistancesCard(wedge: $draft, unit: unit)
            }
            .padding()
        }
        .background(PureLineStyle.canvas)
        .navigationTitle(draft.name.isEmpty ? "Club" : draft.name)
        .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    wedge = draft
                    dismiss()
                }
                .disabled(!hasChanges)
            }
        }
    }
}

private struct WedgeClubDistancesCard: View {
    @Binding var wedge: Wedge
    let unit: WedgeDistanceUnit
    @State private var drafts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Distances")
                .font(.headline)
                .foregroundStyle(PureLineStyle.ink)

            ForEach(WedgeTrajectory.allCases) { trajectory in
                VStack(alignment: .leading, spacing: 8) {
                    Text(trajectory.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(PureLineStyle.muted)

                    HStack(spacing: 8) {
                        ForEach(SwingLength.allCases) { swing in
                            VStack(spacing: 4) {
                                Text(swing.title)
                                    .font(.caption)
                                    .foregroundStyle(PureLineStyle.muted)
                                WedgeDoneAccessoryNumberField(
                                    placeholder: "\(unit.format(wedge.carry(for: trajectory, swing: swing)))",
                                    text: draftBinding(for: trajectory, swing: swing),
                                    textAlignment: .center
                                )
                                .frame(height: 20)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PureLineStyle.ink)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(swing == .full ? PureLineStyle.accent.opacity(0.1) : PureLineStyle.canvas,
                                            in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }
        }
        .pureLineCard()
        .onAppear(perform: loadDrafts)
        .onChange(of: unit) { _, _ in loadDrafts() }
    }

    private func draftBinding(for trajectory: WedgeTrajectory, swing: SwingLength) -> Binding<String> {
        let key = "\(trajectory.rawValue).\(swing.rawValue)"
        return Binding(
            get: { drafts[key] ?? "" },
            set: { value in
                drafts[key] = value
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    wedge.clearCarry(for: trajectory, swing: swing)
                    return
                }
                guard let number = Double(trimmed), number > 0 else { return }
                let carryInYards = unit == .yards ? number : number / 0.9144
                wedge.setCarry(carryInYards, for: trajectory, swing: swing)
            }
        )
    }

    private func loadDrafts() {
        var values: [String: String] = [:]
        for trajectory in WedgeTrajectory.allCases {
            for swing in SwingLength.allCases {
                let key = "\(trajectory.rawValue).\(swing.rawValue)"
                if let override = wedge.overrideCarry(for: trajectory, swing: swing) {
                    let displayValue = unit == .yards ? override : override * 0.9144
                    values[key] = String(format: "%.0f", displayValue)
                } else {
                    values[key] = ""
                }
            }
        }
        drafts = values
    }
}

private struct WedgeDoneAccessoryNumberField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var textAlignment: NSTextAlignment = .right

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.placeholder = placeholder
        textField.keyboardType = .decimalPad
        textField.textAlignment = textAlignment
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.delegate = context.coordinator

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Done", style: .prominent, target: textField, action: #selector(UITextField.resignFirstResponder))
        ]
        textField.inputAccessoryView = toolbar
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        textField.placeholder = placeholder
        textField.textAlignment = textAlignment
        if textField.text != text {
            textField.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            text = textField.text ?? ""
        }
    }
}

#Preview {
    WedgeMatrixView()
}
