import SwiftUI

private struct BagEditorSheet: View {
    enum Editor: String {
        case clubs
        case clubProfile
        case wedges
    }

    let editor: Editor
    @ObservedObject private var profileStore: PlayerProfileStore
    @ObservedObject private var unitPreferences: UnitPreferences
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draftProfileStore: PlayerProfileStore
    @State private var draftWedgeSetup: String

    init(editor: Editor, profileStore: PlayerProfileStore, unitPreferences: UnitPreferences,
         onSave: @escaping () -> Void) {
        self.editor = editor
        self.profileStore = profileStore
        self.unitPreferences = unitPreferences
        self.onSave = onSave
        let wedgeSetup = profileStore.storedWedgeSetup
        _draftProfileStore = StateObject(wrappedValue: PlayerProfileStore(
            draft: profileStore.profile, wedgeSetup: wedgeSetup))
        _draftWedgeSetup = State(initialValue: wedgeSetup)
    }

    private var hasChanges: Bool {
        draftProfileStore.profile != profileStore.profile || draftWedgeSetup != profileStore.storedWedgeSetup
    }

    var body: some View {
        NavigationStack {
            Group {
                switch editor {
                case .clubs:
                    BagClubsView(profileStore: draftProfileStore, storedWedges: $draftWedgeSetup)
                        .navigationTitle("Clubs in my bag")
                case .clubProfile:
                    TrajectoryProfileSettingsView(profileStore: draftProfileStore,
                        unitPreferences: unitPreferences)
                        .navigationTitle("Club distances & launch")
                case .wedges:
                    WedgeBagSetupView(profileStore: draftProfileStore, storedWedges: $draftWedgeSetup)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PureLineStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let profileChanged = profileStore.profile != draftProfileStore.profile
                        let oldWedges = Dictionary(Wedge.catalog(from: profileStore.storedWedgeSetup).map { ($0.name, $0) },
                            uniquingKeysWith: { first, _ in first })
                        let newWedges = Dictionary(Wedge.catalog(from: draftWedgeSetup).map { ($0.name, $0) },
                            uniquingKeysWith: { first, _ in first })
                        profileStore.profile = draftProfileStore.profile
                        profileStore.storedWedgeSetup = draftWedgeSetup
                        if profileChanged { profileStore.markClubProfileSaved() }
                        for name in Set(oldWedges.keys).union(newWedges.keys)
                            where oldWedges[name] != newWedges[name] {
                            profileStore.markWedgeSaved(name: name)
                        }
                        dismiss()
                        onSave()
                    }
                    .disabled(!hasChanges)
                }
            }
        }
        .tint(PureLineStyle.accent)
        .preferredColorScheme(.light)
    }
}

struct InTheBagView: View {
    private enum Editor: String, Identifiable {
        case clubs
        case clubProfile
        case wedges

        var id: String { rawValue }
    }

    @ObservedObject var trajectoryModel: TrajectoryCalculatorViewModel
    var onHome: () -> Void = {}
    var onSave: () -> Void = {}
    @State private var activeEditor: Editor?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PureLinePageHeader(
                        title: "Build your bag",
                        subtitle: "Choose the clubs you carry and set up your club and wedge distances."
                    )
                    .padding(.vertical, 18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Golf clubs")
                            .font(.headline)
                            .foregroundStyle(PureLineStyle.ink)
                        Text("Set the clubs available for trajectory and enter carry or launch details.")
                            .font(.caption)
                            .foregroundStyle(PureLineStyle.muted)
                        setupRow(
                            title: "Clubs in my bag",
                            detail: "Choose which clubs are available",
                            symbol: "figure.golf",
                            editor: .clubs
                        )
                        Divider().overlay(PureLineStyle.line)
                        setupRow(
                            title: "Club distances & launch",
                            detail: "Set personal club profiles",
                            symbol: "slider.horizontal.3",
                            editor: .clubProfile
                        )
                    }
                    .pureLineCard()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wedges")
                            .font(.headline)
                            .foregroundStyle(PureLineStyle.ink)
                        Text("Manage wedge inventory and individual carry distances.")
                            .font(.caption)
                            .foregroundStyle(PureLineStyle.muted)
                        setupRow(
                            title: "Wedge bag",
                            detail: "Add, edit, and select wedges in your bag",
                            symbol: "square.grid.3x3",
                            editor: .wedges
                        )
                    }
                    .pureLineCard()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .background(PureLineStyle.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                PureLineHomeButton(onHome: onHome)
            }
        }
        .tint(PureLineStyle.accent)
        .sheet(item: $activeEditor) { editor in
            BagEditorSheet(editor: BagEditorSheet.Editor(rawValue: editor.rawValue)!,
                profileStore: trajectoryModel.playerProfileStore,
                unitPreferences: trajectoryModel.unitPreferences,
                onSave: onSave)
        }
    }

    private func setupRow(title: String, detail: String, symbol: String, editor: Editor) -> some View {
        Button {
            activeEditor = editor
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PureLineStyle.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PureLineStyle.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(PureLineStyle.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PureLineStyle.muted)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
