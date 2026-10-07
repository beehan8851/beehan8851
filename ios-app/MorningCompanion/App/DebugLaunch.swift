#if DEBUG
import Foundation

/// DEBUG-only QA hooks driven by launch arguments so the simulator can be put
/// into any screen without tapping. Compiled out of Release builds entirely.
///
/// Usage:
///   xcrun simctl launch <sim> dev.numonov.dawnwick -mc.debug.tab 2
///   -mc.debug.skipOnboarding 1      skip onboarding
///   -mc.debug.resetOnboarding 1     show onboarding again on an installed app
///   -mc.debug.seedAlarms 1          save Alarm.samples into the repository
///   -mc.debug.tab <0-4>             select a tab
///   -mc.debug.editor 1              open the New Alarm editor (Alarms tab)
///   -mc.debug.ring 1                present the ringing screen with Alarm.samples[0]
///   -mc.debug.mission <kind>        ring + auto-start a mission of this kind (math, shake, memory, typing, draw, steps, jump, qrCode)
///   -mc.debug.paywall 1             present the paywall
///   -mc.debug.onboardingStep <0-2>  start onboarding at this step (0 welcome, 1 permissions, 2 first alarm)
///   -mc.debug.premium 1|0           force the entitlement on/off (no store round-trip)
///   -mc.debug.seedStreak <n>        write a streak record: n days won ending today, one miss before them
///                                    (0: a streak just lost — older wins, nothing current)
///   -mc.debug.streakGap <k>         with seedStreak: the last of those wins was k days ago (2 with an alarm yesterday = a missed morning)
///   -mc.debug.seedSleep <n>         write n completed sleep sessions, one per night ending this morning (one night skipped)
///   -mc.debug.success 1             present the mission success screen
///   -mc.debug.wakeCheck 1           present the "Still awake?" sheet
///   -mc.debug.clearAlarms 1         delete every saved alarm (for the empty state)
///   -mc.debug.appearance <system|light|dark>  set the in-app appearance preference (simctl's switch is unreliable after a reboot)
///   -mc.debug.mood <sleeping|awake|proud|grumpy>  force the cat's mood on Today (it otherwise follows the clock and the streak)
///   -mc.debug.windDown <setup|breathing|done>  open the wind-down on the Sleep tab at that stage
///   -mc.debug.game 1                open "Catch the cat" from Today
///   -mc.debug.laser 1               open "Laser" from Today
///   -mc.debug.boxes 1               open "Which box?" from Today
///   -mc.debug.streakPage 1          open the streak page from Today
///   -mc.debug.seedBest <n>          with seedStreak: the best streak (tricks learned), instead of max(n, 21)
///   -mc.debug.covers <n>            with seedStreak: covers the cat holds
///   -mc.debug.slowCat 1             the game's cat waits a minute per jump and a round lasts five minutes (scripted taps)
///   -mc.debug.duo <outer|inner|auto>  lay the app out as an iPhone Duo, closed, open, or opening and closing (DuoEmulator)
///   -mc.debug.appleWeather 1        draw the weather detail's attribution as for WeatherKit (the simulator falls back to Open-Meteo)
///   -mc.debug.duoScreen <ring|editor|onboarding|paywall|winddown|game|laser|boxes|share>  with -mc.debug.duo, show that screen in the emulator in place of the app
enum DebugLaunch {
    private static let defaults = UserDefaults.standard

    static var skipOnboarding: Bool { defaults.bool(forKey: "mc.debug.skipOnboarding") }
    static var resetOnboarding: Bool { defaults.bool(forKey: "mc.debug.resetOnboarding") }
    static var seedAlarms: Bool { defaults.bool(forKey: "mc.debug.seedAlarms") }
    static var tab: Int? { defaults.object(forKey: "mc.debug.tab") == nil ? nil : defaults.integer(forKey: "mc.debug.tab") }
    static var openEditor: Bool { defaults.bool(forKey: "mc.debug.editor") }
    /// Not in the Duo emulator: there the mission is shown in place of the app.
    static var ring: Bool { (defaults.bool(forKey: "mc.debug.ring") || missionKind != nil) && duo == nil }
    static var missionKind: MissionKind? { defaults.string(forKey: "mc.debug.mission").flatMap(MissionKind.init(rawValue:)) }
    static var autoStartMission: Bool { missionKind != nil }
    static var paywall: Bool { defaults.bool(forKey: "mc.debug.paywall") }
    static var success: Bool { defaults.bool(forKey: "mc.debug.success") }
    static var wakeCheck: Bool { defaults.bool(forKey: "mc.debug.wakeCheck") }
    static var clearAlarms: Bool { defaults.bool(forKey: "mc.debug.clearAlarms") }
    static var seedStreak: Int? { defaults.object(forKey: "mc.debug.seedStreak") == nil ? nil : defaults.integer(forKey: "mc.debug.seedStreak") }
    static var streakGap: Int { defaults.integer(forKey: "mc.debug.streakGap") }
    static var seedSleep: Int? { defaults.object(forKey: "mc.debug.seedSleep") == nil ? nil : defaults.integer(forKey: "mc.debug.seedSleep") }
    static var windDown: String? { defaults.string(forKey: "mc.debug.windDown") }
    static var game: Bool { defaults.bool(forKey: "mc.debug.game") }
    static var laser: Bool { defaults.bool(forKey: "mc.debug.laser") }
    static var boxes: Bool { defaults.bool(forKey: "mc.debug.boxes") }
    static var naps: Bool { defaults.bool(forKey: "mc.debug.naps") }
    static var streakPage: Bool { defaults.bool(forKey: "mc.debug.streakPage") }
    static var seedBest: Int? { defaults.object(forKey: "mc.debug.seedBest") == nil ? nil : defaults.integer(forKey: "mc.debug.seedBest") }
    static var covers: Int { defaults.integer(forKey: "mc.debug.covers") }
    static var appleWeather: Bool { defaults.bool(forKey: "mc.debug.appleWeather") }
    /// The cat stays a minute, slow enough for a scripted tap to reach it.
    static var slowCat: Bool { defaults.bool(forKey: "mc.debug.slowCat") }
    static var duo: String? { defaults.string(forKey: "mc.debug.duo").flatMap { ["outer", "inner", "auto"].contains($0) ? $0 : nil } }
    /// A screen the app presents over itself, which would miss the emulated window.
    static var duoScreen: String? { duo == nil ? nil : defaults.string(forKey: "mc.debug.duoScreen") }
    static var mood: CatMascot.Mood? { defaults.string(forKey: "mc.debug.mood").flatMap(CatMascot.Mood.init(rawValue:)) }

