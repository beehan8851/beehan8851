import Foundation
import os
import SwiftUI
import AlarmKit
import ActivityKit

// MARK: - Error

enum AlarmKitServiceError: LocalizedError {
    case notAuthorized
    case invalidOneTimeDate
    case rollbackFailed(underlying: any Error, rollback: any Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return String(
                localized: "Alarms & Timers permission is off. Open Settings → Dawnwick → Alarms & Timers to let alarms ring through Silent mode and Focus.",
                comment: "AlarmKit denied error"
            )
        case .invalidOneTimeDate:
            return String(localized: "The one-time alarm date could not be resolved.", comment: "AlarmKit invalid date")
        case .rollbackFailed(let underlying, _):
            return String(localized: "Alarm could not be updated: \(underlying.localizedDescription)", comment: "AlarmKit replace failure")
        }
    }
}

/// Production AlarmKit-backed alarm engine.
///
/// Replaces `AlarmNotificationService` for iOS 26+. Alarms are scheduled via
/// `AlarmKit.AlarmManager` which presents a system-level alert (overrides Focus
/// and ringer switch) and drives a Live Activity on the Lock Screen.
///
/// Both alert buttons route through App Intents (`StopAlarmMissionIntent` /
/// `OpenAlarmMissionIntent`) which record the pending mission in UserDefaults
/// and open the app, enforcing the wake-up challenge before the alarm is done.
///
/// Note: `AlarmKit.AlarmManager` shadows MorningCompanion's own `AlarmManager`,
/// so all AlarmKit references are fully qualified as `AlarmKit.AlarmManager`.
///
/// Replace semantics (F1 step 5): AlarmKit ids are unique, and re-scheduling an
/// id that already exists is not documented as an in-place update, so `register`
/// does cancel → schedule. If the schedule call throws after the cancel, the
/// previous AlarmKit schedule (captured before the cancel) is re-registered with
/// the same presentation so the user never silently loses an alarm.
final class AlarmKitAlarmService: AlarmEngineServiceProtocol {

    private let manager = AlarmKit.AlarmManager.shared

    // MARK: - AlarmEngineServiceProtocol

    func schedule(_ alarm: Alarm) async throws {
        guard alarm.isEnabled else {
            try await cancel(id: alarm.id)
            return
        }
        try await requireAuthorization()
        let schedule = try makeAlarmKitSchedule(for: alarm)
        try await register(alarm: alarm, id: alarm.id, schedule: schedule, isTest: false)
    }

    func scheduleReArm(for alarm: Alarm, reArmID: UUID, delay: TimeInterval) async throws {
        try await requireAuthorization()
        let fireDate = Date().addingTimeInterval(max(1, delay))
        let isTest = ReArmRegistry().entry(for: reArmID)?.kind == .test
        try await register(alarm: alarm, id: reArmID, schedule: .fixed(fireDate), isTest: isTest)
    }

    func cancel(id: UUID) async throws {
        if try manager.alarms.contains(where: { $0.id == id }) {
            try manager.cancel(id: id)
        }
    }

    func cancelAll() async throws {
        for alarm in try manager.alarms {
            try manager.cancel(id: alarm.id)
        }
    }

    /// Every id AlarmKit holds. Re-arm ids are filtered by `AlarmManager` via `ReArmRegistry`.
    func pendingAlarmIDs() async throws -> [UUID] {
        try manager.alarms.map(\.id)
    }

    func isAlerting(id: UUID) async -> Bool {
        guard let alarms = try? manager.alarms else { return false }
        return alarms.contains { $0.id == id && $0.state == .alerting }
    }

    // MARK: - Authorization

    var authorizationState: AlarmKitAuthorizationState {
        AlarmKitAuthorizationState(manager.authorizationState)
    }

    private func requireAuthorization() async throws {
        switch manager.authorizationState {
        case .authorized:
            return
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            if state != .authorized { throw AlarmKitServiceError.notAuthorized }
        case .denied:
            throw AlarmKitServiceError.notAuthorized
        @unknown default:
            throw AlarmKitServiceError.notAuthorized
        }
    }

    // MARK: - Helpers

