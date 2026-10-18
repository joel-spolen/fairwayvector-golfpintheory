import SwiftData
import SwiftUI

struct HCPProjectionEntryView: View {
    var onHome: () -> Void = {}
    private let courseCatalog = CourseCatalogStore()

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PlayerProfile.self,
            GolfClub.self,
            GolfCourse.self,
            TeeSet.self,
            GolfRound.self,
        ])
        let configuration = ModelConfiguration("hcpProjection", schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Never erase a user's handicap history to recover from a migration/storage error.
            fatalError("Could not open preserved HCP Projection store: \(error)")
        }
    }()

    var body: some View {
        HCPProjectionRootView(courseCatalog: courseCatalog, onHome: onHome)
    }
}

#Preview {
    HCPProjectionEntryView()
        .modelContainer(HCPProjectionEntryView.sharedModelContainer)
}
