import Foundation

enum AlarmSound: String, Codable, CaseIterable, Sendable {
    case `default` = "default"
    case gentle    = "gentle"
    case rise      = "rise"
    case pulse     = "pulse"
    case chime     = "chime"
    case digital   = "digital"
    case meow      = "meow"

    var displayName: String {
        switch self {
        case .default: return String(localized: "Default", comment: "Alarm sound name")
        case .gentle:  return String(localized: "Gentle",  comment: "Alarm sound name")
        case .rise:    return String(localized: "Rise",    comment: "Alarm sound name")
        case .pulse:   return String(localized: "Pulse",   comment: "Alarm sound name")
        case .chime:   return String(localized: "Chime",   comment: "Alarm sound name")
        case .digital: return String(localized: "Digital", comment: "Alarm sound name")
        case .meow:    return String(localized: "Meow",    comment: "Alarm sound name: the cat meowing")
        }
    }

    var description: String {
        switch self {
        case .default: return String(localized: "Classic two-beep",    comment: "Alarm sound description")
        case .gentle:  return String(localized: "Soft bell chime",     comment: "Alarm sound description")
        case .rise:    return String(localized: "Escalating tones",    comment: "Alarm sound description")
        case .pulse:   return String(localized: "Deep rhythm",         comment: "Alarm sound description")
        case .chime:   return String(localized: "Warm bell tone",      comment: "Alarm sound description")
        case .digital: return String(localized: "Classic digital beep",comment: "Alarm sound description")
        case .meow:    return String(localized: "The cat, wanting you up", comment: "Alarm sound description")
        }
    }
}

enum GradualWakeDuration: Int, Codable, Sendable, CaseIterable {
    case off        = 0
    case fifteenSec = 15
    case thirtySec  = 30
    case sixtySec   = 60
    case threeMin   = 180

    var displayName: String {
        switch self {
        case .off:        return String(localized: "Off",    comment: "Gradual wake disabled")
        case .fifteenSec: return String(localized: "15 sec", comment: "Gradual wake 15 seconds")
        case .thirtySec:  return String(localized: "30 sec", comment: "Gradual wake 30 seconds")
        case .sixtySec:   return String(localized: "60 sec", comment: "Gradual wake 60 seconds")
        case .threeMin:   return String(localized: "3 min",  comment: "Gradual wake 3 minutes")
        }
    }

    /// Fade duration in seconds passed to AVAudioPlayer.setVolume(_:fadeDuration:).
    var fadeDuration: TimeInterval { TimeInterval(rawValue) }
}
