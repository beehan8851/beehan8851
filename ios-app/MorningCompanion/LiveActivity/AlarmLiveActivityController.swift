import ActivityKit
import Foundation

enum AlarmLiveActivityResult: Sendable, Equatable {
    case started(activityID: String)
    case updated
    case ended
    case unsupported
    case activityNotFound
}

enum AlarmLiveActivityController {
    /// Starts (or, if one already exists for `alarmID`, updates) the custom alarm
    /// Live Activity. The app only ever starts it at alert time, so the default
    /// status is `.ringing` — showing "Scheduled" while the phone is ringing was
    /// audit §3 finding "custom LA shows Scheduled".
    @discardableResult
    static func start(
        alarmID: UUID,
        label: String,
        fireDate: Date,
        status: AlarmActivityAttributes.ContentState.Status = .ringing,
        snoozeCount: Int = 0
    ) throws -> AlarmLiveActivityResult {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .unsupported }

        let state = AlarmActivityAttributes.ContentState(
            fireDate: fireDate,
            status: status,
            snoozeCount: max(0, snoozeCount)
        )
        let content = ActivityContent(state: state, staleDate: fireDate.addingTimeInterval(60 * 60))

        if let existing = activity(for: alarmID) {
            Task { await existing.update(content) }
            return .updated
        }
        let attributes = AlarmActivityAttributes(alarmID: alarmID, label: label)
        let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        return .started(activityID: activity.id)
    }

    static func update(
        alarmID: UUID,
        fireDate: Date,
        status: AlarmActivityAttributes.ContentState.Status,
        snoozeCount: Int
    ) async -> AlarmLiveActivityResult {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .unsupported }
        guard let activity = activity(for: alarmID) else { return .activityNotFound }

        let state = AlarmActivityAttributes.ContentState(
            fireDate: fireDate,
            status: status,
            snoozeCount: max(0, snoozeCount)
        )
        await activity.update(ActivityContent(state: state, staleDate: fireDate.addingTimeInterval(60 * 60)))
        return .updated
    }

    static func end(
        alarmID: UUID,
        finalStatus: AlarmActivityAttributes.ContentState.Status = .dismissed
    ) async -> AlarmLiveActivityResult {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .unsupported }
        guard let activity = activity(for: alarmID) else { return .activityNotFound }

        let finalState = AlarmActivityAttributes.ContentState(
            fireDate: .now,
            status: finalStatus,
            snoozeCount: 0
        )
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        return .ended
    }

    private static func activity(for alarmID: UUID) -> Activity<AlarmActivityAttributes>? {
        Activity<AlarmActivityAttributes>.activities.first { $0.attributes.alarmID == alarmID }
    }
}
