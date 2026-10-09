import SwiftUI
import WidgetKit

// MARK: - Cat

/// The cat on the Home Screen, living the same day you do: asleep on its moon on a
/// night with an alarm, proud after a won morning, grumpy after a missed one, awake
/// otherwise. Free — it is the mascot, and the reason someone keeps the widget.
struct CatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedDataStore.catKind, provider: DawnwickProvider()) { entry in
            CatWidgetView(entry: entry)
                .containerBackground(for: .widget) { CatWidgetBackground(mood: entry.mood) }
                .widgetURL(URL(string: "dawnwick://tab/today"))
        }
        .configurationDisplayName(String(localized: "Cat", comment: "Widget gallery name"))
        .description(String(localized: "The cat sleeps when you do and celebrates your mornings.", comment: "Widget gallery description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Yolk by day, paper when grumpy, ink while it sleeps — and ink on a dark Home
/// Screen whatever its mood.
private struct CatWidgetBackground: View {
    let mood: CatMascot.Mood
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            WidgetInk.inkRaised
        } else {
            switch mood {
            case .sleeping: WidgetInk.ink
            case .grumpy: WidgetInk.paper
            default: WidgetInk.yolk
            }
        }
    }
}

private struct CatWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: DawnwickEntry

    private var onInk: Bool { entry.mood == .sleeping || colorScheme == .dark }
    private var ground: CatMascot.Ground { onInk ? .dark : .light }
    private var primary: Color { onInk ? WidgetInk.nightText : WidgetInk.ink }
    private var secondary: Color {
        if onInk { return WidgetInk.nightSecondary }
        return entry.mood == .grumpy ? WidgetInk.paperSecondary : WidgetInk.onYolkSecondary
    }

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(spacing: 6) {
            WidgetCat(mood: entry.mood, ground: ground, width: entry.mood == .sleeping ? 128 : 92)
                .frame(maxHeight: .infinity)
            Text(line)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var medium: some View {
        HStack(spacing: 12) {
            WidgetCat(mood: entry.mood, ground: ground, width: entry.mood == .sleeping ? 150 : 108)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text(line)
                    .font(.system(size: 17, weight: .heavy).width(.expanded))
                    .foregroundStyle(primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What the cat has to say for itself.
    private var line: String {
        switch entry.mood {
        case .sleeping:
            if let alarm = entry.nextAlarm {
                let time = alarm.formatted(date: .omitted, time: .shortened)
                return String(localized: "Asleep. Up at \(time).", comment: "Cat widget: night, the alarm time follows")
            }
            return String(localized: "Asleep.", comment: "Cat widget: night")
        case .proud:
            return entry.streak > 0
                ? String(localized: "Morning won. Day \(entry.streak).", comment: "Cat widget: the mission was done today; streak day")
                : String(localized: "Morning won.", comment: "Cat widget: the mission was done today")
        case .grumpy:
            return String(localized: "Missed one. Tomorrow counts.", comment: "Cat widget: the last morning was missed")
        case .awake, .ringing, .startled, .sad, .yawning:
            return entry.nextAlarm != nil
                ? String(localized: "Ready for tonight.", comment: "Cat widget: daytime, an alarm is set")
                : String(localized: "No alarm yet.", comment: "Cat widget: no alarm is set")
        }
    }

    private var detail: String? {
        if entry.mood != .sleeping, let alarm = entry.nextAlarm {
            let time = alarm.formatted(date: .omitted, time: .shortened)
            return "\(widgetDayLabel(for: alarm, from: entry.date)) · \(time)"
        }
        if entry.streak > 0, entry.mood != .proud {
            return CountPhrase(String(localized: "\(entry.streak) days in a row", comment: "Streak on Today and Progress: the number is set large and the words small beside it. Keep the number in the text; the app cuts the phrase where it sits."), count: entry.streak)
                .joined
        }
        return nil
    }
}

// MARK: - Streak

/// Ink for the Premium widgets; their locked face is yolk on a light Home Screen.
private struct PremiumWidgetBackground: View {
    let locked: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            WidgetInk.inkRaised
        } else {
            locked ? WidgetInk.yolk : WidgetInk.ink
        }
    }
}

/// The streak, in yolk on ink, with the week as paw prints. Premium.
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedDataStore.streakKind, provider: DawnwickProvider(requiresPremium: true)) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(for: .widget) { PremiumWidgetBackground(locked: !entry.isPremium) }
                .widgetURL(URL(string: entry.isPremium ? "dawnwick://tab/streak" : "dawnwick://tab/settings"))
        }
        .configurationDisplayName(String(localized: "Streak", comment: "Widget gallery name"))
        .description(String(localized: "Your streak and this week, one paw per morning.", comment: "Widget gallery description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DawnwickEntry

    var body: some View {
        if !entry.isPremium {
            WidgetLockedFace(title: String(localized: "Streak", comment: "Widget gallery name"))
        } else if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    private var phrase: CountPhrase {
        CountPhrase(
            String(localized: "\(entry.streak) days in a row", comment: "Streak on Today and Progress: the number is set large and the words small beside it. Keep the number in the text; the app cuts the phrase where it sits."),
            count: entry.streak
        )
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(String(localized: "Streak", comment: "Widget gallery name"), systemImage: "pawprint.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WidgetInk.nightSecondary)
            number(size: 52)
            Spacer(minLength: 0)
            WidgetPawWeek(entry: entry, glyph: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Label(String(localized: "Streak", comment: "Widget gallery name"), systemImage: "pawprint.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetInk.nightSecondary)
                number(size: 60)
                Spacer(minLength: 0)
                if let best = entry.snapshot?.bestStreak {
                    Text(String(localized: "Best \(best)", comment: "Progress streak card: the longest streak so far"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WidgetInk.nightSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack {
                Spacer(minLength: 0)
                WidgetPawWeek(entry: entry, glyph: 18, showLetters: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The number large in yolk, the words small beside it, in whatever order the
    /// language puts them.
    private func number(size: CGFloat) -> some View {
        let p = phrase
        return VStack(alignment: .leading, spacing: 0) {
            if !p.before.isEmpty { words(p.before) }
            Text(p.number)
                .font(.system(size: size, weight: .heavy).width(.expanded))
                .foregroundStyle(WidgetInk.yolk)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !p.after.isEmpty { words(p.after) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.joined)
    }

    private func words(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(WidgetInk.nightText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Sleep

/// Last night and the week's nights as bars, on the night colours — with a way into
/// the wind-down on the larger size. Premium.
struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedDataStore.sleepKind, provider: DawnwickProvider(requiresPremium: true)) { entry in
            SleepWidgetView(entry: entry)
                .containerBackground(for: .widget) { PremiumWidgetBackground(locked: !entry.isPremium) }
                .widgetURL(URL(string: entry.isPremium ? "dawnwick://tab/sleep" : "dawnwick://tab/settings"))
        }
        .configurationDisplayName(String(localized: "Sleep", comment: "Widget gallery name"))
        .description(String(localized: "Last night, the week's nights, and the way into a calmer bedtime.", comment: "Widget gallery description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SleepWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DawnwickEntry

    private var nights: [WidgetNight] { entry.snapshot?.nights ?? [] }
    private var lastNight: TimeInterval? {
        guard let last = nights.last,
              entry.date.timeIntervalSince(last.date) < 36 * 3600 else { return entry.snapshot?.sleepDuration }
        return last.duration
    }

    var body: some View {
        if !entry.isPremium {
            WidgetLockedFace(title: String(localized: "Sleep", comment: "Widget gallery name"))
        } else if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            lastNightText(size: 28)
            Spacer(minLength: 0)
            bars(height: 40, letters: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                header
                lastNightText(size: 30)
                if let average {
                    Text(String(localized: "Average \(formattedSleep(average))", comment: "Sleep widget: average over the shown nights"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetInk.nightSecondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Link(destination: URL(string: "dawnwick://wind-down")!) {
                    Label(String(localized: "Wind down", comment: "Wind-down screen title"), systemImage: "wind")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WidgetInk.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(WidgetInk.yolk, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            bars(height: 92, letters: true)
                .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        Label(String(localized: "Last night", comment: "Sleep screen section: last night"), systemImage: "moon.zzz.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(WidgetInk.nightSecondary)
    }

    @ViewBuilder
    private func lastNightText(size: CGFloat) -> some View {
        if let lastNight {
            Text(formattedSleep(lastNight))
                .font(.system(size: size, weight: .heavy).width(.expanded))
                .foregroundStyle(WidgetInk.nightText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 4)
        } else {
            Text(String(localized: "No nights yet", comment: "Sleep widget: nothing recorded"))
                .font(.system(size: 16, weight: .heavy).width(.expanded))
                .foregroundStyle(WidgetInk.nightText)
                .padding(.top, 4)
        }
    }

    private var average: TimeInterval? {
        guard nights.count > 1 else { return nil }
        return nights.map(\.duration).reduce(0, +) / Double(nights.count)
    }

    /// The last seven days, a bar for each night that has one and a dot for each
    /// that does not, against a nine-hour scale; last night in full yolk.
    private func bars(height: CGFloat, letters: Bool) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(days, id: \.self) { day in
                let night = nights.last { calendar.isDate($0.date, inSameDayAs: day) }
                VStack(spacing: 3) {
                    if let night {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(WidgetInk.yolk.opacity(day == today ? 1 : 0.4))
                            .frame(width: letters ? 14 : 11, height: max(4, height * min(night.duration / (9 * 3600), 1)))
                            .widgetAccentable()
                    } else {
                        Circle()
                            .fill(WidgetInk.nightTertiary)
                            .frame(width: 4, height: 4)
                    }
                    if letters {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(day == today ? WidgetInk.yolk : WidgetInk.nightSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + (letters ? 16 : 0), alignment: .bottom)
        .accessibilityHidden(true)
    }
}
