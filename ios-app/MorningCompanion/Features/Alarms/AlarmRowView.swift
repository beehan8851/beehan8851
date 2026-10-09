import SwiftUI

// MARK: - Recurrence display

extension AlarmRecurrence {
    var displaySummary: String {
        switch self {
        case .oneTime(let date):
            var comps = DateComponents()
            comps.year = date.year; comps.month = date.month; comps.day = date.day
            if let d = Calendar.current.date(from: comps) {
                return String(localized: "Once · \(d.formatted(.dateTime.month(.abbreviated).day()))", comment: "One-time alarm recurrence, with date")
            }
            return "\(date.month)/\(date.day)"
        case .repeating(let days):
            guard !days.isEmpty else { return String(localized: "No days set", comment: "Recurrence no days") }
            let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
            let weekends: Set<Weekday> = [.saturday, .sunday]
            if days == weekdays { return String(localized: "Weekdays", comment: "Recurrence weekdays") }
            if days == weekends { return String(localized: "Weekends", comment: "Recurrence weekends") }
            let order: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
            return order.filter { days.contains($0) }.map(\.shortName).joined(separator: " · ")
        case .daily:
            return String(localized: "Every day", comment: "Recurrence daily")
        }
    }
}

// MARK: - Row

/// One alarm as a row: the time, set large; what it is and when it repeats; then the
/// missions that turn it off, each with its symbol. A disabled alarm keeps its layout
/// and dims.
struct AlarmRowView: View {
    let alarm: Alarm
    let onTap: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    AlarmTimeText(time: alarm.wallClockTime, size: 44, weight: .semibold,
                                  color: alarm.isEnabled ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
                    Text(subtitle)
                        .font(.mcCallout)
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !alarm.missions.isEmpty {
                        missionLine
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(String(localized: "Opens the alarm", comment: "Alarm row hint"))

            Toggle(alarm.label.isEmpty ? String(localized: "Alarm", comment: "Toggle label fallback") : alarm.label,
                   isOn: Binding(get: { alarm.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(DesignTokens.Colors.accent)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    /// The missions in order, each as its symbol and name.
    private var missionLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(Array(alarm.missions.enumerated()), id: \.offset) { _, mission in
                    missionLabel(mission)
                }
            }
            Text(alarm.missions.map(\.displayName).joined(separator: ", "))
                .font(.mcFootnote)
                .foregroundStyle(ink)
                .lineLimit(2)
        }
    }

    private func missionLabel(_ mission: MissionConfig) -> some View {
        HStack(spacing: 5) {
            Image(systemName: mission.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(alarm.isEnabled ? DesignTokens.Colors.accent : DesignTokens.Colors.textTertiary)
            Text(mission.displayName)
                .font(.mcFootnoteSemibold)
                .foregroundStyle(ink)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var ink: Color {
        alarm.isEnabled ? DesignTokens.Colors.textSecondary : DesignTokens.Colors.textTertiary
    }

    /// "Wake up · Weekdays", or just the recurrence when the alarm has no label.
    private var subtitle: String {
        alarm.label.isEmpty
            ? alarm.recurrence.displaySummary
            : "\(alarm.label) · \(alarm.recurrence.displaySummary)"
    }
}

// MARK: - Next occurrence

private extension AlarmRowView {
    var nextOccurrenceText: String? {
        guard alarm.isEnabled,
              let date = NextAlarmCalculator.nextFireDate(for: alarm, after: .now, in: .current)
        else { return nil }
        let diff = date.timeIntervalSinceNow
        if diff < 3600 {
            let mins = max(1, Int(diff / 60))
            return String(localized: "in \(mins) min", comment: "Next alarm minutes")
        } else if diff < 24 * 3600 {
            let hours = Int(diff / 3600)
            let mins  = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
            return mins > 0
                ? String(localized: "in \(hours)h \(mins)m", comment: "Next alarm h+m")
                : String(localized: "in \(hours)h", comment: "Next alarm hours")
        } else {
            return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
        }
    }
}

// MARK: - Previews

#Preview("Enabled — multi-mission") {
    AlarmRowView(alarm: Alarm.samples[0], onTap: {}, onToggle: {})
        .padding().background(DesignTokens.Colors.background)
}

#Preview("Disabled") {
    AlarmRowView(alarm: Alarm.samples[1], onTap: {}, onToggle: {})
        .padding().background(DesignTokens.Colors.background)
}
