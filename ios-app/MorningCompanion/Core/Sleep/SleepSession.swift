import Foundation

// MARK: - Sound type

/// The sounds that can play while falling asleep.
///
/// Rain and ocean were offered here and never shipped: no audio existed for them, so
/// choosing one played silence. They are gone rather than faked. White and brown noise
/// are mathematical definitions, so a generated file is the real thing; rain is a
/// recording of the world, and a synthesised one sounds like a synthesised one.
enum SleepSoundType: String, Codable, CaseIterable, Sendable {
    case none
    case whiteNoise = "white_noise"
    case brownNoise = "brown_noise"

    /// Sessions were stored with `rain` and `ocean` before they were removed, and a
    /// strict decode would throw — taking the whole night's record with it.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SleepSoundType(rawValue: raw) ?? .none
    }

    var displayName: String {
        switch self {
        case .none:       return String(localized: "No Sound",     comment: "Sleep sound: none")
        case .whiteNoise: return String(localized: "White Noise",  comment: "Sleep sound: white noise")
        case .brownNoise: return String(localized: "Brown Noise",  comment: "Sleep sound: brown noise")
        }
    }

    var systemImage: String {
        switch self {
        case .none:       return "speaker.slash"
        case .whiteNoise: return "waveform"
        case .brownNoise: return "waveform.path"
        }
    }

    /// Bundle audio file name without extension. Returns nil for .none.
    var audioResourceName: String? {
        self == .none ? nil : rawValue
    }
}

// MARK: - Noise event

struct NoiseEvent: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let timestamp: Date
    let peakDecibels: Float
}

// MARK: - Session

struct SleepSession: Codable, Identifiable, Sendable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    var noiseEvents: [NoiseEvent]
    var soundUsed: SleepSoundType

    var duration: TimeInterval? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }

    var isActive: Bool { endDate == nil }

    init(
        id: UUID = UUID(),
        startDate: Date = .now,
        soundUsed: SleepSoundType = .none
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = nil
        self.noiseEvents = []
        self.soundUsed = soundUsed
    }
}
