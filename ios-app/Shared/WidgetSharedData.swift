import Foundation
import WidgetKit

nonisolated struct WidgetSharedSnapshot: Codable, Sendable, Equatable {
    var nextAlarmDate: Date?
    var nextAlarmLabel: String?
    var streakDays: Int?
    var sleepDuration: TimeInterval?
    var updatedAt: Date
    /// The next alarm's missions, in order, already localized by the app.
    var missions: [WidgetMission]?
    /// This week, first weekday first, judged as the app judges it.
    var week: [WidgetDay]?
    var bestStreak: Int?
    /// Recent nights, oldest first, at most seven.
    var nights: [WidgetNight]?
    /// The day of the last won morning, and the days from the snapshot's own day
    /// on that have an alarm: what the widget needs to tell, days later and with the
    /// app never opened, whether a morning has been missed since.
    var lastWin: Date?
    var scheduledDays: [Date]?
    /// Covers the cat has left: missed mornings up to this many do not end the
    /// streak. `scheduledDays` leaves out the days already covered.
    var covers: Int?

    init(
        nextAlarmDate: Date? = nil,
        nextAlarmLabel: String? = nil,
        streakDays: Int? = nil,
        sleepDuration: TimeInterval? = nil,
        updatedAt: Date = .now,
        missions: [WidgetMission]? = nil,
        week: [WidgetDay]? = nil,
        bestStreak: Int? = nil,
        nights: [WidgetNight]? = nil,
        lastWin: Date? = nil,
        scheduledDays: [Date]? = nil,
        covers: Int? = nil
    ) {
        self.nextAlarmDate = nextAlarmDate
        self.nextAlarmLabel = nextAlarmLabel
        self.streakDays = streakDays
        self.sleepDuration = sleepDuration
        self.updatedAt = updatedAt
        self.missions = missions
        self.week = week
        self.bestStreak = bestStreak
        self.nights = nights
        self.lastWin = lastWin
        self.scheduledDays = scheduledDays
        self.covers = covers
    }
}

extension WidgetSharedSnapshot {
    /// How many days ahead `scheduledDays` reaches. Beyond it the widget keeps the
    /// streak; a fortnight with the app never opened is not the case to design for.
    static let scheduleHorizon = 14

    /// The streak the snapshot holds, unless a morning has been missed since it was
    /// written. The app writes the snapshot again on every win, so a scheduled day
    /// after the last win that is now over, with no newer snapshot, was not won — and
    /// a widget on a phone where the app has not been opened since would otherwise
    /// show the old streak for good. Today is still to play for.
    func liveStreak(at now: Date, calendar: Calendar = .current) -> Int {
        guard let days = streakDays, days > 0 else { return 0 }
        let today = calendar.startOfDay(for: now)
        if let lastWin, let scheduledDays {
            let won = calendar.startOfDay(for: lastWin)
            let missed = scheduledDays.filter { day in
                let day = calendar.startOfDay(for: day)
                return day > won && day < today
            }
            // As many as the cat can still cover for, and the streak stands.
            return missed.count > (covers ?? 0) ? 0 : days
        }
        // A snapshot from before these were written: judge by the next alarm alone.
        if let next = nextAlarmDate, calendar.startOfDay(for: next) < today { return 0 }
        return days
    }
}

nonisolated struct WidgetMission: Codable, Sendable, Equatable {
    var name: String
    var symbol: String
}

nonisolated struct WidgetDay: Codable, Sendable, Equatable {
    enum Outcome: String, Codable, Sendable { case won, missed, rest, covered, today, upcoming }
    var date: Date
    var outcome: Outcome
}

nonisolated struct WidgetNight: Codable, Sendable, Equatable {
    var date: Date
    var duration: TimeInterval
}

enum WidgetSharedDataError: LocalizedError {
    case appGroupUnavailable
    case encodingFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "The shared app-group container is unavailable."
        case .encodingFailed(let error):
            return "Widget data could not be encoded: \(error.localizedDescription)"
        }
    }
}

nonisolated struct WidgetSharedDataStore {
    static let appGroupIdentifier = "group.dev.numonov.dawnwick"
    static let widgetKind = "MorningCompanion.NextAlarm"
    static let catKind = "MorningCompanion.Cat"
    static let streakKind = "MorningCompanion.Streak"
    static let sleepKind = "MorningCompanion.Sleep"

    /// UserDefaults is documented thread-safe; see `ReArmRegistry` for the same pattern.
    nonisolated(unsafe) private let defaults: UserDefaults?
    private let storageKey = "widget.shared.snapshot.v1"

    init(appGroupIdentifier: String = Self.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    func read() -> WidgetSharedSnapshot? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSharedSnapshot.self, from: data)
    }

    func save(_ snapshot: WidgetSharedSnapshot) throws {
        guard let defaults else { throw WidgetSharedDataError.appGroupUnavailable }
        do {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: storageKey)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            throw WidgetSharedDataError.encodingFailed(error)
        }
    }

    func clear() {
        defaults?.removeObject(forKey: storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
