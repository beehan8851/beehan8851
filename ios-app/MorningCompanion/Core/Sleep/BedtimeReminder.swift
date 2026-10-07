import Foundation

/// The nightly wind-down reminder, as it is stored.
///
/// Persisted because the notification it schedules is persisted: iOS keeps a repeating
/// request across launches, so a toggle that resets to off every launch would show the
/// user "off" while a reminder kept arriving every night.
struct BedtimeReminder: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    static let disabled = BedtimeReminder(isEnabled: false, hour: 22, minute: 30)

    var time: AlarmTime { AlarmTime(hour: hour, minute: minute) }

    /// Clamped on the way in, so a corrupt or hand-edited store cannot schedule a
    /// notification at hour 47 and silently do nothing.
    init(isEnabled: Bool, hour: Int, minute: Int) {
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }
}
