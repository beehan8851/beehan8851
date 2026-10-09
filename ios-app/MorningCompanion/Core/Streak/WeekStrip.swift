import SwiftUI

// MARK: - Outcome

/// What one calendar day did for the streak.
enum DayOutcome: Equatable, Sendable {
    /// The mission was completed.
    case won
    /// An alarm was set and the mission was not completed.
    case missed
    /// No alarm that day. Rest days do not break a streak.
    case rest
    /// An alarm was set and the mission was not completed, but the cat covered for
    /// it: the streak went on.
    case covered
    /// Today, before the alarm has fired (or with no alarm).
    case today
    /// Later this week.
    case upcoming
}

struct DayCell: Identifiable, Equatable, Sendable {
    let date: Date
    let outcome: DayOutcome
    var id: Date { date }
}

// MARK: - Strip

/// Seven days, starting on the locale's first weekday, each a `DayGlyph`.
struct WeekStrip: View {
    let days: [DayCell]
    var calendar: Calendar = .current

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: DesignTokens.Spacing.xs) {
                    let isToday = calendar.isDateInToday(day.date)
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.system(.caption, weight: isToday ? .heavy : .semibold))
                        .foregroundStyle(isToday ? DesignTokens.Colors.accent : DesignTokens.Colors.textSecondary)
                    DayGlyph(outcome: day.outcome)
                        .frame(width: 26, height: 26)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: day))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "This week", comment: "Week strip accessibility label"))
    }

    private func accessibilityLabel(for day: DayCell) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide))
        switch day.outcome {
        case .won:      return String(localized: "\(weekday), woke up", comment: "Week strip day, VoiceOver")
        case .missed:   return String(localized: "\(weekday), missed", comment: "Week strip day, VoiceOver")
        case .rest:     return String(localized: "\(weekday), rest day", comment: "Week strip day, VoiceOver")
        case .covered:  return String(localized: "\(weekday), the cat covered for you", comment: "Week strip day, VoiceOver: a missed morning a streak cover saved")
        case .today:    return String(localized: "\(weekday), today", comment: "Week strip day, VoiceOver")
        case .upcoming: return String(localized: "\(weekday), upcoming", comment: "Week strip day, VoiceOver")
        }
    }
}

// MARK: - Glyph

/// The small state mark used by the week strip and the monthly calendar. Each state
/// has its own shape, so it reads without colour: a paw print for a morning won (the
/// cat walked across your week in ink), a cross for one missed, the paw print in
/// outline for one the cat covered (its paw, not yours), a small dot for rest, a
/// dashed ring for today, still waiting for its paw.
struct DayGlyph: View {
    let outcome: DayOutcome

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                switch outcome {
                case .won:
                    PawPrintShape()
                        .fill(DesignTokens.Colors.streakFlame)
                        .frame(width: d * 0.9, height: d * 0.9)
                case .missed:
                    Image(systemName: "xmark")
                        .font(.system(size: d * 0.4, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.streakMissed)
                case .rest:
                    Circle().fill(DesignTokens.Colors.streakRest).frame(width: d * 0.24, height: d * 0.24)
                case .covered:
                    PawPrintShape()
                        .stroke(DesignTokens.Colors.streakFlame, lineWidth: max(1.2, d * 0.06))
                        .frame(width: d * 0.84, height: d * 0.84)
                case .today:
                    Circle()
                        .strokeBorder(DesignTokens.Colors.accent, style: StrokeStyle(lineWidth: 2, dash: [3.2, 3.2]))
                        .frame(width: d * 0.82, height: d * 0.82)
                case .upcoming:
                    Circle().fill(DesignTokens.Colors.textDisabled).frame(width: d * 0.18, height: d * 0.18)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Building the week

extension DayCell {
    /// The current week as the strip shows it, using the calendar's first weekday.
    ///
    /// - `record`: which days were won, and which the cat covered for. Pass it
    ///   `settled(on:)`, so a cover due today shows before it is saved.
    /// - `alarms`: which days had an alarm, so a quiet day reads as rest rather than a
    ///   miss. Past days are judged by today's alarms — the app does not keep a diary
    ///   of schedule changes, and a week of history is not worth one.
    static func currentWeek(
        record: StreakRecord,
        alarms: [Alarm],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DayCell] {
        let today = calendar.startOfDay(for: now)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let outcome: DayOutcome
            if record.isCompleted(day, calendar: calendar) {
                outcome = .won
            } else if record.isCovered(day, calendar: calendar) {
                outcome = .covered
            } else if day == today {
                outcome = .today
            } else if day > today {
                outcome = .upcoming
            } else if alarms.contains(where: { $0.isEnabled && $0.recurrence.occurs(on: day, calendar: calendar) }) {
                outcome = .missed
            } else {
                outcome = .rest
            }
            return DayCell(date: day, outcome: outcome)
        }
    }
}

extension DayCell {
    /// Every day of the month containing `now`, judged the same way as the week.
    static func month(
        containing now: Date = .now,
        record: StreakRecord,
        alarms: [Alarm],
        calendar: Calendar = .current
    ) -> [DayCell] {
        let today = calendar.startOfDay(for: now)
        guard let interval = calendar.dateInterval(of: .month, for: today),
              let count = calendar.range(of: .day, in: .month, for: today)?.count else { return [] }
        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let outcome: DayOutcome
            if record.isCompleted(day, calendar: calendar) {
                outcome = .won
            } else if record.isCovered(day, calendar: calendar) {
                outcome = .covered
            } else if day == today {
                outcome = .today
            } else if day > today {
                outcome = .upcoming
            } else if alarms.contains(where: { $0.isEnabled && $0.recurrence.occurs(on: day, calendar: calendar) }) {
                outcome = .missed
            } else {
                outcome = .rest
            }
            return DayCell(date: day, outcome: outcome)
        }
    }
}

extension AlarmRecurrence {
    /// Whether this recurrence has an occurrence on the given calendar day.
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily:
            return true
        case .repeating(let days):
            guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { return false }
            return days.contains(weekday)
        case .oneTime(let date):
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            return c.year == date.year && c.month == date.month && c.day == date.day
        }
    }
}

// MARK: - Preview

#Preview {
    let cal = Calendar.current
    let start = cal.dateInterval(of: .weekOfYear, for: .now)!.start
    let outcomes: [DayOutcome] = [.won, .won, .missed, .rest, .today, .upcoming, .upcoming]
    let cells = outcomes.enumerated().map { i, o in
        DayCell(date: cal.date(byAdding: .day, value: i, to: start)!, outcome: o)
    }
    return WeekStrip(days: cells)
        .padding()
        .background(DesignTokens.Colors.background)
}
