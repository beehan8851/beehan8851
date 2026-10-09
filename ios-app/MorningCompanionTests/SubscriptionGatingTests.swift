import Testing
import Foundation
import AVFoundation
@testable import MorningCompanion

/// Hardware probe that says yes to everything, so mission tests only exercise tiering.
private let allAvailableProbe = MissionCapability.Probe(
    isStepCountingAvailable: { true },
    isAccelerometerAvailable: { true },
    cameraAuthorization: { .authorized },
    isVoiceOverRunning: { false }
)

// MARK: - Free alarm limit

@Suite("F2 Free alarm limit")
struct FreeAlarmLimitTests {

    private func alarm(hour: Int, enabled: Bool = true) -> Alarm {
        var a = Alarm(wallClockTime: AlarmTime(hour: hour, minute: 0), recurrence: .daily, missions: [.defaultMath])
        a.isEnabled = enabled
        return a
    }

    private func manager(_ alarms: [Alarm], isPremium: Bool) -> AlarmManager {
        AlarmManager(
            repository: MockAlarmRepository(alarms: alarms),
            engine: StubAlarmEngineService(),
            entitlements: FixedEntitlementProvider(isPremium)
        )
    }

    @Test("Free: a third alarm is refused")
    func thirdAlarmRefused() async {
        let existing = [alarm(hour: 6), alarm(hour: 7)]
        let result = await manager(existing, isPremium: false).save(alarm(hour: 8))
        guard case .failure(.freeAlarmLimit) = result else {
            Issue.record("Expected .freeAlarmLimit, got \(result)")
            return
        }
    }

    @Test("Free: a second alarm is allowed")
    func secondAlarmAllowed() async {
        let result = await manager([alarm(hour: 6)], isPremium: false).save(alarm(hour: 7))
        if case .failure(let error) = result {
            Issue.record("Expected the second alarm to save, got failure: \(error)")
        }
    }

    @Test("Free: the limit counts stored alarms, not just enabled ones")
    func disabledAlarmsStillCount() async {
        let existing = [alarm(hour: 6, enabled: false), alarm(hour: 7, enabled: false)]
        let result = await manager(existing, isPremium: false).save(alarm(hour: 8))
        guard case .failure(.freeAlarmLimit) = result else {
            Issue.record("Expected .freeAlarmLimit, got \(result)")
            return
        }
    }

    @Test("Premium: a third alarm saves")
    func premiumHasNoLimit() async {
        let existing = [alarm(hour: 6), alarm(hour: 7)]
        let result = await manager(existing, isPremium: true).save(alarm(hour: 8))
        if case .failure(let error) = result {
            Issue.record("Premium should have no alarm limit, got failure: \(error)")
        }
    }

    @Test("Downgrade: editing an already-enabled alarm is never blocked")
    func editingEnabledAlarmSurvivesDowngrade() async {
        let kept = [alarm(hour: 5), alarm(hour: 6), alarm(hour: 7)]   // more than free allows
        var edited = kept[0]
        edited.label = "Renamed"
        let result = await manager(kept, isPremium: false).save(edited)
        if case .failure(let error) = result {
            Issue.record("A downgrade must not break existing alarms, got failure: \(error)")
        }
    }

    @Test("Downgrade: re-enabling a third alarm is blocked")
    func reEnablingBlocked() async {
        let existing = [alarm(hour: 5), alarm(hour: 6), alarm(hour: 7, enabled: false)]
        var switchedOn = existing[2]
        switchedOn.isEnabled = true
        let result = await manager(existing, isPremium: false).save(switchedOn)
        guard case .failure(.freeAlarmLimit) = result else {
            Issue.record("Expected .freeAlarmLimit when switching on a third alarm, got \(result)")
            return
        }
    }

    @Test("Free: disabling an alarm is always allowed")
    func disablingAlwaysAllowed() async {
        let existing = [alarm(hour: 5), alarm(hour: 6), alarm(hour: 7)]
        var switchedOff = existing[0]
        switchedOff.isEnabled = false
        let result = await manager(existing, isPremium: false).save(switchedOff)
        if case .failure(let error) = result {
            Issue.record("Turning an alarm off must always work, got failure: \(error)")
        }
    }
}

// MARK: - Premium missions

@Suite("F2 Premium missions")
struct PremiumMissionTests {

    @Test("Math and Shake are free; every other mission is Premium")
    func missionTiers() {
        #expect(MissionKind.math.isPremium == false)
        #expect(MissionKind.shake.isPremium == false)
        for kind in MissionKind.allCases where kind != .math && kind != .shake {
            #expect(kind.isPremium, "\(kind.rawValue) should be Premium")
        }
    }

    @Test("A lapsed subscription falls back to Math at ring time, never a paywall")
    func lapsedSubstitutesMath() {
        let result = MissionCapability.runnableMissions(
            from: [.defaultMemory, .defaultShake],
            probe: allAvailableProbe,
            isPremium: false
        )
        #expect(result.missions.count == 2)
        #expect(result.missions[0].kind == .math, "Memory is Premium — it must become Math")
        #expect(result.missions[1].kind == .shake, "Shake is free — it must be left alone")
        #expect(result.notes.count == 1)
    }

