import ActivityKit
import SwiftUI
import WidgetKit

struct MorningCompanionSleepLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(Self.night)
                .activitySystemActionForegroundColor(Self.ember)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CatGlyph(mood: .sleeping, size: 28)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(String(localized: "Sleeping", comment: "Sleep Live Activity center label"))
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isActive {
                        Text(context.state.startDate, style: .timer)
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let alarmDate = context.state.nextAlarmDate {
                        HStack {
                            Image(systemName: "alarm")
                            Text(alarmDate, style: .time)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                CatGlyph(mood: .sleeping, size: 16)
            } compactTrailing: {
                if context.state.isActive {
                    Text(context.state.startDate, style: .timer)
                        .font(.caption2)
                        .monospacedDigit()
                }
            } minimal: {
                CatGlyph(mood: .sleeping, size: 14)
            }
        }
    }

    // Tokens the extension cannot import: ink and yolk.
    private static let night = Color(red: 0.106, green: 0.102, blue: 0.090)   // #1B1A17, ink
    private static let ember = Color(red: 1.0, green: 0.776, blue: 0.161)    // #FFC629, yolk

    private func lockScreenView(_ context: ActivityViewContext<SleepActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            CatGlyph(mood: .sleeping, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                if context.state.isActive {
                    Text(context.state.startDate, style: .timer)
                        .font(.headline.monospacedDigit())
                } else {
                    Text(String(localized: "Sleep ended", comment: "Sleep Live Activity ended"))
                        .font(.headline)
                }
                if let label = context.state.nextAlarmLabel, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let alarmDate = context.state.nextAlarmDate {
                    Text(alarmDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let alarmDate = context.state.nextAlarmDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(localized: "Alarm", comment: "Alarm label in sleep LA"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(alarmDate, style: .time)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding()
    }
}
