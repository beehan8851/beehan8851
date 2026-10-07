import Foundation

/// What was on someone's mind at bedtime, left for the morning. It is written into
/// that morning's Focus on Today, so the thought has somewhere to be that is not
/// their head.
enum WindDownNote {
    /// The morning the note is for: the day the next alarm rings when there is one
    /// within the day, otherwise tomorrow — or today, after midnight and before five.
    static func morning(now: Date = .now, nextAlarm: Date?, calendar: Calendar = .current) -> Date {
        if let nextAlarm, nextAlarm > now, nextAlarm.timeIntervalSince(now) < 24 * 3600 {
            return calendar.startOfDay(for: nextAlarm)
        }
        let today = calendar.startOfDay(for: now)
        if calendar.component(.hour, from: now) < 5 { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// Adds `text` to that morning's Focus, under anything already there. Returns
    /// false when there was nothing to save or the save failed.
    @discardableResult
    static func park(
        _ text: String,
        in storage: any StorageServiceProtocol,
        now: Date = .now,
        nextAlarm: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return false }
        let key = MorningBriefViewModel.focusStorageKey(
            for: morning(now: now, nextAlarm: nextAlarm, calendar: calendar),
            calendar: calendar
        )
        let existing = ((try? storage.load(key: key)) as String?)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = existing.isEmpty ? note : existing + "\n" + note
        do {
            try storage.save(combined, key: key)
            return true
        } catch {
            return false
        }
    }
}
