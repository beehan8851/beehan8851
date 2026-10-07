import AVFoundation

/// Plays a looping alarm tone while the ring screen is visible.
/// Drop m4a/mp3/caf/wav files into the bundle to override synthesis for any sound.
@MainActor
final class AlarmAudioPlayer {

    private var player: AVAudioPlayer?
    private let sampleRate = 44100

    // MARK: - Public API

    func play(sound: AlarmSound = .default, volume: Float = 1.0, gradualWake: GradualWakeDuration = .off) {
        player?.stop()
        player = nil
        activateSession()

        let clamped  = min(max(volume, 0), 1)
        let startVol = gradualWake != .off ? Float(0.05) : clamped

        // Prefer bundled audio asset (allows future file drop-in without code changes)
        for ext in ["m4a", "mp3", "caf", "wav"] {
            let name = sound == .default ? "alarm" : sound.rawValue
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let p = try? AVAudioPlayer(contentsOf: url) {
                arm(p, startVol: startVol, targetVol: clamped, gradualWake: gradualWake)
                player = p
                return
            }
        }

        // Synthesise — distinct pattern and timbre for each option
        if let data = synthesise(sound: sound, volume: clamped),
           let p = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) {
            arm(p, startVol: startVol, targetVol: clamped, gradualWake: gradualWake)
            player = p
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func fadeOut(duration: TimeInterval = 0.8) {
        guard let p = player else { return }
        let start = p.volume
        let steps = 12
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * Double(i) / Double(steps)) { [weak self] in
                self?.player?.volume = max(0, start * Float(1 - Double(i) / Double(steps)))
                if i == steps { self?.stop() }
            }
        }
    }

    func reduceVolume(to level: Float = 0.25, fadeDuration: TimeInterval = 0.4) {
        player?.setVolume(level, fadeDuration: fadeDuration)
    }

    func restoreVolume(to level: Float = 1.0, fadeDuration: TimeInterval = 0.4) {
        player?.setVolume(level, fadeDuration: fadeDuration)
    }

    // MARK: - Session

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func arm(_ p: AVAudioPlayer, startVol: Float, targetVol: Float, gradualWake: GradualWakeDuration) {
        p.numberOfLoops = -1
        p.volume = startVol
        p.play()
        if gradualWake != .off { p.setVolume(targetVol, fadeDuration: gradualWake.fadeDuration) }
    }

    // MARK: - Synthesis router

    private func synthesise(sound: AlarmSound, volume: Float) -> Data? {
        switch sound {
        case .default: return makeDefaultAlarm(vol: volume)
        case .gentle:  return makeGentleAlarm(vol: volume)
        case .rise:    return makeRiseAlarm(vol: volume)
        case .pulse:   return makePulseAlarm(vol: volume)
        case .chime:   return makeChimeAlarm(vol: volume)
        case .digital: return makeDigitalAlarm(vol: volume)
        // A voice cannot be made from tones; meow.caf is always in the bundle, and
        // were it ever missing the classic beep is still an alarm.
        case .meow:    return makeDefaultAlarm(vol: volume)
        }
    }

    // MARK: Default — classic two-beep (A5 = 880 Hz, 1.02 s loop)
    // beep(120ms) · gap(80ms) · beep(120ms) · silence(700ms)

    private func makeDefaultAlarm(vol: Float) -> Data? {
        let beep  = n(ms: 120)
        let short = n(ms: 80)
        let long  = n(ms: 700)
        var buf = [Int16](repeating: 0, count: beep * 2 + short + long)
        fillTone(&buf, at: 0,            len: beep, freq: 880, vol: vol, h2amp: 0.18)
        fillTone(&buf, at: beep + short, len: beep, freq: 880, vol: vol, h2amp: 0.18)
        return buildWAV(buf)
    }

    // MARK: Gentle — ascending bell chime: C5 → E5 → G5 → rest (2.4 s loop)

    private func makeGentleAlarm(vol: Float) -> Data? {
        let noteLen = n(ms: 360)
        let gap     = n(ms: 60)
        let rest    = n(ms: 1080)
        let freqs: [Double] = [523.25, 659.25, 783.99]
        var buf = [Int16](repeating: 0, count: freqs.count * (noteLen + gap) + rest)
        for (i, freq) in freqs.enumerated() {
            fillBell(&buf, at: i * (noteLen + gap), len: noteLen, freq: freq, vol: vol * 0.84)
        }
        return buildWAV(buf)
    }

    // MARK: Rise — urgency escalation E4 → G4 → B4 → E5 → B5, crescendo (1.75 s loop)

    private func makeRiseAlarm(vol: Float) -> Data? {
        let freqs:    [Double] = [329.63, 392.00, 493.88, 659.25, 987.77]
        let noteLens: [Int]    = [n(ms: 165), n(ms: 148), n(ms: 130), n(ms: 112), n(ms: 95)]
        let gap  = n(ms: 82)
        let rest = n(ms: 580)
        let total = noteLens.reduce(0, +) + freqs.count * gap + rest
        var buf = [Int16](repeating: 0, count: total)
        var at = 0
        for (i, (freq, len)) in zip(freqs, noteLens).enumerated() {
            let amp = vol * Float(0.76 + 0.06 * Double(i))
            fillTone(&buf, at: at, len: len, freq: freq, vol: amp, h2amp: 0.14)
            at += len + gap
        }
        return buildWAV(buf)
    }

    // MARK: Pulse — deep rhythmic thuds A3 × 3 → rest (2.55 s loop)

    private func makePulseAlarm(vol: Float) -> Data? {
        let thump = n(ms: 195)
        let gap   = n(ms: 285)
        let rest  = n(ms: 885)
        var buf = [Int16](repeating: 0, count: 3 * (thump + gap) + rest)
        for i in 0..<3 {
            fillThump(&buf, at: i * (thump + gap), len: thump, freq: 220, vol: vol)
        }
        return buildWAV(buf)
    }

    // MARK: Chime — two warm bell strikes a 5th apart: A4 → E5 (~2.45 s loop)

    private func makeChimeAlarm(vol: Float) -> Data? {
        let strike1 = n(ms: 550)
        let gap     = n(ms: 250)
        let strike2 = n(ms: 450)
        let rest    = n(ms: 1200)
        var buf = [Int16](repeating: 0, count: strike1 + gap + strike2 + rest)
        fillBell(&buf, at: 0,              len: strike1, freq: 440.00, vol: vol)
        fillBell(&buf, at: strike1 + gap,  len: strike2, freq: 659.25, vol: vol * 0.88)
        return buildWAV(buf)
    }

    // MARK: Digital — classic digital clock three-beep burst (~760 ms loop)

    private func makeDigitalAlarm(vol: Float) -> Data? {
        let beep = n(ms: 72)
        let gap  = n(ms: 48)
        let rest = n(ms: 472)
        let total = 3 * beep + 2 * gap + rest
        var buf = [Int16](repeating: 0, count: total)
        for i in 0..<3 {
            fillDigital(&buf, at: i * (beep + gap), len: beep, freq: 1000, vol: vol)
        }
        return buildWAV(buf)
    }

    // MARK: - Oscillator primitives

    /// Sine tone + optional second harmonic, trapezoid amplitude envelope.
    private func fillTone(_ buf: inout [Int16], at offset: Int, len: Int,
                          freq: Double, vol: Float, h2amp: Double = 0) {
        let ramp = min(len / 10, n(ms: 7))
        let norm = 1.0 + h2amp
        for i in 0..<len {
            guard offset + i < buf.count else { break }
            let env: Double
            if i < ramp            { env = Double(i) / Double(ramp) }
            else if i > len - ramp { env = Double(len - i) / Double(ramp) }
            else                   { env = 1.0 }
            let t = Double(offset + i)
            let sr = Double(sampleRate)
            let wave = (sin(2 * .pi * freq * t / sr) + h2amp * sin(2 * .pi * freq * 2 * t / sr)) / norm
            buf[offset + i] = Int16(clamping: Int(vol * Float(env * wave) * 32767))
        }
    }

    /// Bell timbre: fundamental with decaying upper harmonics, exponential decay envelope.
    private func fillBell(_ buf: inout [Int16], at offset: Int, len: Int,
                          freq: Double, vol: Float) {
        let attack = min(len / 14, n(ms: 16))
        for i in 0..<len {
            guard offset + i < buf.count else { break }
            let env: Double
            if i < attack { env = Double(i) / Double(attack) }
            else          { env = exp(-3.8 * Double(i - attack) / Double(max(1, len - attack))) }
            let t  = Double(offset + i)
            let sr = Double(sampleRate)
            let f1 = sin(2 * .pi * freq * t / sr)
            let f2 = 0.38 * exp(-3.0 * Double(i) / Double(len)) * sin(2 * .pi * freq * 2 * t / sr)
            let f3 = 0.14 * exp(-6.5 * Double(i) / Double(len)) * sin(2 * .pi * freq * 3 * t / sr)
            let wave = (f1 + f2 + f3) / 1.52
            buf[offset + i] = Int16(clamping: Int(vol * Float(env * wave) * 32767))
        }
    }

    /// Exponential-decay sine burst — deep thump character.
    private func fillThump(_ buf: inout [Int16], at offset: Int, len: Int,
                           freq: Double, vol: Float) {
        for i in 0..<len {
            guard offset + i < buf.count else { break }
            let env  = exp(-5.5 * Double(i) / Double(len))
            let wave = sin(2 * .pi * freq * Double(offset + i) / Double(sampleRate))
            buf[offset + i] = Int16(clamping: Int(vol * Float(env * wave) * 32767))
        }
    }

    /// Buzzy square-wave approximation (odd harmonics) — classic digital alarm character.
    private func fillDigital(_ buf: inout [Int16], at offset: Int, len: Int,
                             freq: Double, vol: Float) {
        let ramp = min(len / 8, n(ms: 4))
        for i in 0..<len {
            guard offset + i < buf.count else { break }
            let env: Double
            if i < ramp            { env = Double(i) / Double(ramp) }
            else if i > len - ramp { env = Double(len - i) / Double(ramp) }
            else                   { env = 1.0 }
            let t  = Double(offset + i)
            let sr = Double(sampleRate)
            let wave = (sin(2 * .pi * freq       * t / sr)
                        + 0.33 * sin(2 * .pi * freq * 3 * t / sr)
                        + 0.20 * sin(2 * .pi * freq * 5 * t / sr)) / 1.53
            buf[offset + i] = Int16(clamping: Int(vol * Float(env * wave) * 32767))
        }
    }

    // MARK: - WAV helpers

    private func n(ms: Int) -> Int { ms * sampleRate / 1000 }

    private func buildWAV(_ samples: [Int16]) -> Data? {
        let dataBytes = samples.count * 2
        var d = Data(capacity: 44 + dataBytes)
        func cc(_ s: String)  { d.append(contentsOf: s.utf8.prefix(4)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        cc("RIFF"); u32(UInt32(36 + dataBytes)); cc("WAVE")
        cc("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        cc("data"); u32(UInt32(dataBytes))
        for s in samples { withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }
}
