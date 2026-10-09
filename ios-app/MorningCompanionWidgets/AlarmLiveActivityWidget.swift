import ActivityKit
import SwiftUI
import WidgetKit

struct MorningCompanionAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(Self.night)
                .activitySystemActionForegroundColor(Self.ember)
        } dynamicIsland: { context in
            DynamicIsland {
                // The expanded island puts its regions hard against the cutout's edge;
                // a little breathing room keeps the cat and the status text inside it.
                DynamicIslandExpandedRegion(.leading) {
                    CatGlyph(mood: context.state.status == .ringing ? .ringing : .waiting, size: 28)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.fireDate, style: .time)
                        .font(.headline)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(activityTitle(context))
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(statusText(context.state.status))
                        Spacer()
                        if context.state.snoozeCount > 0 {
                            Text(String(localized: "Snoozed \(context.state.snoozeCount)×", comment: "Alarm Live Activity snooze count"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                CatGlyph(mood: context.state.status == .ringing ? .ringing : .waiting, size: 16)
            } compactTrailing: {
                Text(context.state.fireDate, style: .time)
                    .font(.caption2)
            } minimal: {
                CatGlyph(mood: context.state.status == .ringing ? .ringing : .waiting, size: 14)
            }
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<AlarmActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            CatGlyph(mood: context.state.status == .ringing ? .ringing : .waiting, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(activityTitle(context))
                    .font(.headline)
                    .lineLimit(1)
                Text(statusText(context.state.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(context.state.fireDate, style: .time)
                .font(.title3.weight(.semibold))
        }
        .padding()
    }

    // Tokens the extension cannot import: ink and yolk.
    private static let night = Color(red: 0.106, green: 0.102, blue: 0.090)   // #1B1A17, ink
    private static let ember = Color(red: 1.0, green: 0.776, blue: 0.161)    // #FFC629, yolk

    private func activityTitle(_ context: ActivityViewContext<AlarmActivityAttributes>) -> String {
        context.attributes.label.isEmpty
            ? String(localized: "Alarm", comment: "Alarm Live Activity title when the alarm has no label")
            : context.attributes.label
    }

    private func statusText(_ status: AlarmActivityAttributes.ContentState.Status) -> String {
        switch status {
        case .scheduled: return String(localized: "Scheduled", comment: "Alarm Live Activity status")
        case .ringing:   return String(localized: "Ringing", comment: "Alarm Live Activity status")
        case .snoozed:   return String(localized: "Snoozed", comment: "Alarm Live Activity status")
        case .dismissed: return String(localized: "Dismissed", comment: "Alarm Live Activity status")
        }
    }
}
