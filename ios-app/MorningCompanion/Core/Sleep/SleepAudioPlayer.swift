import AVFoundation
import Foundation

@MainActor
@Observable
final class SleepAudioPlayer {
    private(set) var currentSound: SleepSoundType = .none
    private(set) var isPlaying: Bool = false

    private var player: AVAudioPlayer?

    // MARK: - Playback

    func play(_ sound: SleepSoundType) {
        guard sound != .none else { stop(); return }
        guard sound != currentSound || !isPlaying else { return }
        stopImmediate()

        guard let name = sound.audioResourceName,
              let url = Bundle.main.url(forResource: name, withExtension: "mp3")
                     ?? Bundle.main.url(forResource: name, withExtension: "m4a")
                     ?? Bundle.main.url(forResource: name, withExtension: "wav")
                     ?? Bundle.main.url(forResource: name, withExtension: "caf") else {
            // Audio file not bundled yet — graceful no-op.
            // Add audio files to the app bundle to enable this sound.
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1   // loop indefinitely
            p.volume = 0.0
            p.prepareToPlay()
            p.play()
            player = p
            currentSound = sound
            isPlaying = true
            fadeIn(p)
        } catch {
            // Init failure — graceful degradation
        }
    }

    func stop() {
        guard isPlaying, let p = player else { return }
        fadeOut(p) { [weak self] in
            self?.player = nil
            self?.isPlaying = false
            self?.currentSound = .none
        }
    }

    func stopImmediate() {
        player?.stop()
        player = nil
        isPlaying = false
        currentSound = .none
    }

    // MARK: - Fades

    private func fadeIn(_ p: AVAudioPlayer) {
        var step = 0
        let total = 20
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak p] t in
            guard let p, p.isPlaying else { t.invalidate(); return }
            step += 1
            p.volume = Float(step) / Float(total)
            if step >= total { t.invalidate() }
        }
    }

    private func fadeOut(_ p: AVAudioPlayer, completion: @escaping () -> Void) {
        let start = p.volume
        var step = 0
        let total = 10
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak p] t in
            guard let p else { t.invalidate(); completion(); return }
            step += 1
            p.volume = start * (1.0 - Float(step) / Float(total))
            if step >= total { t.invalidate(); p.stop(); completion() }
        }
    }

    // MARK: - Audio session management

    /// Playback-only — use when noise monitoring is disabled.
    static func activatePlayback() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Play + record — use when noise monitoring is enabled.
    /// .defaultToSpeaker routes audio to the speaker, not the earpiece.
    static func activatePlayAndRecord() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Record-only — use when noise monitoring is enabled but no sound is selected.
    static func activateRecord() {
        try? AVAudioSession.sharedInstance().setCategory(
            .record,
            mode: .default,
            options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
