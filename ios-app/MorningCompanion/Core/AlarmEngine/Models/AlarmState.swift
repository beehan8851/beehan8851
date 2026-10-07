import Foundation

enum AlarmState: Sendable, Equatable {
    case scheduled
    case firing
    case snoozed(until: Date)
    case dismissed
}
