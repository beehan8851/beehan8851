import SwiftUI

// MARK: - Status page

/// The right page of an open Duo beside a screen that is one page: the next alarm,
/// large, and the cat saying how the night stands — what the closed phone's Today band
/// says, kept in view while you are elsewhere in the app. A bedside clock with a cat.
struct StatusPage: View {
    @State private var snapshot = WidgetSharedDataStore().read()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let next = snapshot?.nextAlarmDate.flatMap { $0 > context.date ? $0 : nil }
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: DesignTokens.Spacing.l)
                summary(next: next, now: context.date)
                Spacer(minLength: DesignTokens.Spacing.m)
                TappableCat(mood: mood(next: next, now: context.date), width: 150)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.bottom, DesignTokens.Spacing.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background.ignoresSafeArea())
        .inkTabBarClearance()
        // The app writes the snapshot whenever an alarm or the streak changes.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            snapshot = WidgetSharedDataStore().read()
        }
    }

    @ViewBuilder
    private func summary(next: Date?, now: Date) -> some View {
        if let next {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(NextAlarmPhrase.relativeDay(for: next).capitalized(with: .current))
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                AlarmTimeText(time: AlarmTime(from: next), size: 72, weight: .bold)
                Text(NextAlarmPhrase.ringsIn(next, now: now))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.accent)
                if let label = snapshot?.nextAlarmLabel {
                    Text(label)
                        .font(.mcCallout)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(String(localized: "No alarm set", comment: "Next alarm card, empty"))
                    .font(.mcTitle2)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(String(localized: "Tomorrow starts when you say so.", comment: "Next alarm card, empty, detail"))
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Today's mood rules, from what the snapshot knows: pleased once the morning is
    /// won, asleep on its moon while a night alarm is set, awake otherwise.
    private func mood(next: Date?, now: Date) -> CatMascot.Mood {
        if snapshot?.week?.contains(where: { $0.outcome == .won && Calendar.current.isDate($0.date, inSameDayAs: now) }) == true {
            return .proud
        }
        guard next != nil else { return .awake }
        let hour = Calendar.current.component(.hour, from: now)
        return (hour >= 19 || hour < 5) ? .sleeping : .awake
    }
}

// MARK: - One page beside the status page

extension View {
    /// Open on a Duo, a screen that is one page keeps to the left page, and the status
    /// page takes the right. The screen stays where it is in the hierarchy either way,
    /// so folding and opening keeps its navigation.
    func statusPageBeside() -> some View {
        modifier(StatusPageBeside())
    }
}

private struct StatusPageBeside: ViewModifier {
    @Environment(\.pageLayout) private var pageLayout

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content.frame(maxWidth: .infinity)
            if pageLayout == .spread {
                Color.clear.frame(width: PageLayout.gutter)
                StatusPage().frame(maxWidth: .infinity)
            }
        }
        .background(DesignTokens.Colors.background.ignoresSafeArea())
    }
}

// MARK: - Phrases

/// How the next alarm is said wherever it is shown.
enum NextAlarmPhrase {
    static func ringsIn(_ date: Date, now: Date) -> String {
        let minutes = max(1, Int(date.timeIntervalSince(now) / 60))
        if minutes < 60 {
            return String(localized: "Rings in \(minutes) min", comment: "Rings in minutes")
        }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0
            ? String(localized: "Rings in \(hours)h", comment: "Rings in hours")
            : String(localized: "Rings in \(hours)h \(rest)m", comment: "Rings in hours and minutes")
    }

    static func relativeDay(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return String(localized: "today", comment: "Relative day for next alarm, lowercase")
        }
        if Calendar.current.isDateInTomorrow(date) {
            return String(localized: "tomorrow", comment: "Relative day for next alarm, lowercase")
        }
        return date.formatted(.dateTime.weekday(.wide))
    }
}
