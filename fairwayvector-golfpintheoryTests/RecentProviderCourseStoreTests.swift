import Foundation
import Testing
@testable import fairwayvector_golfpintheory

struct RecentProviderCourseStoreTests {
    @Test func recordsFiveMostRecentDistinctCoursesAndMovesReusedCourseToFront() throws {
        var data = Data()
        for number in 1...6 {
            data = RecentProviderCourseStore.recording(try reference(courseID: "course-\(number)", teeID: "tee-1"), in: data)
        }
        #expect(RecentProviderCourseStore.decode(data).map(\.golfAPICourseID) ==
            ["course-6", "course-5", "course-4", "course-3", "course-2"])

        data = RecentProviderCourseStore.recording(try reference(courseID: "course-4", teeID: "tee-red"), in: data)
        let updated = RecentProviderCourseStore.decode(data)
        #expect(updated.map(\.golfAPICourseID) ==
            ["course-4", "course-6", "course-5", "course-3", "course-2"])
        #expect(updated.first?.golfAPITeeID == "tee-red")
        #expect(updated.count == RecentProviderCourseStore.maximumCount)
    }

    private func reference(courseID: String, teeID: String) throws -> CourseReference {
        let value: [String: Any] = [
            "osmRelationID": NSNull(), "golfAPICourseID": courseID, "golfAPITeeID": teeID,
            "clubName": "Club", "courseName": courseID, "city": "", "region": "",
            "location": NSNull(), "holeCount": 18, "totalPar": 72, "teeName": "Blue",
            "teeSex": "male", "courseRating": 72.0, "slopeRating": 113
        ]
        return try JSONDecoder().decode(CourseReference.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