    private func makeAlarmKitSchedule(for alarm: Alarm) throws -> AlarmKit.Alarm.Schedule {
        let time = AlarmKit.Alarm.Schedule.Relative.Time(
            hour: alarm.wallClockTime.hour,
            minute: alarm.wallClockTime.minute
        )
        switch alarm.recurrence {
        case .oneTime(let date):
            var comps = DateComponents()
            comps.year   = date.year
            comps.month  = date.month
            comps.day    = date.day
            comps.hour   = alarm.wallClockTime.hour
            comps.minute = alarm.wallClockTime.minute
            guard let fireDate = Calendar.current.date(from: comps) else {
                throw AlarmKitServiceError.invalidOneTimeDate
            }
            return .fixed(fireDate)
        case .daily:
            let allDays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            return .relative(.init(time: time, repeats: .weekly(allDays)))
        case .repeating(let days):
            if days.isEmpty {
                return .relative(.init(time: time, repeats: .never))
            }
            let localeWeekdays = days.sorted { $0.rawValue < $1.rawValue }.map(\.localeWeekday)
            return .relative(.init(time: time, repeats: .weekly(localeWeekdays)))
        }
    }

    private func makeConfiguration(
        alarm: Alarm,
        schedule: AlarmKit.Alarm.Schedule,
        isTest: Bool
    ) -> AlarmKit.AlarmManager.AlarmConfiguration<MCAlarmMetadata> {
        let title = alarm.label.isEmpty
            ? String(localized: "Wake up", comment: "Default alarm title")
            : alarm.label
        let openButton = AlarmButton(text: "Open", textColor: .white, systemImageName: "arrow.up.forward.app.fill")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
        }
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: MCAlarmMetadata(originalAlarmID: alarm.id.uuidString, label: alarm.label, isTest: isTest),
            tintColor: .orange
        )
        return AlarmKit.AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmMissionIntent(alarmID: alarm.id.uuidString),
            secondaryIntent: OpenAlarmMissionIntent(alarmID: alarm.id.uuidString),
            sound: alarmKitSound(for: alarm.sound)
        )
    }

    private func register(
        alarm: Alarm,
        id: UUID,
        schedule: AlarmKit.Alarm.Schedule,
        isTest: Bool
    ) async throws {
        let configuration = makeConfiguration(alarm: alarm, schedule: schedule, isTest: isTest)

        // Capture the previous registration so a failed replace can be rolled back.
        let previous = try? manager.alarms.first(where: { $0.id == id })
        do {
            if previous != nil {
                try manager.cancel(id: id)
            }
            let scheduled = try await manager.schedule(id: id, configuration: configuration)
            Log.alarm.info("AlarmKit scheduled id=\(id.uuidString, privacy: .public) state=\(String(describing: scheduled.state), privacy: .public) schedule=\(String(describing: schedule), privacy: .public)")
        } catch {
            Log.alarm.error("AlarmKit schedule FAILED id=\(id.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
            if let previousSchedule = previous?.schedule {
                do {
                    let rollback = makeConfiguration(alarm: alarm, schedule: previousSchedule, isTest: isTest)
                    _ = try await manager.schedule(id: id, configuration: rollback)
                    Log.alarm.warning("AlarmKit rolled back id=\(id.uuidString, privacy: .public) to its previous schedule")
                } catch let rollbackError {
                    Log.alarm.fault("AlarmKit rollback FAILED id=\(id.uuidString, privacy: .public) error=\(String(describing: rollbackError), privacy: .public)")
                    throw AlarmKitServiceError.rollbackFailed(underlying: error, rollback: rollbackError)
                }
            }
            throw error
        }
    }

    private func alarmKitSound(for sound: AlarmSound) -> AlertConfiguration.AlertSound {
        guard sound != .default,
              Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") != nil else {
            return .default
        }
        return .named("\(sound.rawValue).caf")
    }
}

// MARK: - Weekday mapping

private extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday:    return .sunday
        case .monday:    return .monday
        case .tuesday:   return .tuesday
        case .wednesday: return .wednesday
        case .thursday:  return .thursday
        case .friday:    return .friday
        case .saturday:  return .saturday
        }
    }
}
