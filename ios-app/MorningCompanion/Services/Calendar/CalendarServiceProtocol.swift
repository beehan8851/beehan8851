import Foundation

protocol CalendarServiceProtocol {
    /// The calendar permission's state, read without prompting.
    func authorizationState() async -> ContextualPermissionState
    func requestAuthorization() async throws
    func firstEventToday() async throws -> CalendarEventSummary?
}

struct CalendarEventSummary: Codable, Sendable {
    let title: String
    let startDate: Date
    let location: String?
}

/// Preview stub — returns a realistic sample event.
final class StubCalendarService: CalendarServiceProtocol {
    func authorizationState() async -> ContextualPermissionState { .granted }
    func requestAuthorization() async throws {}
    func firstEventToday() async throws -> CalendarEventSummary? {
        CalendarEventSummary(
            title: "Team Standup",
            startDate: Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: Date()) ?? Date(),
            location: nil
        )
    }
}
