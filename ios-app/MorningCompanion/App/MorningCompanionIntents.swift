import AppIntents
import Foundation

/// UserDefaults bridge that carries an alarm ID from an AlarmKit alert-button
/// intent to the app process.
///
/// Uses the App Group suite so the write is visible to the main app even when
/// the intent runs in the extension/system process (i.e. when the app is killed).
/// Plain UserDefaults.standard is only shared within the same process, which
/// fails for the "app killed, intent fires, app relaunches" flow.
enum MissionHandoff {
    nonisolated static let suiteName = "group.dev.numonov.dawnwick"
    nonisolated static let key = "com.morningcompanion.pendingMissionAlarmID"

    nonisolated private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    nonisolated static func set(_ alarmID: String) {
        defaults.set(alarmID, forKey: key)
    }

    /// Reads and clears the pending id in one atomic operation.
    nonisolated static func take() -> UUID? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return UUID(uuidString: raw)
    }

    nonisolated static func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// Wired to the AlarmKit alert's secondary "Open" button. Launches the app and
/// records the pending mission so the wake-up challenge is enforced on entry.
struct OpenAlarmMissionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open Dawnwick"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        MissionHandoff.set(alarmID)
        return .result()
    }
}

/// Wired to the AlarmKit alert's "Stop" button. AlarmKit silences the alert
/// automatically; the intent additionally records the pending mission so the
/// alarm can't be dismissed from the system alert without completing the
/// wake-up challenge.
struct StopAlarmMissionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete morning mission"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        MissionHandoff.set(alarmID)
        return .result()
    }
}
