import SwiftUI
import WidgetKit

// MARK: - Palette

/// Yolk & Ink, as the widgets need it. The extension shares no design tokens with the
/// app, so the handful of colours live here, by the same names.
enum WidgetInk {
    static let yolk = Color(red: 1.0, green: 0.776, blue: 0.161)          // #FFC629
    static let ink = Color(red: 0.106, green: 0.102, blue: 0.090)         // #1B1A17
    static let paper = Color(red: 0.957, green: 0.949, blue: 0.929)       // #F4F2ED
    static let onYolkSecondary = Color(red: 0.373, green: 0.306, blue: 0.110) // #5F4E1C
    static let nightText = Color(red: 0.957, green: 0.949, blue: 0.929)   // #F4F2ED
    static let nightSecondary = Color(red: 0.659, green: 0.639, blue: 0.604)  // #A8A39A
    static let nightTertiary = Color(red: 0.431, green: 0.416, blue: 0.388)   // #6E6A63
    static let paperSecondary = Color(red: 0.420, green: 0.400, blue: 0.369)  // #6B665E
    static let missed = Color(red: 0.851, green: 0.333, blue: 0.259)
    /// Ink raised a step, for a widget on a dark Home Screen.
    static let inkRaised = Color(red: 0.133, green: 0.125, blue: 0.114)  // #22201D
}

/// Yolk with ink type on a light Home Screen; ink with yolk figures on a dark one,
/// where a block of yellow is the brightest thing on the screen.
struct WidgetTone {
    let dark: Bool
    var surface: Color { dark ? WidgetInk.inkRaised : WidgetInk.yolk }
    var primary: Color { dark ? WidgetInk.nightText : WidgetInk.ink }
    var secondary: Color { dark ? WidgetInk.nightSecondary : WidgetInk.onYolkSecondary }
    /// The one big figure: the time, the streak.
    var figure: Color { dark ? WidgetInk.yolk : WidgetInk.ink }
    /// A small disc or chip, and what sits on it.
    var chip: Color { dark ? WidgetInk.yolk : WidgetInk.ink }
    var onChip: Color { dark ? WidgetInk.ink : WidgetInk.yolk }
    var ground: CatMascot.Ground { dark ? .dark : .light }
}

// MARK: - Entry and timeline

struct DawnwickEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSharedSnapshot?
    var isPremium: Bool = true

    var nextAlarm: Date? {
        guard let date = snapshot?.nextAlarmDate, date > self.date else { return nil }
        return date
    }

    /// This week as of the entry's own date, so a timeline entry past midnight does
    /// not still call yesterday "today".
    func outcome(on day: Date, calendar: Calendar = .current) -> WidgetDay.Outcome? {
        guard let cell = snapshot?.week?.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) else { return nil }
        let today = calendar.startOfDay(for: date)
        if cell.outcome == .today, cell.date < today { return .rest }
        if cell.outcome == .upcoming, calendar.isDate(cell.date, inSameDayAs: date) { return .today }
        return cell.outcome
    }

    var wokeToday: Bool { outcome(on: date) == .won }

    /// The cat's mood. On a night with an alarm it is asleep, whatever the morning
    /// was; otherwise the rules Today uses: a won morning, then a missed one.
    var mood: CatMascot.Mood {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        if nextAlarm != nil, hour >= 19 || hour < 5 { return .sleeping }
        if wokeToday { return .proud }
        let today = calendar.startOfDay(for: date)
        let judged = (snapshot?.week ?? [])
            .filter { $0.date <= today }
            .compactMap { outcome(on: $0.date) }
            .filter { $0 == .won || $0 == .missed }
        if judged.last == .missed { return .grumpy }
        return .awake
    }

    var streak: Int { snapshot?.liveStreak(at: date) ?? 0 }
}

