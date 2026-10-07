import Foundation
import os

/// Orchestrates sleep session lifecycle: audio, noise monitoring, Live Activity,
/// and session persistence. Survives app force-quit by persisting active sessions.
@MainActor
@Observable
final class SleepTrackingService {

    // MARK: - Public state

    private(set) var activeSession: SleepSession?
    /// True when the active session was loaded from a prior app launch, not started this session.
    private(set) var isRestoredSession: Bool = false
    private(set) var selectedSound: SleepSoundType
    /// Whether tonight's session should listen. Off unless the user turns it on:
    /// it holds the microphone open all night, and opting someone into that by
    /// default is not a decision an alarm app gets to make for them.
    private(set) var noiseMonitoringEnabled: Bool

    let audioPlayer = SleepAudioPlayer()
    let noiseMonitor = SleepNoiseMonitor()

    var isActive: Bool { activeSession != nil }
    var currentLevelDB: Float { noiseMonitor.currentLevelDB }
    var isMonitoring: Bool { noiseMonitor.isMonitoring }
    var hasMicPermission: Bool { noiseMonitor.micPermission == .granted }
    var noiseEvents: [NoiseEvent] { noiseMonitor.events }

    // MARK: - Private

    private let repository: any SleepSessionRepositoryProtocol
    private let selectedSoundKey = "com.morningcompanion.sleep.selectedSound"
    private let noiseMonitoringKey = "com.morningcompanion.sleep.noiseMonitoring"

    init(repository: any SleepSessionRepositoryProtocol) {
        self.repository = repository

        if let raw = UserDefaults.standard.string(forKey: selectedSoundKey),
           let sound = SleepSoundType(rawValue: raw) {
            selectedSound = sound
        } else {
            selectedSound = .none
        }

        noiseMonitoringEnabled = UserDefaults.standard.bool(forKey: noiseMonitoringKey)

        noiseMonitor.checkPermission()
        restoreIfNeeded()
    }

    // MARK: - Session lifecycle

    func startSession(nextAlarmDate: Date?, nextAlarmLabel: String?) async {
        guard activeSession == nil else { return }

        let session = SleepSession(startDate: .now, soundUsed: selectedSound)
        activeSession = session
        isRestoredSession = false
        noiseMonitor.reset()

        // Persist immediately so a force-quit can restore
        try? repository.saveActive(session)

        // An audio session is only activated if something is actually going to use it.
        // The app declares the `audio` background mode, so an idle session keeps it
        // alive all night playing nothing — the previous code did exactly that
        // whenever the microphone was refused and no sound was chosen.
        let wantsSound = selectedSound != .none
        let wantsNoise = noiseMonitoringEnabled && noiseMonitor.micPermission == .granted

        switch (wantsSound, wantsNoise) {
        case (true, true):   SleepAudioPlayer.activatePlayAndRecord()
        case (true, false):  SleepAudioPlayer.activatePlayback()
        case (false, true):  SleepAudioPlayer.activateRecord()
        case (false, false): break
        }

        if wantsSound { audioPlayer.play(selectedSound) }
        if wantsNoise { try? noiseMonitor.start() }

        // Start Live Activity
        _ = try? SleepLiveActivityController.start(
            sessionID: session.id,
            startDate: session.startDate,
            nextAlarmDate: nextAlarmDate,
            nextAlarmLabel: nextAlarmLabel
        )
    }

    /// Stops tracking, persists the completed session, and returns it.
    @discardableResult
    func stopSession() async -> SleepSession? {
        guard var session = activeSession else { return nil }

        session.endDate = .now
        session.noiseEvents = noiseMonitor.events

        audioPlayer.stop()
        noiseMonitor.stopMonitoring()

        try? repository.saveCompleted(session)
        repository.clearActive()
        activeSession = nil
        isRestoredSession = false

        await SleepLiveActivityController.end(sessionID: session.id)
        SleepAudioPlayer.deactivate()

        return session
    }

    // MARK: - Noise monitoring

    func setNoiseMonitoring(_ isEnabled: Bool) {
        noiseMonitoringEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: noiseMonitoringKey)
    }

    // MARK: - Sound

    func selectSound(_ sound: SleepSoundType) {
        selectedSound = sound
        UserDefaults.standard.set(sound.rawValue, forKey: selectedSoundKey)
        guard isActive else { return }
        if sound == .none {
            audioPlayer.stop()
        } else {
            audioPlayer.play(sound)
        }
    }

    // MARK: - Microphone permission

    func requestMicrophonePermission() async -> Bool {
        let granted = await noiseMonitor.requestPermission()
        // Being asked for the microphone is consent to use it, so the setting follows.
        if granted { setNoiseMonitoring(true) }
        guard granted, isActive else { return granted }
        // Switch to play+record category now that mic is available
        if selectedSound != .none {
            SleepAudioPlayer.activatePlayAndRecord()
        } else {
            SleepAudioPlayer.activateRecord()
        }
        try? noiseMonitor.start()
        return granted
    }

    // MARK: - History

    func loadCompletedSessions() -> [SleepSession] {
        repository.loadCompleted()
    }

    // MARK: - Restore

    /// The longest a restored session is still believable as one night's sleep.
    /// Beyond this the app was simply never told the user woke up.
    static let maximumRestorableDuration: TimeInterval = 14 * 60 * 60

    private func restoreIfNeeded() {
        guard let session = repository.loadActive(), session.isActive else { return }

        let elapsed = Date.now.timeIntervalSince(session.startDate)
        guard elapsed <= Self.maximumRestorableDuration else {
            // Discarded rather than closed at the cap: nobody knows when this person
            // actually woke, and a fabricated fourteen-hour night would go into their
            // history, their trend, and eventually Health as if it were measured.
            // Clearing it also frees them to start tonight's session.
            repository.clearActive()
            Log.app.warning("Discarded a stale sleep session (\(Int(elapsed / 3600), privacy: .public)h old, never stopped)")
            return
        }

        activeSession = session
        isRestoredSession = true
        // Audio and noise monitoring are NOT restarted on restore — the user is asleep.
        // They will manually stop the session when they wake.
    }
}

// Expose stop for noise monitor from outside
extension SleepNoiseMonitor {
    func stopMonitoring() { stop() }
}
