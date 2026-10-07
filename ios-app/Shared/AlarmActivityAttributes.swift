import ActivityKit
import Foundation

struct AlarmActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Status: String, Codable, Hashable, Sendable {
            case scheduled
            case ringing
            case snoozed
            case dismissed
        }

        var fireDate: Date
        var status: Status
        var snoozeCount: Int
    }

    var alarmID: UUID
    var label: String
}