/// One provider for every widget: the shared snapshot, plus extra entries at the
/// moments the picture changes on its own — midnight, five in the morning, seven
/// in the evening and the alarm itself.
struct DawnwickProvider: TimelineProvider {
    /// Widgets that are Premium show a locked face to free users.
    var requiresPremium = false

    private let store = WidgetSharedDataStore()
    private let entitlements = SubscriptionEntitlementCache()

    func placeholder(in context: Context) -> DawnwickEntry {
        DawnwickEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DawnwickEntry) -> Void) {
        // The gallery always shows the widget at its best.
        if context.isPreview {
            completion(DawnwickEntry(date: .now, snapshot: store.read() ?? .sample))
            return
        }
        completion(DawnwickEntry(date: .now, snapshot: store.read(), isPremium: premium))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DawnwickEntry>) -> Void) {
        let now = Date()
        let snapshot = store.read()
        let isPremium = premium
        let horizon = now.addingTimeInterval(12 * 3600)
        let calendar = Calendar.current
        var moments: [Date] = [now]
        for hour in [0, 5, 19] {
            if let next = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime),
               next < horizon {
                moments.append(next)
            }
        }
        if let alarm = snapshot?.nextAlarmDate, alarm > now, alarm < horizon {
            moments.append(alarm.addingTimeInterval(1))
        }
        let entries = moments.sorted().map { DawnwickEntry(date: $0, snapshot: snapshot, isPremium: isPremium) }
        completion(Timeline(entries: entries, policy: .after(horizon)))
    }

    private var premium: Bool { !requiresPremium || entitlements.isPremium() }
}

extension WidgetSharedSnapshot {
    /// What the gallery and the placeholder show: a good week.
    static var sample: WidgetSharedSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let week: [WidgetDay] = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let outcome: WidgetDay.Outcome = day < today ? (offset == 5 ? .rest : .won) : (day == today ? .won : .upcoming)
            return WidgetDay(date: day, outcome: outcome)
        }
        let nights: [WidgetNight] = (1...7).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back + 1, to: today) else { return nil }
            return WidgetNight(date: day, duration: [7.4, 6.2, 7.9, 6.8, 8.1, 7.0, 7.4][back - 1] * 3600)
        }
        var alarm = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today) ?? today
        if alarm < .now { alarm = calendar.date(byAdding: .day, value: 1, to: alarm) ?? alarm }
        return WidgetSharedSnapshot(
            nextAlarmDate: alarm,
            nextAlarmLabel: nil,
            streakDays: 12,
            sleepDuration: 7.4 * 3600,
            missions: [
                WidgetMission(name: String(localized: "Math", comment: "Mission kind"), symbol: "plus.forwardslash.minus"),
                WidgetMission(name: String(localized: "Shake", comment: "Mission kind"), symbol: "iphone.radiowaves.left.and.right"),
            ],
            week: week,
            bestStreak: 21,
            nights: nights
        )
    }
}

// MARK: - Shared pieces

/// A time split the way the app sets it: big digits, a small AM/PM where the
/// locale keeps one.
struct WidgetTimeParts {
    let time: String
    let period: String?
    let periodFirst: Bool

    init(_ date: Date) {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        let format = formatter.dateFormat ?? "HH:mm"
        guard format.contains("a") else {
            time = formatter.string(from: date)
            period = nil
            periodFirst = false
            return
        }
        periodFirst = format.trimmingCharacters(in: .whitespaces).hasPrefix("a")
        period = Calendar.current.component(.hour, from: date) < 12 ? formatter.amSymbol : formatter.pmSymbol
        formatter.dateFormat = format.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        time = formatter.string(from: date)
    }
}

struct WidgetBigTime: View {
    let date: Date
    var size: CGFloat
    var color: Color
    var periodColor: Color

