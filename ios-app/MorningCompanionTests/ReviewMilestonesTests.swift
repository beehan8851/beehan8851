import Foundation
import Testing
@testable import MorningCompanion

@Suite("Review milestones")
struct ReviewMilestonesTests {
    private func freshDefaults() -> UserDefaults {
        let name = "review-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test("Only the milestone days ask")
    func onlyMilestones() {
        let defaults = freshDefaults()
        #expect(ReviewMilestones.due(for: 1, defaults: defaults) == nil)
        #expect(ReviewMilestones.due(for: 3, defaults: defaults) == 3)
        #expect(ReviewMilestones.due(for: 4, defaults: defaults) == nil)
        #expect(ReviewMilestones.due(for: 7, defaults: defaults) == 7)
    }

    @Test("Each milestone asks once, even after the streak is rebuilt")
    func asksOnce() {
        let defaults = freshDefaults()
        ReviewMilestones.markAsked(3, defaults: defaults)
        #expect(ReviewMilestones.due(for: 3, defaults: defaults) == nil)
        #expect(ReviewMilestones.due(for: 7, defaults: defaults) == 7)
    }
}

@Suite("Count phrase")
struct CountPhraseTests {
    @Test("Number first")
    func numberFirst() {
        let p = CountPhrase("5 дней подряд", count: 5)
        #expect(p.before.isEmpty)
        #expect(p.number == "5")
        #expect(p.after == "дней подряд")
    }

    @Test("Number in the middle, no spaces")
    func numberInside() {
        let zh = CountPhrase("连续 12 天", count: 12)
        #expect([zh.before, zh.number, zh.after] == ["连续", "12", "天"])
        let ja = CountPhrase("12日連続", count: 12)
        #expect([ja.before, ja.number, ja.after] == ["", "12", "日連続"])
    }

    @Test("A translation without the number keeps all its words")
    func noNumber() {
        let p = CountPhrase("days in a row", count: 3)
        #expect(p.number == "3")
        #expect(p.after == "days in a row")
    }
}
