import Combine
import Foundation

final class PlayerProfileStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let clubProfileModifiedAtKey: String?
    private let persistsProfile: Bool

    @Published var profile: TrajectoryPlayerProfile {
        didSet { saveProfile() }
    }

    var needsSetup: Bool {
        !profile.isSetupComplete
    }

    init(userDefaults: UserDefaults = .standard, storageKey: String = "playerProfile.active") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        clubProfileModifiedAtKey = "accountSync.clubProfileModifiedAt.v1"
        persistsProfile = true

        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(TrajectoryPlayerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = TrajectoryPlayerProfile()
        }
    }

    init(draft profile: TrajectoryPlayerProfile, wedgeSetup: String) {
        userDefaults = UserDefaults()
        storageKey = "playerProfile.draft"
        clubProfileModifiedAtKey = nil
        persistsProfile = false
        self.profile = profile
        userDefaults.set(wedgeSetup, forKey: "wedgeMatrix.wedges")
    }

    func update(_ transform: (inout TrajectoryPlayerProfile) -> Void) {
        var updated = profile
        transform(&updated)
        profile = updated
    }

    func effectiveProfile(for club: TrajectoryGolfClub) -> ClubLaunchProfile {
        ClubProfileDefaults.effectiveProfile(for: club, playerProfile: profile, wedges: wedges)
    }

    /// Resolve only from the injected store; never from an active/global account.
    var wedges: [Wedge] {
        Wedge.catalog(from: userDefaults.string(forKey: "wedgeMatrix.wedges") ?? "")
    }

    var storedWedgeSetup: String {
        get { userDefaults.string(forKey: "wedgeMatrix.wedges") ?? "" }
        set { userDefaults.set(newValue, forKey: "wedgeMatrix.wedges") }
    }

    var clubProfileModifiedAt: Date? {
        guard let clubProfileModifiedAtKey else { return nil }
        return userDefaults.object(forKey: clubProfileModifiedAtKey) as? Date
    }

    func markClubProfileSaved(at date: Date = Date()) {
        guard let clubProfileModifiedAtKey else { return }
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded(.down) / 1_000
        userDefaults.set(Date(timeIntervalSince1970: milliseconds), forKey: clubProfileModifiedAtKey)
    }

    func restoreClubProfileModifiedAt(_ date: Date) {
        guard let clubProfileModifiedAtKey else { return }
        userDefaults.set(date, forKey: clubProfileModifiedAtKey)
    }

    func wedgeModifiedAt(name: String) -> Date? {
        userDefaults.object(forKey: wedgeModifiedAtKey(name)) as? Date
    }

    func markWedgeSaved(name: String, at date: Date = Date()) {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded(.down) / 1_000
        userDefaults.set(Date(timeIntervalSince1970: milliseconds), forKey: wedgeModifiedAtKey(name))
    }

    func restoreWedgeModifiedAt(name: String, date: Date) {
        userDefaults.set(date, forKey: wedgeModifiedAtKey(name))
    }

    private func wedgeModifiedAtKey(_ name: String) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "accountSync.wedgeModifiedAt.v1.\(normalized)"
    }

    func isAvailable(for club: TrajectoryGolfClub) -> Bool {
        ClubProfileDefaults.isAvailable(for: club, playerProfile: profile, wedges: wedges)
    }

    private func saveProfile() {
        guard persistsProfile else { return }
        guard let encoded = try? JSONEncoder().encode(profile) else { return }
        userDefaults.set(encoded, forKey: storageKey)
    }
}