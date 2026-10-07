import ActivityKit
import Foundation

struct SleepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var startDate: Date
        var nextAlarmDate: Date?
        var nextAlarmLabel: String?
        var isActive: Bool
    }

    var sessionID: UUID
}
