import Foundation

/// The computed next-fire information for a scheduled alarm.
/// Produced by NextAlarmCalculator and consumed by the alarm engine.
struct AlarmSchedule: Sendable {
    let alarm: Alarm
    let nextFireDate: Date
    let state: AlarmState
}