    var body: some View {
        let parts = WidgetTimeParts(date)
        HStack(alignment: .firstTextBaseline, spacing: size * 0.08) {
            if let period = parts.period, parts.periodFirst { periodText(period) }
            Text(parts.time)
                .font(.system(size: size, weight: .heavy).width(.expanded))
                .tracking(-size * 0.02)
                .foregroundStyle(color)
            if let period = parts.period, !parts.periodFirst { periodText(period) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private func periodText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: max(11, size * 0.32), weight: .bold))
            .foregroundStyle(periodColor)
    }
}

/// "Today", "Tomorrow" or the weekday of the next alarm.
func widgetDayLabel(for date: Date, from now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) {
        return String(localized: "Today", comment: "Widget: the alarm rings later today")
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
        return String(localized: "Tomorrow", comment: "Widget: the alarm rings tomorrow")
    }
    return date.formatted(.dateTime.weekday(.wide))
}

/// The cat, drawn in full on the Home Screen, and as the little head silhouette
/// where the system tints the widget.
struct WidgetCat: View {
    let mood: CatMascot.Mood
    let ground: CatMascot.Ground
    var width: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            CatMascot(mood: mood, ground: ground, animated: false)
                .frame(width: width)
        } else {
            CatGlyph(mood: glyphMood, size: width * 0.6)
                .widgetAccentable()
        }
    }

    private var glyphMood: CatGlyph.Mood {
        switch mood {
        case .sleeping: .sleeping
        case .ringing: .ringing
        default: .waiting
        }
    }
}

/// The week as paw prints: a paw for a won morning, a cross for a missed one, a dot
/// for rest, a dashed ring for today.
struct WidgetPawWeek: View {
    let entry: DawnwickEntry
    var glyph: CGFloat = 14
    var showLetters = false
    var won: Color = WidgetInk.yolk
    var quiet: Color = WidgetInk.nightTertiary
    var letters: Color = WidgetInk.nightSecondary

    var body: some View {
        let days = entry.snapshot?.week ?? []
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 4) {
                    if showLetters {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Calendar.current.isDate(day.date, inSameDayAs: entry.date) ? won : letters)
                    }
                    glyphView(entry.outcome(on: day.date) ?? .upcoming)
                        .frame(width: glyph, height: glyph)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "This week", comment: "Widget: the week of paw prints, VoiceOver"))
    }

    @ViewBuilder
    private func glyphView(_ outcome: WidgetDay.Outcome) -> some View {
        switch outcome {
        case .won:
            PawPrintShape().fill(won).widgetAccentable()
        case .missed:
            Image(systemName: "xmark")
                .font(.system(size: glyph * 0.6, weight: .heavy))
                .foregroundStyle(WidgetInk.missed)
        case .rest:
            Circle().fill(quiet).frame(width: glyph * 0.28, height: glyph * 0.28)
        case .covered:
            PawPrintShape().stroke(won, lineWidth: 1.2).widgetAccentable()
        case .today:
            Circle()
                .strokeBorder(won, style: StrokeStyle(lineWidth: 1.6, dash: [2.6, 2.6]))
                .frame(width: glyph * 0.9, height: glyph * 0.9)
        case .upcoming:
            Circle().fill(quiet.opacity(0.6)).frame(width: glyph * 0.2, height: glyph * 0.2)
        }
    }
}

/// What a Premium widget shows a free user: what it is and where to unlock it.
struct WidgetLockedFace: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    private var tone: WidgetTone { WidgetTone(dark: colorScheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(String(localized: "Premium", comment: "Widget: locked badge"), systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tone.secondary)
                Spacer()
                CatGlyph(mood: .waiting, size: 26)
            }
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 17, weight: .heavy).width(.expanded))
                .foregroundStyle(tone.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(String(localized: "Open Dawnwick to unlock.", comment: "Widget: locked, how to unlock"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

func formattedSleep(_ duration: TimeInterval) -> String {
    let minutes = max(0, Int(duration / 60))
    return String(localized: "\(minutes / 60)h \(minutes % 60)m", comment: "Duration format")
}
