import AVFoundation
import CoreMotion
import Foundation
import UIKit

/// Soft-lock policy (audit §4 / F1 step 11): a mission that cannot physically
/// run on this device must be refused at save time and, if it slips through
/// (permission revoked later, corrupt data), substituted with Math at ring time
/// instead of leaving the user on a dead-end screen.
enum MissionCapability {

    enum Availability: Equatable {
        case available
        case unavailable(reason: String)

        var isAvailable: Bool { self == .available }
        var reason: String? {
            if case .unavailable(let r) = self { return r }
            return nil
        }
    }

    /// Hardware / permission probe results, injectable for tests and previews.
    struct Probe {
        var isStepCountingAvailable: () -> Bool
        var isAccelerometerAvailable: () -> Bool
        var cameraAuthorization: () -> AVAuthorizationStatus
        var isVoiceOverRunning: () -> Bool

        static let live = Probe(
            isStepCountingAvailable: { CMPedometer.isStepCountingAvailable() },
            isAccelerometerAvailable: { CMMotionManager().isAccelerometerAvailable },
            cameraAuthorization: { AVCaptureDevice.authorizationStatus(for: .video) },
            isVoiceOverRunning: { UIAccessibility.isVoiceOverRunning }
        )
    }

    /// Missions a VoiceOver user cannot complete, whatever the hardware reports.
    ///
    /// Draw asks for a stroke traced against a shape on screen, QR for a camera aimed
    /// at a printed code, and Memory shows a pattern it never speaks. None of the
    /// three has a non-visual path to success, and failing to dismiss an alarm is not
    /// a recoverable situation at 7am.
    ///
    /// Shake, Steps and Jump deliberately stay: they are physical, not visual, and
    /// their feedback is haptic. Substituting them would take away missions a blind
    /// user can perfectly well do.
    static func isBlockedByVoiceOver(_ kind: MissionKind) -> Bool {
        switch kind {
        case .draw, .qrCode, .memory, .catchCat: return true
        case .math, .shake, .steps, .typing, .jump: return false
        }
    }

    /// Whether `kind` can run right now. Pure given the probe.
    static func availability(of kind: MissionKind, probe: Probe = .live) -> Availability {
        switch kind {
        case .steps:
            return probe.isStepCountingAvailable()
                ? .available
                : .unavailable(reason: String(localized: "Step counting isn't available on this device, so the Steps mission can't be used.", comment: "Steps mission unavailable"))
        case .jump:
            return probe.isAccelerometerAvailable()
                ? .available
                : .unavailable(reason: String(localized: "The accelerometer isn't available on this device, so the Jump mission can't be used.", comment: "Jump mission unavailable"))
        case .qrCode:
            switch probe.cameraAuthorization() {
            case .denied:
                return .unavailable(reason: String(localized: "Camera access is turned off. Enable it in Settings → Dawnwick → Camera to use the QR mission.", comment: "QR mission camera denied"))
            case .restricted:
                return .unavailable(reason: String(localized: "Camera access is restricted on this device, so the QR mission can't be used.", comment: "QR mission camera restricted"))
            default:
                return .available
            }
        case .math, .shake, .memory, .typing, .draw, .catchCat:
            return .available
        }
    }

    /// Availability for a concrete mission config, including its setup state.
    static func availability(of config: MissionConfig, probe: Probe = .live) -> Availability {
        guard config.isConfigured else {
            return .unavailable(reason: String(localized: "'\(config.displayName)' was never set up.", comment: "Mission unconfigured at runtime"))
        }
        return availability(of: config.kind, probe: probe)
    }

    /// First blocking reason across a mission list, or nil when all can run.
    static func firstBlockingReason(in missions: [MissionConfig], probe: Probe = .live) -> String? {
        for mission in missions {
            if let reason = availability(of: mission, probe: probe).reason { return reason }
        }
        return nil
    }

    /// Runtime substitution used by `MissionHostView`: every mission that cannot run
    /// becomes a default Math mission, and `notes` explains each substitution.
    ///
    /// A lapsed subscription is handled here too, deliberately. An alarm is ringing
    /// and the user is half awake: showing a paywall over it would be an App Review
    /// 2.1 rejection and a one-star review (docs/15 §10). They solve Math and get on
    /// with their morning; the upsell belongs in the editor, not at 6 a.m.
    static func runnableMissions(
        from missions: [MissionConfig],
        probe: Probe = .live,
        isPremium: Bool = true
    ) -> (missions: [MissionConfig], notes: [String]) {
        var result: [MissionConfig] = []
        var notes: [String] = []
        for mission in missions {
            if !isPremium, mission.kind.isPremium {
                result.append(.defaultMath)
                notes.append(String(localized: "\(mission.displayName) needs Premium — solve Math instead.", comment: "Premium mission substituted with math"))
                continue
            }
            // Checked at ring time only, never at save time: VoiceOver can be switched
            // on after an alarm is set, and someone may well be setting an alarm on
            // this phone for somebody else.
            if probe.isVoiceOverRunning(), isBlockedByVoiceOver(mission.kind) {
                result.append(.defaultMath)
                notes.append(String(localized: "\(mission.displayName) can't be used with VoiceOver — solve Math instead.", comment: "Mission substituted with math under VoiceOver"))
                continue
            }
            switch availability(of: mission, probe: probe) {
            case .available:
                result.append(mission)
            case .unavailable:
                result.append(.defaultMath)
                notes.append(String(localized: "\(mission.displayName) can't run right now — solve Math instead.", comment: "Mission substituted with math"))
            }
        }
        if result.isEmpty { result = [.defaultMath] }
        return (result, notes)
    }
}


// MARK: - Asking before the morning

/// Motion & Fitness is asked for when the alarm is saved, not when it rings. A
/// permission dialog is the last thing a half-asleep person should have to answer,
/// and a "Don't Allow" at that moment would silently turn Steps into Math.
enum MotionPermission {
    static func requestIfNeeded() async {
        guard CMPedometer.authorizationStatus() == .notDetermined else { return }
        let pedometer = CMPedometer()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pedometer.queryPedometerData(from: Date().addingTimeInterval(-60), to: Date()) { _, _ in
                continuation.resume()
            }
        }
    }
}
