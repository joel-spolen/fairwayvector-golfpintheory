import Combine
import Foundation

final class PlayerProfileStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let storageKey: String

    @Published var profile: TrajectoryPlayerProfile {
        didSet { saveProfile() }
    }

    var needsSetup: Bool {
        !profile.isSetupComplete
    }

    init(userDefaults: UserDefaults = .standard, storageKey: String = "playerProfile.active") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey

        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(TrajectoryPlayerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = TrajectoryPlayerProfile()
        }
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

    func isAvailable(for club: TrajectoryGolfClub) -> Bool {
        ClubProfileDefaults.isAvailable(for: club, playerProfile: profile, wedges: wedges)
    }

    private func saveProfile() {
        guard let encoded = try? JSONEncoder().encode(profile) else { return }
        userDefaults.set(encoded, forKey: storageKey)
    }
}