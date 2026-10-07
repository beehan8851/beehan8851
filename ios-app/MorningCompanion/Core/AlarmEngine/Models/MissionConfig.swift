import Foundation

// MARK: - Math difficulty

enum MathDifficulty: String, Codable, Sendable, CaseIterable {
    case easy, medium, hard

    var displayName: String {
        switch self {
        case .easy:   return String(localized: "Easy",   comment: "Difficulty level")
        case .medium: return String(localized: "Medium", comment: "Difficulty level")
        case .hard:   return String(localized: "Hard",   comment: "Difficulty level")
        }
    }
}

// MARK: - Memory difficulty

enum MemoryDifficulty: String, Codable, Sendable, CaseIterable {
    case easy, medium, hard

    var displayName: String {
        switch self {
        case .easy:   return String(localized: "Easy",   comment: "Difficulty level")
        case .medium: return String(localized: "Medium", comment: "Difficulty level")
        case .hard:   return String(localized: "Hard",   comment: "Difficulty level")
        }
    }

    var columns: Int {
        switch self { case .easy: return 3; case .medium: return 4; case .hard: return 5 }
    }

    var highlightCount: Int {
        switch self { case .easy: return 3; case .medium: return 5; case .hard: return 7 }
    }
}

// MARK: - Drawing

/// Normalized (0–1) 2-D point for the Draw Again mission.
struct StrokePoint: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
}

// MARK: - MissionConfig

/// Complete per-mission configuration — the enum case determines mission type;
/// associated values hold all user-configurable settings for that mission.
enum MissionConfig: Codable, Sendable, Equatable {
    case math(difficulty: MathDifficulty, rounds: Int)
    case shake(targetCount: Int)
    case steps(targetCount: Int)
    case qrCode(registeredCode: String?)
    case memory(difficulty: MemoryDifficulty, rounds: Int)
    case typing(phrase: String)
    case draw(referenceStrokes: [[StrokePoint]]?)
    case jump(targetCount: Int)
    case catchCat(catches: Int)

    // MARK: Defaults

    static var defaultMath:   MissionConfig { .math(difficulty: .medium, rounds: 3) }
    static var defaultShake:  MissionConfig { .shake(targetCount: 10) }
    static var defaultSteps:  MissionConfig { .steps(targetCount: 20) }
    static var defaultQR:     MissionConfig { .qrCode(registeredCode: nil) }
    static var defaultMemory: MissionConfig { .memory(difficulty: .easy, rounds: 1) }
    static var defaultTyping: MissionConfig { .typing(phrase: "") }
    static var defaultDraw:   MissionConfig { .draw(referenceStrokes: nil) }
    static var defaultJump:   MissionConfig { .jump(targetCount: 5) }
    static var defaultCatchCat: MissionConfig { .catchCat(catches: 8) }

    // MARK: Properties

    var kind: MissionKind {
        switch self {
        case .math:   return .math
        case .shake:  return .shake
        case .steps:  return .steps
        case .qrCode: return .qrCode
        case .memory: return .memory
        case .typing: return .typing
        case .draw:   return .draw
        case .jump:   return .jump
        case .catchCat: return .catchCat
        }
    }

    var displayName: String { kind.displayName }
    var systemImage: String { kind.systemImage }

    /// A phrase shorter than this is a tap, not a mission.
    static let typingMinimumLength = 6

    var configSummary: String {
        switch self {
        case .math(let d, let r):
            return "\(d.displayName) · \(r) \(r == 1 ? "round" : "rounds")"
        case .shake(let n):
            return "\(n) shakes"
        case .steps(let n):
            return "\(n) steps"
        case .qrCode(let code):
            return code == nil
                ? String(localized: "Not configured", comment: "QR not set up")
                : String(localized: "Ready",           comment: "QR ready")
        case .memory(let d, let r):
            return "\(d.displayName) · \(r) \(r == 1 ? "round" : "rounds")"
        case .typing(let phrase):
            if phrase.isEmpty { return String(localized: "No phrase set", comment: "Typing phrase empty") }
            let preview = phrase.count > 22 ? String(phrase.prefix(22)) + "…" : phrase
            return "\"\(preview)\""
        case .draw(let strokes):
            return strokes == nil
                ? String(localized: "Not calibrated", comment: "Draw not set up")
                : String(localized: "Calibrated",     comment: "Draw ready")
        case .jump(let n):
            return "\(n) jumps"
        case .catchCat(let n):
            return String(localized: "Catches: \(n)", comment: "Catch the cat mission summary: how many times the cat must be caught")
        }
    }

    var isConfigured: Bool {
        switch self {
        case .qrCode(let code):   return code != nil
        case .typing(let phrase): return phrase.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.typingMinimumLength
        case .draw(let strokes):  return strokes != nil
        default:                  return true
        }
    }

    /// Returns a copy of this config with its kind changed to `kind`, preserving
    /// any settings that carry over (none at the moment — each kind is independent).
    func withKind(_ kind: MissionKind) -> MissionConfig {
        kind.defaultConfig
    }
}

// MARK: - MissionKind

/// Flat enum for listing available mission types in pickers/library views.
enum MissionKind: String, CaseIterable, Sendable, Identifiable {
    case math, shake, steps, qrCode, memory, typing, draw, jump, catchCat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .math:   return String(localized: "Math",    comment: "Mission kind")
        case .shake:  return String(localized: "Shake",   comment: "Mission kind")
        case .steps:  return String(localized: "Steps",   comment: "Mission kind")
        case .qrCode: return String(localized: "QR Code", comment: "Mission kind")
        case .memory: return String(localized: "Memory",  comment: "Mission kind")
        case .typing: return String(localized: "Typing",  comment: "Mission kind")
        case .draw:   return String(localized: "Draw",    comment: "Mission kind")
        case .jump:   return String(localized: "Jump",    comment: "Mission kind")
        case .catchCat: return String(localized: "Catch the cat", comment: "Game title")
        }
    }

    var systemImage: String {
        switch self {
        case .math:   return "plus.forwardslash.minus"
        case .shake:  return "iphone.radiowaves.left.and.right"
        case .steps:  return "figure.walk"
        case .qrCode: return "qrcode.viewfinder"
        case .memory: return "brain.head.profile"
        case .typing: return "keyboard"
        case .draw:   return "scribble.variable"
        case .jump:   return "figure.jumprope"
        case .catchCat: return "cat"
        }
    }

    var defaultConfig: MissionConfig {
        switch self {
        case .math:   return .defaultMath
        case .shake:  return .defaultShake
        case .steps:  return .defaultSteps
        case .qrCode: return .defaultQR
        case .memory: return .defaultMemory
        case .typing: return .defaultTyping
        case .draw:   return .defaultDraw
        case .jump:   return .defaultJump
        case .catchCat: return .defaultCatchCat
        }
    }

    /// Missions that need a setup flow before they work at alarm time.
    var requiresSetup: Bool {
        switch self { case .qrCode, .draw: return true; default: return false }
    }
}
