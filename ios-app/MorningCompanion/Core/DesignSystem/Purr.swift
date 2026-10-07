import AVFoundation
import CoreHaptics

/// The cat's purr: the sound, and on a phone with a Taptic Engine the feel of it in
/// the hand. One purr app-wide; it starts when a stroke starts and fades when the
/// finger lifts.
///
/// The sound joins whatever audio session is already set rather than changing it:
/// the alarm and the sleep sounds own the session while they play, and a purr is not
/// a reason to take it from them. With nothing else playing it uses `.ambient`, so
/// the silent switch silences it and music the user is listening to keeps playing.
/// The feel follows the Haptics switch in Settings, like every other haptic.
@MainActor
final class Purr {
    static let shared = Purr()

    /// Loud enough to hear in a quiet room, not loud enough to startle anyone.
    private static let volume: Float = 0.55
    /// One breath of purring, out and in, in `purr.caf` and in the haptic pattern
    /// alike (assets/audio/generate_purr.py).
    private static let breath: TimeInterval = 2.0

    private var player: AVAudioPlayer?
    private var engine: CHHapticEngine?
    private var feel: CHHapticAdvancedPatternPlayer?
    private var claimedSession = false
    private var stopping: Task<Void, Never>?

    private init() {}

    func start() {
        stopping?.cancel()
        stopping = nil
        startSound()
        startFeel()
    }

    func stop() {
        player?.setVolume(0, fadeDuration: 0.6)
        try? feel?.stop(atTime: CHHapticTimeImmediate)
        stopping = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.65))
            guard !Task.isCancelled else { return }
            self?.player?.stop()
            self?.releaseSession()
        }
    }

    // MARK: Sound

    private func startSound() {
        if player == nil {
            guard let url = Bundle.main.url(forResource: "purr", withExtension: "caf"),
                  let loaded = try? AVAudioPlayer(contentsOf: url) else { return }
            loaded.numberOfLoops = -1
            loaded.volume = 0
            loaded.prepareToPlay()
            player = loaded
        }
        guard let player else { return }
        claimSessionIfFree()
        if !player.isPlaying {
            player.currentTime = 0
            player.play()
        }
        player.setVolume(Self.volume, fadeDuration: 0.4)
    }

    private func claimSessionIfFree() {
        let session = AVAudioSession.sharedInstance()
        guard !claimedSession, session.category == .soloAmbient || session.category == .ambient else { return }
        try? session.setCategory(.ambient)
        try? session.setActive(true)
        claimedSession = true
    }

    private func releaseSession() {
        guard claimedSession else { return }
        claimedSession = false
        let session = AVAudioSession.sharedInstance()
        // Something else may have taken the session over meanwhile; leave it be.
        guard session.category == .ambient else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Feel

    private func startFeel() {
        guard Haptics.isEnabled, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                let made = try CHHapticEngine()
                made.isAutoShutdownEnabled = true
                // After a reset the old players are gone; make them again next time.
                made.resetHandler = { [weak self] in
                    Task { @MainActor in self?.feel = nil }
                }
                engine = made
            }
            try engine?.start()
            if feel == nil {
                let made = try engine?.makeAdvancedPlayer(with: Self.pattern())
                made?.loopEnabled = true
                made?.loopEnd = Self.breath
                feel = made
            }
            try feel?.start(atTime: CHHapticTimeImmediate)
            // In step with the sound if it was still fading out from the last stroke.
            if let player, player.isPlaying {
                try feel?.seek(toOffset: player.currentTime.truncatingRemainder(dividingBy: Self.breath))
            }
        } catch {
            feel = nil
        }
    }

    /// One breath as taps: about 26 a second breathing out, 23 and softer breathing
    /// in, swelling and fading as the sound does. Low sharpness, so it is a rumble
    /// rather than a buzz.
    private static func pattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        func stretch(from start: TimeInterval, length: TimeInterval, rate: Double, gain: Float) {
            var t = 0.0
            while t < length {
                let swell = Float(pow(sin(.pi * t / length), 0.6))
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: gain * swell),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08),
                    ],
                    relativeTime: start + t
                ))
                t += 1 / rate
            }
        }
        stretch(from: 0, length: 1.05, rate: 26, gain: 0.5)
        stretch(from: 1.17, length: 0.72, rate: 23, gain: 0.3)
        return try CHHapticPattern(events: events, parameters: [])
    }
}
