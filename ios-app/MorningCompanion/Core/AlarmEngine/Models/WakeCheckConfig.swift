import Foundation

struct WakeCheckConfig: Codable, Sendable, Equatable {
    /// Minutes after mission success before the "Still awake?" prompt appears.
    /// 0 means wake check is disabled.
    var durationMinutes: Int

    static let off = WakeCheckConfig(durationMinutes: 0)

    var isEnabled: Bool { durationMinutes > 0 }
    var durationSeconds: TimeInterval { TimeInterval(durationMinutes * 60) }

    static let durationOptions: [Int] = [0, 3, 5, 10]

    var durationLabel: String {
        durationMinutes == 0
            ? String(localized: "Off", comment: "Wake check disabled")
            : "\(durationMinutes) min"
    }
}
