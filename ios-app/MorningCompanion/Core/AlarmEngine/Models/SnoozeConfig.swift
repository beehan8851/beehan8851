import Foundation

struct SnoozeConfig: Codable, Sendable, Equatable {
    /// Snooze interval in minutes. 0 means snooze is disabled.
    var durationMinutes: Int
    /// Maximum snoozes per alarm cycle. -1 = unlimited. 0 = off (follows durationMinutes = 0).
    var maxCount: Int

    static let `default` = SnoozeConfig(durationMinutes: 5, maxCount: 2)
    static let off        = SnoozeConfig(durationMinutes: 0, maxCount: 0)

    var isEnabled: Bool       { durationMinutes > 0 }
    var isUnlimited: Bool     { maxCount == -1 }
    var durationSeconds: TimeInterval { TimeInterval(durationMinutes * 60) }

    var maxCountDisplayLabel: String {
        switch maxCount {
        case -1: return String(localized: "Unlimited", comment: "Unlimited snooze count")
        case 0:  return String(localized: "Off",       comment: "Snooze off")
        default: return "\(maxCount)"
        }
    }

    static let durationOptions: [Int] = [0, 3, 5, 10]
    static let maxCountOptions:  [Int] = [1, 2, 3, -1]

    func label(for count: Int) -> String {
        if maxCount == -1 { return "" }
        let remaining = maxCount - count
        if remaining <= 0 { return String(localized: "No snoozes left", comment: "Snooze exhausted") }
        return remaining == 1
            ? String(localized: "Last snooze", comment: "Final snooze remaining")
            : String(localized: "\(remaining) snoozes left", comment: "Snooze count remaining")
    }
}
