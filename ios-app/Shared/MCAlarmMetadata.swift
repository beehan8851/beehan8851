import AlarmKit
import Foundation

/// Metadata attached to every AlarmKit alarm the app schedules.
///
/// Lives in `Shared/` because the widget extension must name the exact same
/// type in `ActivityConfiguration(for: AlarmAttributes<MCAlarmMetadata>.self)`
/// for AlarmKit's own Live Activity (Lock Screen + Dynamic Island) to render.
struct MCAlarmMetadata: AlarmMetadata {
    /// Original alarm id (for re-arms this is the *original* alarm, not the re-arm id).
    var originalAlarmID: String?
    /// Human-readable label shown in the Live Activity.
    var label: String?
    /// True for the "Test alarm (30 s)" flow.
    var isTest: Bool

    init(originalAlarmID: String? = nil, label: String? = nil, isTest: Bool = false) {
        self.originalAlarmID = originalAlarmID
        self.label = label
        self.isTest = isTest
    }
}
