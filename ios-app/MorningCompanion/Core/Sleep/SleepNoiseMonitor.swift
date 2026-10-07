import AVFoundation
import Foundation

/// Monitors ambient noise level via AVAudioRecorder metering.
/// Records to a temporary file (deleted on stop) so no audio is retained.
/// Sampling uses a 2-second timer — this is an approximate indicator, not a recorder.
@MainActor
@Observable
final class SleepNoiseMonitor {
    private(set) var currentLevelDB: Float = -160
    private(set) var isMonitoring: Bool = false
    private(set) var events: [NoiseEvent] = []
    private(set) var micPermission: MicrophonePermission = .undetermined

    enum MicrophonePermission {
        case undetermined, granted, denied
    }

    // Level above which a noise event is recorded (-40 dBFS ≈ quiet room disturbance)
    private let eventThresholdDB: Float = -40
    // Minimum gap between consecutive events to avoid flooding
    private let minEventGapSeconds: TimeInterval = 60

    private var recorder: AVAudioRecorder?
    private var sampleTimer: Timer?
    private var lastEventDate: Date?
    private var tempFileURL: URL?

    // MARK: - Permission

    func checkPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:      micPermission = .granted
        case .denied:       micPermission = .denied
        case .undetermined: micPermission = .undetermined
        @unknown default:   micPermission = .undetermined
        }
    }

    func requestPermission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        micPermission = granted ? .granted : .denied
        return granted
    }

    // MARK: - Start / Stop

    func start() throws {
        guard micPermission == .granted else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc_noise_\(UUID().uuidString)")
            .appendingPathExtension("caf")
        tempFileURL = url

        // Minimal quality: we only need meter readings, not audible recordings.
        let settings: [String: Any] = [
            AVFormatIDKey:           Int(kAudioFormatAppleIMA4),
            AVSampleRateKey:         4000.0,
            AVNumberOfChannelsKey:   1
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        rec.record()
        recorder = rec
        isMonitoring = true

        sampleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        recorder?.stop()
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        tempFileURL = nil
        isMonitoring = false
        currentLevelDB = -160
    }

    func reset() {
        stop()
        events = []
        lastEventDate = nil
    }

    // MARK: - Sampling

    private func sample() {
        guard let rec = recorder, rec.isRecording else { return }
        rec.updateMeters()
        let db = rec.averagePower(forChannel: 0)
        currentLevelDB = db

        guard db > eventThresholdDB else { return }
        let now = Date()
        if let last = lastEventDate, now.timeIntervalSince(last) < minEventGapSeconds { return }
        lastEventDate = now
        events.append(NoiseEvent(timestamp: now, peakDecibels: db))
    }
}
