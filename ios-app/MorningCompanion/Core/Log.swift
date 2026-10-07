import Foundation
import os

/// Central place for the app's `os.Logger` instances, one per subsystem area.
///
/// Usage: `Log.alarm.info("Scheduled alarm \(id, privacy: .public)")`.
/// Logs are visible in Console.app filtered by the `subsystem` below and never
/// end up in a release build's stdout the way `print` does.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "MorningCompanion"

    /// App lifecycle, bootstrap, scene-phase transitions.
    static let app = Logger(subsystem: subsystem, category: "App")
    /// AlarmKit / notification scheduling and alarm engine state.
    static let alarm = Logger(subsystem: subsystem, category: "Alarm")
    /// Persistence: envelopes, repositories, migrations.
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    /// Wake-up missions.
    static let missions = Logger(subsystem: subsystem, category: "Missions")
    /// Weather, calendar, health integrations.
    static let services = Logger(subsystem: subsystem, category: "Services")
}
