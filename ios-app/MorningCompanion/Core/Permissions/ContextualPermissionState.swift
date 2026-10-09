import Foundation

/// Whether a permission the app can live without has been decided yet.
///
/// The three states are what the UI actually has to tell apart: ask (but only when the
/// user says so), show the thing, or explain that it is off. Whether "off" means denied,
/// restricted or missing hardware changes nothing a person can act on, so it is one case.
enum ContextualPermissionState: Equatable, Sendable {
    /// Never asked. The screen offers, and the system prompt waits for a tap.
    case notDetermined
    case granted
    /// Denied, restricted, or unavailable on this device. iOS will not prompt again.
    case unavailable
}