    @Test("Premium keeps every configured mission")
    func premiumKeepsMissions() {
        let result = MissionCapability.runnableMissions(
            from: [.defaultMemory, .typing(phrase: "wake up")],
            probe: allAvailableProbe,
            isPremium: true
        )
        #expect(result.missions.map(\.kind) == [.memory, .typing])
        #expect(result.notes.isEmpty)
    }

    @Test("An all-Premium alarm still has something to solve")
    func allPremiumStillRunnable() {
        let result = MissionCapability.runnableMissions(
            from: [.draw(referenceStrokes: [[StrokePoint(x: 0, y: 0), StrokePoint(x: 1, y: 1)]])],
            probe: allAvailableProbe,
            isPremium: false
        )
        #expect(result.missions.count == 1)
        #expect(result.missions[0].kind == .math)
    }
}

// MARK: - Entitlement cache

@Suite("F2 Entitlement cache")
struct SubscriptionEntitlementCacheTests {

    /// Each test gets its own suite so they cannot see each other's writes.
    private func makeCache() -> SubscriptionEntitlementCache {
        SubscriptionEntitlementCache(appGroupIdentifier: "test.entitlement.\(UUID().uuidString)")
    }

    @Test("No snapshot means free")
    func emptyIsFree() {
        #expect(makeCache().isPremium() == false)
    }

    @Test("A fresh premium snapshot grants premium")
    func freshPremium() {
        let cache = makeCache()
        cache.save(SubscriptionEntitlementSnapshot(isPremium: true, expiresAt: .now.addingTimeInterval(86_400)))
        #expect(cache.isPremium())
    }

    @Test("Premium survives being unverifiable for less than the grace period")
    func withinGrace() {
        let cache = makeCache()
        let twoDaysAgo = Date.now.addingTimeInterval(-2 * 86_400)
        cache.save(SubscriptionEntitlementSnapshot(isPremium: true, expiresAt: nil, verifiedAt: twoDaysAgo))
        #expect(cache.isPremium())
    }

    @Test("Premium lapses once the grace period is exhausted")
    func beyondGrace() {
        let cache = makeCache()
        let longAgo = Date.now.addingTimeInterval(-(SubscriptionEntitlementCache.graceInterval + 3_600))
        cache.save(SubscriptionEntitlementSnapshot(isPremium: true, expiresAt: nil, verifiedAt: longAgo))
        #expect(cache.isPremium() == false)
    }

    @Test("A long-expired entitlement is free even if it was verified recently")
    func expiredBeyondGrace() {
        let cache = makeCache()
        let expiry = Date.now.addingTimeInterval(-(SubscriptionEntitlementCache.graceInterval + 3_600))
        cache.save(SubscriptionEntitlementSnapshot(isPremium: true, expiresAt: expiry, verifiedAt: .now))
        #expect(cache.isPremium() == false)
    }

    @Test("An explicitly free snapshot is never upgraded by grace")
    func freeStaysFree() {
        let cache = makeCache()
        cache.save(SubscriptionEntitlementSnapshot(isPremium: false))
        #expect(cache.isPremium() == false)
    }
}

// MARK: - VoiceOver substitution

/// A mission a VoiceOver user cannot complete has to be swapped at ring time, not
/// refused at save time: VoiceOver can be switched on long after the alarm was set.
@Suite("VoiceOver mission substitution")
struct VoiceOverMissionTests {

    private func probe(voiceOver: Bool) -> MissionCapability.Probe {
        MissionCapability.Probe(
            isStepCountingAvailable: { true },
            isAccelerometerAvailable: { true },
            cameraAuthorization: { .authorized },
            isVoiceOverRunning: { voiceOver }
        )
    }

    /// `.defaultDraw` carries no reference strokes and would be substituted anyway for
    /// being unset up, which would make these tests pass for the wrong reason.
    private let configuredDraw = MissionConfig.draw(referenceStrokes: [[]])

    @Test("Visual-only missions become Math when VoiceOver is on")
    func visualMissionsSubstituted() {
        for mission in [configuredDraw, .qrCode(registeredCode: "abc"), .defaultMemory] {
            let result = MissionCapability.runnableMissions(from: [mission], probe: probe(voiceOver: true))
            #expect(result.missions == [.defaultMath], "\(mission.kind) was not substituted")
            #expect(result.notes.count == 1)
        }
    }

    @Test("Physical missions are left alone — a blind user can shake, walk and jump")
    func physicalMissionsKept() {
        for mission in [MissionConfig.defaultShake, .defaultSteps, .defaultJump, .defaultTyping] {
            let configured = mission.isConfigured ? mission : .typing(phrase: "wake up")
            let result = MissionCapability.runnableMissions(from: [configured], probe: probe(voiceOver: true))
            #expect(result.missions == [configured], "\(configured.kind) was substituted but should not have been")
            #expect(result.notes.isEmpty)
        }
    }

    @Test("With VoiceOver off nothing changes")
    func noSubstitutionWithoutVoiceOver() {
        let result = MissionCapability.runnableMissions(from: [configuredDraw], probe: probe(voiceOver: false))
        #expect(result.missions == [configuredDraw])
        #expect(result.notes.isEmpty)
    }

    @Test("Saving is not blocked — the alarm may be set for someone else")
    func savingIsUnaffected() {
        #expect(MissionCapability.availability(of: .draw, probe: probe(voiceOver: true)).isAvailable)
        #expect(MissionCapability.availability(of: .memory, probe: probe(voiceOver: true)).isAvailable)
    }
}
