import Foundation
import EventKit

final class EventKitCalendarService: CalendarServiceProtocol {
    // EKEventStore() is deferred until first use to avoid blocking app startup.
    // EKEventStore() involves calendar daemon IPC (~20-50ms on first call).
    private lazy var store = EKEventStore()

    func authorizationState() async -> ContextualPermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:    return .granted
        case .notDetermined: return .notDetermined
        // Write-only and restricted both mean no events can be read, which is what
        // this screen cares about.
        default:             return .unavailable
        }
    }

    func requestAuthorization() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .notDetermined else { return }
        let granted = try await store.requestFullAccessToEvents()
        if !granted { throw CalendarServiceError.denied }
    }

    func firstEventToday() async throws -> CalendarEventSummary? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let now = Date()
        let upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate >= now }
            .sorted { $0.startDate < $1.startDate }

        guard let event = upcoming.first else { return nil }
        return CalendarEventSummary(
            title: event.title ?? "",
            startDate: event.startDate,
            location: event.location
        )
    }
}

enum CalendarServiceError: LocalizedError {
    case denied
    var errorDescription: String? { "Calendar access was denied." }
}
