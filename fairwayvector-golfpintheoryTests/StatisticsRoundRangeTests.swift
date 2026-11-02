import Foundation
import Testing
@testable import fairwayvector_golfpintheory

@MainActor
struct StatisticsRoundRangeTests {
    private func rounds(_ days: [Int]) -> [RoundPerformanceRecord] {
        days.map { day in
            RoundPerformanceRecord(id: "round-\(day)", date: Date(timeIntervalSince1970: Double(day) * 86_400),
                title: "Course", holes: 18, gross: nil, adjustedGross: nil, differential: nil, played: nil, handicap: nil)
        }
    }

    @Test func keepsTheLatestRoundsInDateOrder() {
        let selected = StatisticsRoundRange.last5.apply(rounds([7, 1, 3, 9, 2, 8, 5]))
        #expect(selected.map(\.id) == ["round-3", "round-5", "round-7", "round-8", "round-9"])
    }

    @Test func allAndShortHistoriesKeepEveryRound() {
        let history = rounds([4, 2, 6])
        #expect(StatisticsRoundRange.all.apply(history).map(\.id) == ["round-2", "round-4", "round-6"])
        #expect(StatisticsRoundRange.last20.apply(history).count == 3)
    }
}
