import ActivityKit
import Foundation

enum SleepLiveActivityController {

    // MARK: - Start

    @discardableResult
    static func start(
        sessionID: UUID,
        startDate: Date,
        nextAlarmDate: Date?,
        nextAlarmLabel: String?
    ) throws -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }

        let attributes = SleepActivityAttributes(sessionID: sessionID)
        let state = SleepActivityAttributes.ContentState(
            startDate: startDate,
            nextAlarmDate: nextAlarmDate,
            nextAlarmLabel: nextAlarmLabel,
            isActive: true
        )
        let staleDate = startDate.addingTimeInterval(14 * 60 * 60)  // stale after 14 h
        let content = ActivityContent(state: state, staleDate: staleDate)
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        return activity.id
    }

    // MARK: - End

    static func end(sessionID: UUID) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let activity = Activity<SleepActivityAttributes>.activities
            .first(where: { $0.attributes.sessionID == sessionID }) else { return }

        let finalState = SleepActivityAttributes.ContentState(
            startDate: activity.content.state.startDate,
            nextAlarmDate: nil,
            nextAlarmLabel: nil,
            isActive: false
        )
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
    }
}
