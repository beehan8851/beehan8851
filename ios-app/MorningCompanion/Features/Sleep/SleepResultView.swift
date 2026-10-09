import SwiftUI

struct SleepResultView: View {
    let session: SleepSession
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .center, spacing: DesignTokens.Spacing.xs) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Text(String(localized: "Total sleep", comment: "Total sleep duration label"))
                                .font(.system(.headline, weight: .bold))
                                .foregroundStyle(DesignTokens.Colors.onHeroSecondary)
                            Text(formattedDuration)
                                .mcScaledFont(48, weight: .heavy)
                                .foregroundStyle(DesignTokens.Colors.heroFigure)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        CatMascot(mood: .awake)
                            .frame(width: 96)
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .listRowBackground(DesignTokens.Colors.heroBand)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
                }

                Group {
                Section {
                    LabeledContent(String(localized: "Fell asleep", comment: "Sleep start time label")) {
                        Text(session.startDate, format: .dateTime.hour().minute())
                    }
                    if let end = session.endDate {
                        LabeledContent(String(localized: "Woke up", comment: "Sleep end time label")) {
                            Text(end, format: .dateTime.hour().minute())
                        }
                    }
                }

                if !session.noiseEvents.isEmpty {
                    Section {
                        ForEach(session.noiseEvents) { event in
                            LabeledContent {
                                Text(levelLabel(event.peakDecibels))
                            } label: {
                                Text(event.timestamp, format: .dateTime.hour().minute())
                            }
                        }
                    } header: {
                        Text(noiseEventTitle)
                    }
                }

                Section {
                    Label(session.soundUsed.displayName, systemImage: session.soundUsed.systemImage)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                }
                .mcRows()
            }
            .listStyle(.insetGrouped)
            .mcList()
            .font(.mcBody)
            .navigationTitle(String(localized: "Sleep recorded", comment: "Sleep result nav title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Dismiss sleep result"), action: onDismiss)
                }
            }
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        guard let d = session.duration else { return "—" }
        let mins = max(0, Int(d / 60))
        return String(localized: "\(mins / 60)h \(mins % 60)m", comment: "Sleep duration hours+minutes")
    }

    private var noiseEventTitle: String {
        let n = session.noiseEvents.count
        return n == 1
            ? String(localized: "1 noise event", comment: "One noise event")
            : String(localized: "\(n) noise events", comment: "Multiple noise events")
    }

    private func levelLabel(_ db: Float) -> String {
        if db > -20 { return String(localized: "Loud", comment: "Loud noise level") }
        if db > -35 { return String(localized: "Moderate", comment: "Moderate noise level") }
        return String(localized: "Soft", comment: "Soft noise level")
    }
}

#Preview {
    let session = SleepSession(startDate: .now.addingTimeInterval(-7 * 3600))
    var s = session
    s.endDate = .now
    s.noiseEvents = [
        NoiseEvent(timestamp: .now.addingTimeInterval(-5 * 3600), peakDecibels: -30),
        NoiseEvent(timestamp: .now.addingTimeInterval(-2 * 3600), peakDecibels: -25)
    ]
    return SleepResultView(session: s, onDismiss: {})
}
