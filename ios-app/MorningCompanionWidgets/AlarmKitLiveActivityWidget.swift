import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// AlarmKit's own Live Activity for alarms scheduled by `AlarmKitAlarmService`.
///
/// Without an `ActivityConfiguration(for: AlarmAttributes<MCAlarmMetadata>.self)`
/// in the widget bundle, AlarmKit has nothing to render on the Lock Screen or in
/// the Dynamic Island while an alarm is scheduled/alerting (audit §3 P1). The
/// metadata type must be the exact one used when scheduling — it lives in Shared/.
struct MorningCompanionAlarmKitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<MCAlarmMetadata>.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(Self.night)
                .activitySystemActionForegroundColor(Self.moon)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CatGlyph(mood: isAlerting(context) ? .ringing : .waiting, size: 28)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(title(context))
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trailingTime(context)
                        .font(.headline)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(statusText(context))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isAlerting(context) {
                            Label(openHint, systemImage: "arrow.up.forward.app.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Self.moon)
                        }
                    }
                }
            } compactLeading: {
                CatGlyph(mood: isAlerting(context) ? .ringing : .waiting, size: 16)
            } compactTrailing: {
                trailingTime(context)
                    .font(.caption2)
                    .monospacedDigit()
            } minimal: {
                CatGlyph(mood: isAlerting(context) ? .ringing : .waiting, size: 14)
            }
        }
    }

    // MARK: - Views

    private func lockScreenView(_ context: ActivityViewContext<AlarmAttributes<MCAlarmMetadata>>) -> some View {
        HStack(spacing: 12) {
            CatGlyph(mood: isAlerting(context) ? .ringing : .waiting, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title(context))
                    .font(.headline)
                    .lineLimit(1)
                Text(isAlerting(context) ? openHint : statusText(context))
                    .font(.caption)
                    .foregroundStyle(isAlerting(context) ? AnyShapeStyle(Self.moon) : AnyShapeStyle(.secondary))
            }
            Spacer()
            trailingTime(context)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .padding()
    }

    @ViewBuilder
    private func trailingTime(_ context: ActivityViewContext<AlarmAttributes<MCAlarmMetadata>>) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
        case .paused:
            Text(String(localized: "Paused", comment: "AlarmKit LA paused"))
        case .alert:
            Text(Date.now, style: .time)
        @unknown default:
            Text(Date.now, style: .time)
        }
    }

    // MARK: - Helpers

    private var openHint: String {
        String(localized: "Open to complete your mission", comment: "AlarmKit LA open hint")
    }

    private func title(_ context: ActivityViewContext<AlarmAttributes<MCAlarmMetadata>>) -> String {
        if let label = context.attributes.metadata?.label, !label.isEmpty { return label }
        return String(localized: "Alarm", comment: "AlarmKit LA default title")
    }

    // Tokens the extension cannot import: ink and yolk.
    private static let night = Color(red: 0.106, green: 0.102, blue: 0.090)   // #1B1A17
    private static let moon = Color(red: 1.0, green: 0.776, blue: 0.161)      // #FFC629

    private func isAlerting(_ context: ActivityViewContext<AlarmAttributes<MCAlarmMetadata>>) -> Bool {
        if case .alert = context.state.mode { return true }
        return false
    }

    private func statusText(_ context: ActivityViewContext<AlarmAttributes<MCAlarmMetadata>>) -> String {
        switch context.state.mode {
        case .countdown: return String(localized: "Scheduled", comment: "AlarmKit LA scheduled")
        case .paused:    return String(localized: "Paused", comment: "AlarmKit LA paused")
        case .alert:     return String(localized: "Ringing", comment: "AlarmKit LA ringing")
        @unknown default: return ""
        }
    }
}
