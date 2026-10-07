import Observation
import SwiftUI

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System", comment: "System appearance option")
        case .light: return String(localized: "Light", comment: "Light appearance option")
        case .dark: return String(localized: "Dark", comment: "Dark appearance option")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
@Observable
final class AppPreferences {
    var defaultAlarmSound: AlarmSound {
        didSet { save(defaultAlarmSound, key: Keys.defaultAlarmSound) }
    }
    var hapticsEnabled: Bool {
        didSet {
            save(hapticsEnabled, key: Keys.hapticsEnabled)
            Haptics.isEnabled = hapticsEnabled
        }
    }
    var appearance: AppAppearance {
        didSet { save(appearance, key: Keys.appearance) }
    }

    private let storage: any StorageServiceProtocol

    init(storage: any StorageServiceProtocol) {
        self.storage = storage
        self.defaultAlarmSound = (try? storage.load(key: Keys.defaultAlarmSound)) ?? .default
        self.hapticsEnabled = (try? storage.load(key: Keys.hapticsEnabled)) ?? true
        self.appearance = (try? storage.load(key: Keys.appearance)) ?? .system
        // Set once everything is initialised; `didSet` does not fire during init.
        Haptics.isEnabled = hapticsEnabled
    }

    private func save<T: Codable>(_ value: T, key: String) {
        try? storage.save(value, key: key)
    }

    private enum Keys {
        static let defaultAlarmSound = "com.morningcompanion.settings.defaultAlarmSound"
        static let hapticsEnabled = "com.morningcompanion.settings.hapticsEnabled"
        static let appearance = "com.morningcompanion.settings.appearance"
    }
}