    /// Which onboarding step to open on. Onboarding is otherwise reachable only on a
    /// fresh install, which makes its later steps tedious to look at.
    static var onboardingStep: Int? {
        defaults.object(forKey: "mc.debug.onboardingStep") == nil
            ? nil
            : defaults.integer(forKey: "mc.debug.onboardingStep")
    }

    /// Overrides the entitlement so gated states can be QA'd without a sandbox purchase.
    /// Nil means "use the real subscription service".
    static var forcedTier: SubscriptionTier? {
        guard defaults.object(forKey: "mc.debug.premium") != nil else { return nil }
        return defaults.bool(forKey: "mc.debug.premium") ? .premium : .free
    }

    /// Writes the forced entitlement into the App Group so the `AlarmManager` actor
    /// and the widget extension agree with the in-app service.
    static func applyForcedTierToSharedCache() {
        guard let forcedTier else { return }
        SubscriptionEntitlementCache().save(
            SubscriptionEntitlementSnapshot(isPremium: forcedTier.isPremium, expiresAt: nil, verifiedAt: .now)
        )
    }

    /// Alarm used for ring/mission previews.
    static var ringAlarm: Alarm {
        var alarm = Alarm.samples[0]
        if let kind = missionKind {
            var config = kind.defaultConfig
            if case .typing = config { config = .typing(phrase: "I am awake and ready") }
            alarm.missions = [config]
        }
        return alarm
    }

    @MainActor
    static func apply(to container: AppContainer) async {
        if resetOnboarding { container.hasCompletedOnboarding = false }
        if clearAlarms {
            for alarm in (try? await container.alarmManager.fetchAll()) ?? [] {
                _ = await container.alarmManager.delete(id: alarm.id)
            }
        }
        if skipOnboarding, !container.hasCompletedOnboarding { container.markOnboardingComplete() }
        if seedAlarms {
            // Disabled by default so the notification-permission prompt does not block screenshots.
            for var sample in Alarm.samples {
                sample.isEnabled = defaults.bool(forKey: "mc.debug.seedEnabled")
                _ = await container.alarmManager.save(sample)
            }
        }
        if let seedStreak, seedStreak >= 0 {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            var record = StreakRecord()
            for back in streakGap..<(streakGap + seedStreak) {
                if let day = calendar.date(byAdding: .day, value: -back, to: today) {
                    record.completedDates.insert(StreakRecord.dateKey(for: day, calendar: calendar))
                }
            }
            // A few older mornings, with a gap, so the calendar shows a miss too.
            for back in (streakGap + seedStreak + 2)..<(streakGap + seedStreak + 6) {
                if let day = calendar.date(byAdding: .day, value: -back, to: today) {
                    record.completedDates.insert(StreakRecord.dateKey(for: day, calendar: calendar))
                }
            }
            record.currentStreak = seedStreak
            record.bestStreak = seedBest.map { max($0, seedStreak) } ?? max(seedStreak, 21)
            record.covers = min(covers, StreakRecord.maxCovers)
            record.lastCompletionDate = seedStreak > 0
                ? calendar.date(byAdding: .day, value: -streakGap, to: today)
                : calendar.date(byAdding: .day, value: -2, to: today)
            try? container.storageService.save(record, key: StorageKeys.streakRecord)
            container.streakManager.reload()
        }
        if let tab { container.selectedTabIndex = tab }
        if streakPage { container.streakPageRequested = true }
        if wakeCheck { container.showWakeCheckPrompt = true }
        if ring {
            container.currentRingingAlarm = ringAlarm
            // The real ring path starts the Live Activity; the hook does too, so the
            // Dynamic Island and Lock Screen can be checked on the simulator.
            _ = try? AlarmLiveActivityController.start(alarmID: ringAlarm.id, label: ringAlarm.label, fireDate: .now)
        }
        if let seedSleep, seedSleep > 0 {
            // Nights of varying length ending on the last `n` mornings; the third night
            // back is skipped so the history chart shows an empty slot too.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let hours: [Double] = [7.4, 6.1, 8.2, 5.3, 7.9, 6.8, 7.0, 8.6, 4.9, 7.2]
            var sessions: [SleepSession] = []
            for back in 0..<seedSleep where back != 2 {
                guard let morning = calendar.date(byAdding: .day, value: -back, to: today),
                      let wake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: morning) else { continue }
                let length = hours[back % hours.count] * 3600
                var session = SleepSession(startDate: wake.addingTimeInterval(-length), soundUsed: .none)
                session.endDate = wake
                sessions.append(session)
            }
            try? container.storageService.save(sessions, key: "com.morningcompanion.sleep.completedSessions")
        }
        if let raw = defaults.string(forKey: "mc.debug.appearance"), let appearance = AppAppearance(rawValue: raw) {
            container.appPreferences.appearance = appearance
        }
    }
}
#endif
