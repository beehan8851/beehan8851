import UIKit

/// Every haptic the app plays, in one place, so the Haptics switch in Settings
/// actually turns them off.
///
/// It did not. The preference was stored and read back correctly, and forty-odd call
/// sites went straight to `UIImpactFeedbackGenerator` without ever consulting it — a
/// setting that silently does nothing, which is worse than not offering it. Rather
/// than thread the settings store into every view that buzzes, `AppPreferences` keeps
/// this flag in step with itself.
///
/// No exceptions, including while an alarm is ringing: the ring screen already
/// honoured the setting, and buzzing someone who switched it off is not a decision
/// worth overriding them on.
@MainActor
enum Haptics {
    /// Mirrors `AppPreferences.hapticsEnabled`; kept in step by that type.
    static var isEnabled = true

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
