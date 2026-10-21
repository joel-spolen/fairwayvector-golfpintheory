import SwiftData
import SwiftUI

struct HCPProjectionEntryView: View {
    var onHome: () -> Void = {}
    private let courseCatalog = CourseCatalogStore()

    var body: some View {
        HCPProjectionRootView(courseCatalog: courseCatalog, onHome: onHome)
    }
}

#Preview {
    HCPProjectionEntryView()
        .modelContainer(for: [PlayerProfile.self, GolfClub.self, GolfCourse.self, TeeSet.self, GolfRound.self],
                        inMemory: true)
}
