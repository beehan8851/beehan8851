import SwiftUI

struct SleepReportView: View {
    let localSessions: [SleepSession]
    let healthEntries: [SleepEntry]

    private var combinedDays: [DaySleepSummary] {
        DaySleepSummary.merge(sessions: localSessions, healthEntries: healthEntries)
    }

    private var averageDuration: TimeInterval? {
        let values = combinedDays.compactMap(\.duration)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        content
        .background(DesignTokens.Colors.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Sleep History", comment: "Sleep report nav title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        if combinedDays.isEmpty {
            emptyState
        } else {
            reportList
        }
    }

    // MARK: - Report list

    private var reportList: some View {
        List {
            Section {
                barChartSection
            }
            .mcRows()

            if let avg = averageDuration {
                Section(String(localized: "Average", comment: "Average sleep section")) {
                    HStack {
                        Text(String(localized: "Per night", comment: "Average sleep label; the value is a duration"))
                            .font(.mcBody)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        Spacer()
                        Text(formattedDuration(avg))
                            .font(.mcHeadline)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                    .listRowBackground(DesignTokens.Colors.surfacePrimary)
                    .accessibilityElement(children: .combine)
                }
            }

            Section(String(localized: "Recent Nights", comment: "Recent sleep nights section")) {
                ForEach(combinedDays) { day in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.date, format: .dateTime.weekday(.wide).month().day())
                                .font(.mcSubhead)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            if let source = day.sourceLabel {
                                Text(source)
                                    .font(.mcCaption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                        }
                        Spacer()
                        if let d = day.duration {
                            Text(formattedDuration(d))
                                .font(.mcCallout)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        } else {
                            Text("—")
                                .font(.mcCallout)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                    .listRowBackground(DesignTokens.Colors.surfacePrimary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .mcList()
    }

    // MARK: - Bar chart (the last seven calendar days)

    /// Seven slots, oldest to newest, ending today. A night without data is an empty
    /// slot, not a missing bar — a single tracked night used to stretch across the
    /// whole chart as one anonymous block.
    private var week: [(date: Date, duration: TimeInterval?)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let match = combinedDays.first { cal.isDate($0.date, inSameDayAs: day) }
            return (day, match?.duration)
        }
    }

    /// Eight hours is the fixed ceiling, so a bar's height means the same thing every
    /// week and a short night looks short. A longer night raises the ceiling for all.
    private var chartCeiling: TimeInterval {
        Swift.max(8 * 3600, week.compactMap(\.duration).max() ?? 0)
    }

    private static let barArea: CGFloat = 96

    private var barChartSection: some View {
        let ceiling = chartCeiling
        let guide = 8 * 3600 / ceiling
        return VStack(spacing: DesignTokens.Spacing.xs) {
            ZStack(alignment: .bottom) {
                // The eight-hour rule, and its label.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Rectangle()
                            .fill(DesignTokens.Colors.separator)
                            .frame(height: 1)
                        Text(String(localized: "8h", comment: "Sleep chart guide line, eight hours"))
                            .font(.mcEyebrow)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                        .frame(height: Self.barArea * guide)
                }
                .frame(height: Self.barArea)
                .accessibilityHidden(true)

                HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xs) {
                    ForEach(week, id: \.date) { slot in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(slot.duration == nil ? DesignTokens.Colors.streakRest : DesignTokens.Colors.streakFlame)
                            .frame(height: barHeight(duration: slot.duration, ceiling: ceiling))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(barLabel(slot))
                    }
                }
                .padding(.trailing, 28) // room for the guide label
                .frame(height: Self.barArea, alignment: .bottom)
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(week, id: \.date) { slot in
                    Text(slot.date, format: .dateTime.weekday(.narrow))
                        .font(.mcEyebrow)
                        .foregroundStyle(Calendar.current.isDateInToday(slot.date)
                                         ? DesignTokens.Colors.textPrimary
                                         : DesignTokens.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, 28)
            .accessibilityHidden(true)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Last seven nights", comment: "Sleep chart accessibility label"))
    }

    private func barHeight(duration: TimeInterval?, ceiling: TimeInterval) -> CGFloat {
        guard let d = duration, ceiling > 0 else { return 4 }
        return Swift.max(4, CGFloat(d / ceiling) * Self.barArea)
    }

    private func barLabel(_ slot: (date: Date, duration: TimeInterval?)) -> String {
        let day = slot.date.formatted(.dateTime.weekday(.wide))
        if let d = slot.duration {
            return String(localized: "\(day), \(formattedDuration(d))", comment: "Sleep chart bar, VoiceOver")
        }
        return String(localized: "\(day), no sleep recorded", comment: "Sleep chart bar without data, VoiceOver")
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No sleep history yet", comment: "Empty sleep report title"), systemImage: "bed.double")
        } description: {
            Text(String(localized: "Track your first session or connect Apple Health to see your history here.", comment: "Empty sleep report message"))
        }
    }

    // MARK: - Formatting

    private func formattedDuration(_ d: TimeInterval) -> String {
        let mins = max(0, Int(d / 60))
        return String(localized: "\(mins / 60)h \(mins % 60)m", comment: "Duration hours+minutes")
    }
}

// MARK: - Day summary model

struct DaySleepSummary: Identifiable {
    let date: Date
    let duration: TimeInterval?
    let sourceLabel: String?

    var id: Date { date }

    /// Merges local tracked sessions and HealthKit entries into one list, a night per
    /// entry. A night belongs to the **morning it ended on** — Health already dates its
    /// entries that way, and it is the day you mean by "last night". Keying by the
    /// evening a session started used to fold two nights into one whenever someone
    /// went to bed before midnight one day and after it the next.
    static func merge(sessions: [SleepSession], healthEntries: [SleepEntry], calendar cal: Calendar = .current) -> [DaySleepSummary] {
        var byWakeDay: [Date: DaySleepSummary] = [:]

        for entry in healthEntries {
            let day = cal.startOfDay(for: entry.date)
            byWakeDay[day] = DaySleepSummary(
                date: day,
                duration: entry.duration,
                sourceLabel: String(localized: "Apple Health", comment: "HealthKit data source")
            )
        }

        // Local sessions override or supplement HealthKit for the same night.
        for session in sessions {
            guard let d = session.duration, let end = session.endDate else { continue }
            let day = cal.startOfDay(for: end)
            // Prefer the longer of the two for the same night.
            if let existing = byWakeDay[day], let ed = existing.duration, ed >= d { continue }
            byWakeDay[day] = DaySleepSummary(
                date: day,
                duration: d,
                sourceLabel: String(localized: "Tracked", comment: "Locally tracked sleep source")
            )
        }

        return byWakeDay.values.sorted { $0.date > $1.date }
    }
}

#Preview {
    NavigationStack {
        SleepReportView(localSessions: [], healthEntries: [])
    }
    .environment(AppContainer.preview())
}
