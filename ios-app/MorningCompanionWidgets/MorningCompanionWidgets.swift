import SwiftUI
import WidgetKit

@main
struct MorningCompanionWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        CatWidget()
        StreakWidget()
        SleepWidget()
        MorningCompanionAlarmLiveActivity()
        MorningCompanionAlarmKitLiveActivity()
        MorningCompanionSleepLiveActivity()
    }
}

// MARK: - Next alarm

/// The alarm, large, on yolk — with the missions that will turn it off and the cat
/// peeking in from the corner. Free: it is the app's face on the Home Screen, and
/// on the Lock Screen it is the one thing people check before they sleep.
struct NextAlarmWidget: Widget {
    let kind = WidgetSharedDataStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DawnwickProvider()) { entry in
            NextAlarmWidgetView(entry: entry)
                .containerBackground(for: .widget) { NextAlarmBackground() }
                .widgetURL(URL(string: "dawnwick://tab/alarms"))
        }
        .configurationDisplayName(String(localized: "Next Alarm", comment: "Widget gallery name"))
        .description(String(localized: "Your next alarm and the missions that turn it off.", comment: "Widget gallery description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct NextAlarmBackground: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch family {
        case .systemSmall, .systemMedium: WidgetTone(dark: colorScheme == .dark).surface
        default: Color.clear
        }
    }
}

private struct NextAlarmWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: DawnwickEntry

    private var tone: WidgetTone { WidgetTone(dark: colorScheme == .dark) }

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    /// Asleep on a night with an alarm, whatever the morning was; otherwise proud of a
    /// won morning, or simply awake.
    private var catMood: CatMascot.Mood {
        switch entry.mood {
        case .sleeping, .proud: entry.mood
        default: .awake
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let alarm = entry.nextAlarm {
                Text(widgetDayLabel(for: alarm, from: entry.date))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tone.secondary)
                WidgetBigTime(date: alarm, size: 38, color: tone.figure, periodColor: tone.secondary)
                    .padding(.top, 2)
                Text("in \(Text(alarm, style: .relative))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                missionDots
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            // In the corner, the whole of it inside the widget: into the content
            // margin, not past the edge.
            WidgetCat(mood: catMood, ground: tone.ground, width: catMood == .sleeping ? 72 : 64)
                .offset(x: 10, y: 10)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let alarm = entry.nextAlarm {
                    HStack(spacing: 6) {
                        Text(widgetDayLabel(for: alarm, from: entry.date))
                        if let label = entry.snapshot?.nextAlarmLabel {
                            Text(verbatim: "·")
                            Text(label).lineLimit(1)
                        }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tone.secondary)
                    WidgetBigTime(date: alarm, size: 46, color: tone.figure, periodColor: tone.secondary)
                        .padding(.top, 2)
                    Text("in \(Text(alarm, style: .relative))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tone.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    missionChips
                } else {
                    empty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(alignment: .bottomTrailing) {
            WidgetCat(mood: catMood, ground: tone.ground, width: catMood == .sleeping ? 140 : 108)
                .offset(x: 10, y: 10)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "No alarm set", comment: "Widget: no alarm"))
                .font(.system(size: 18, weight: .heavy).width(.expanded))
                .foregroundStyle(tone.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(String(localized: "Tap to set one.", comment: "Widget: no alarm, hint"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Ink discs with yolk symbols, one per mission, in order.
    private var missionDots: some View {
        HStack(spacing: 4) {
            ForEach(Array((entry.snapshot?.missions ?? []).prefix(3).enumerated()), id: \.offset) { _, mission in
                Image(systemName: mission.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tone.onChip)
                    .frame(width: 26, height: 26)
                    .background(tone.chip, in: Circle())
                    .accessibilityLabel(mission.name)
            }
        }
    }

    private var missionChips: some View {
        HStack(spacing: 5) {
            ForEach(Array((entry.snapshot?.missions ?? []).prefix(3).enumerated()), id: \.offset) { _, mission in
                HStack(spacing: 4) {
                    Image(systemName: mission.symbol)
                        .font(.system(size: 10, weight: .bold))
                    Text(mission.name)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(tone.onChip)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(tone.chip, in: Capsule())
            }
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let alarm = entry.nextAlarm {
                let parts = WidgetTimeParts(alarm)
                VStack(spacing: 0) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 10, weight: .bold))
                        .widgetAccentable()
                    Text(parts.time)
                        .font(.system(size: 15, weight: .heavy))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let period = parts.period {
                        Text(period).font(.system(size: 9, weight: .bold))
                    }
                }
                .padding(.horizontal, 4)
            } else {
                Image(systemName: "alarm")
                    .font(.system(size: 20, weight: .semibold))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            CatGlyph(mood: catMood == .sleeping ? .sleeping : .waiting, size: 30)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                if let alarm = entry.nextAlarm {
                    Text(widgetDayLabel(for: alarm, from: entry.date))
                        .font(.system(size: 11, weight: .semibold))
                    Text(alarm, format: .dateTime.hour().minute())
                        .font(.system(size: 20, weight: .heavy).width(.expanded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .widgetAccentable()
                    Text(missionLine)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                } else {
                    Text(String(localized: "No alarm set", comment: "Widget: no alarm"))
                        .font(.system(size: 14, weight: .bold))
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var inline: some View {
        if let alarm = entry.nextAlarm {
            let time = alarm.formatted(.dateTime.hour().minute())
            let missions = missionLine
            return Label(missions.isEmpty ? time : "\(time) · \(missions)", systemImage: "alarm.fill")
        }
        return Label(String(localized: "No alarm set", comment: "Widget: no alarm"), systemImage: "alarm")
    }

    private var missionLine: String {
        (entry.snapshot?.missions ?? []).map(\.name).joined(separator: " · ")
    }

    private var accessibilityText: String {
        guard let alarm = entry.nextAlarm else {
            return String(localized: "No alarm set", comment: "Widget: no alarm")
        }
        let time = alarm.formatted(.dateTime.weekday(.wide).hour().minute())
        return missionLine.isEmpty ? time : "\(time), \(missionLine)"
    }
}
