import Foundation

/// Which streak lengths earn a rating request, and which have already had one.
/// Each milestone asks once, ever, so a streak that breaks and is rebuilt to 7 does
/// not ask a second time.
enum ReviewMilestones {
    static let all = [3, 7, 30]
    private static let key = "com.morningcompanion.review.askedMilestones"

    /// The milestone `streak` has just reached, if it has not been asked for yet.
    static func due(for streak: Int, defaults: UserDefaults = .standard) -> Int? {
        guard all.contains(streak) else { return nil }
        return asked(in: defaults).contains(streak) ? nil : streak
    }

    static func markAsked(_ milestone: Int, defaults: UserDefaults = .standard) {
        defaults.set(Array(asked(in: defaults).union([milestone])).sorted(), forKey: key)
    }

    private static func asked(in defaults: UserDefaults) -> Set<Int> {
        Set(defaults.array(forKey: key) as? [Int] ?? [])
    }
}
