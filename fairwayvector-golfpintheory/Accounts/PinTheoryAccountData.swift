import CryptoKit
import Foundation
import SwiftData

/// Local content for one authenticated project/user pair. Never opens or imports
/// the legacy unscoped stores. Opening errors propagate to the login gate.
@MainActor
final class PinTheoryAccountData: Identifiable {
    let id: String
    let defaults: UserDefaults
    let defaultsSuiteName: String
    let directory: URL
    let modelContainer: ModelContainer
    let roundsURL: URL
    let accountProfileURL: URL

    /// Permanently erases this account's saved rounds, active draft, SwiftData
    /// records and account-scoped preferences. Does not touch device preferences
    /// or any other account's directory.
    func eraseLocalContent() throws {
        let context = ModelContext(modelContainer)
        do {
            for profile in try context.fetch(FetchDescriptor<PlayerProfile>()) { context.delete(profile) }
            for club in try context.fetch(FetchDescriptor<GolfClub>()) { context.delete(club) }
            for course in try context.fetch(FetchDescriptor<GolfCourse>()) { context.delete(course) }
            for tee in try context.fetch(FetchDescriptor<TeeSet>()) { context.delete(tee) }
            for round in try context.fetch(FetchDescriptor<GolfRound>()) { context.delete(round) }
            try context.save()
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            guard defaults.synchronize() else { throw StorageError.defaultsWriteFailed }
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch { throw StorageError.localEraseFailed }
    }

    func loadAccountProfile() -> PinTheoryAccountDetails? {
        guard let data = try? Data(contentsOf: accountProfileURL),
              let profile = try? JSONDecoder().decode(CachedAccountProfile.self, from: data) else { return nil }
        return profile.details
    }

    func accountProfileCacheIsFresh(maxAge: TimeInterval = 24 * 60 * 60) -> Bool {
        guard let data = try? Data(contentsOf: accountProfileURL),
              let profile = try? JSONDecoder().decode(CachedAccountProfile.self, from: data) else { return false }
        let age = Date().timeIntervalSince(profile.updatedAt)
        return age >= 0 && age < maxAge
    }

    func saveAccountProfile(_ details: PinTheoryAccountDetails) throws {
        let profile = CachedAccountProfile(details: details)
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(profile)
            try data.write(to: accountProfileURL, options: .atomic)
        } catch { throw StorageError.accountProfileWriteFailed }
    }

    private struct CachedAccountProfile: Codable {
        let email: String?
        let pendingEmail: String?
        let providers: [String]
        let firstName: String
        let lastName: String
        let displayName: String
        let updatedAt: Date

        init(details: PinTheoryAccountDetails) {
            email = details.email
            pendingEmail = details.pendingEmail
            providers = details.providers
            firstName = details.firstName
            lastName = details.lastName
            displayName = details.displayName
            updatedAt = Date()
        }

        var details: PinTheoryAccountDetails {
            PinTheoryAccountDetails(email: email, pendingEmail: pendingEmail, providers: providers,
                                   firstName: firstName, lastName: lastName, displayName: displayName)
        }
    }

    enum StorageError: Error {
        case invalidProjectHost
        case defaultsUnavailable
        case defaultsWriteFailed
        case localEraseFailed
        case accountProfileWriteFailed
    }

    init(projectHost: String, userID: UUID, root: URL? = nil) throws {
        let host = projectHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !host.isEmpty, labels.allSatisfy({ label in
            !label.isEmpty && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { throw StorageError.invalidProjectHost }

        let projectID = SHA256.hash(data: Data(host.utf8)).map { String(format: "%02x", $0) }.joined()
        id = "\(projectID).\(userID.uuidString.lowercased())"
        directory = (root ?? URL.applicationSupportDirectory.appendingPathComponent("PinTheoryAccounts", isDirectory: true))
            .appendingPathComponent(projectID, isDirectory: true)
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
        roundsURL = directory.appendingPathComponent("rounds-v1.json")
        accountProfileURL = directory.appendingPathComponent("account-profile-v1.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let schema = Schema([PlayerProfile.self, GolfClub.self, GolfCourse.self, TeeSet.self, GolfRound.self])
        let configuration = ModelConfiguration("accountHCP", schema: schema,
            url: directory.appendingPathComponent("hcp.store"), cloudKitDatabase: .none)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])

        defaultsSuiteName = "com.fairwayvector.pintheory.account.\(id)"
        guard let scoped = UserDefaults(suiteName: defaultsSuiteName) else {
            throw StorageError.defaultsUnavailable
        }
        // A suite alone is NOT isolation: Foundation can search the legacy app
        // domain after it. Seed every content key in the *persistent suite*, not
        // registration defaults (which have lower priority than that fallback).
        // New account-content AppStorage keys must be added here as well.
        let emptyContent: [String: Any] = [
            "playerProfile.active": Data(),
            "wedgeMatrix.wedges": "",
            "customFlagPositions": "",
            "map.recentCourseReference": Data(),
            "map.development.recentCourseReference.v1": Data(),
            "hcp.provider.recentCourseReference.v1": Data(),
        ]
        let existing = scoped.persistentDomain(forName: defaultsSuiteName) ?? [:]
        for (key, value) in emptyContent where existing[key] == nil {
            scoped.set(value, forKey: key)
        }
        guard scoped.synchronize(), let persisted = scoped.persistentDomain(forName: defaultsSuiteName),
              emptyContent.keys.allSatisfy({ persisted[$0] != nil }) else {
            throw StorageError.defaultsWriteFailed
        }
        defaults = scoped
    }
}