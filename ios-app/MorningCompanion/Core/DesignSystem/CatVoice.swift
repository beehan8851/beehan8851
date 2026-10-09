import AVFoundation

/// The cat's voice outside an alarm: the short "mrrp" a cat gives in greeting, when
/// it is tapped. Three takes a little apart in pitch, never the same one twice running,
/// so tapping it again does not sound like a recording.
///
/// Like the purr it joins whatever audio session is already set rather than taking
/// it, and with nothing else playing uses `.ambient`: the silent switch silences it
/// and music keeps playing (assets/audio/generate_cat_voice.py).
@MainActor
final class CatVoice {
    static let shared = CatVoice()

    private static let takes = ["mrrp1", "mrrp2", "mrrp3"]
    private static let volume: Float = 0.5

    private var players: [String: AVAudioPlayer] = [:]
    private var last: String?

    private init() {}

    func mrrp() {
        let take = Self.takes.filter { $0 != last }.randomElement() ?? Self.takes[0]
        last = take
        guard let player = player(for: take) else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category == .soloAmbient {
            try? session.setCategory(.ambient)
        }
        if session.category == .ambient {
            try? session.setActive(true)
        }
        player.currentTime = 0
        player.volume = Self.volume
        player.play()
    }

    private func player(for take: String) -> AVAudioPlayer? {
        if let player = players[take] { return player }
        guard let url = Bundle.main.url(forResource: take, withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[take] = player
        return player
    }
}
