import Foundation
import os
import Observation
import UserNotifications
import AlarmKit

/// Single dependency-injection root. Propagated via .environment(appContainer).
///
/// Ring-state invariants (F1 · Alarm reliability):
/// - `presentRing(_:alertingID:)` is the *only* place that sets the pending-mission
///   state, and it runs before any `AlarmKit.AlarmManager.shared.stop` for a re-arm.
///   A re-arm is never silenced until the ring screen has something to show.
/// - AlarmKit keeps alerting until the mission completes or the user snoozes;
///   `RingingAlarmView` only plays in-app audio while AlarmKit is *not* alerting.
/// - Every transient id (snooze, escape/persistence re-arm, wake-check auto-fail,
///   test alarm) is registered in `ReArmRegistry` (App Group) via `AlarmManager`.
@Observable
final class AppContainer {
    let alarmManager: AlarmManager
    let storageService: any StorageServiceProtocol
    let subscriptionService: any SubscriptionServiceProtocol
    let healthKitService: any HealthKitServiceProtocol
    let weatherService: any WeatherServiceProtocol
    let calendarService: any CalendarServiceProtocol
    let appPreferences: AppPreferences
    let streakManager: StreakManager
    let sleepTrackingService: SleepTrackingService
    let notificationDelegate: NotificationDelegate?

    var hasCompletedOnboarding: Bool
    var currentRingingAlarm: Alarm?
    var selectedTabIndex: Int = 0
    /// Set when the bedtime reminder is tapped: the Sleep tab opens the wind-down.
    var windDownRequested = false
    /// Set to open the streak page on Today (the Streak widget, a deep link).
    var streakPageRequested = false

    // MARK: - Entitlement

    /// Single read point for gating. Reads through the subscription service so
    /// SwiftUI re-renders as soon as an entitlement lands.
    ///
    /// The paywall itself is always presented from the screen that needs it, never
    /// from here: the ring screen and the alarm editor are full-screen covers, and a
    /// paywall must never appear over a ringing alarm (App Review 2.1, docs/15 §10).
    var isPremium: Bool { subscriptionService.currentTier.isPremium }

    /// Mirror of `AlarmKit.AlarmManager.shared.authorizationState`, refreshed on
    /// launch and every foreground transition. Drives the Alarms banner and Settings row.
    private(set) var alarmKitAuthorization: AlarmKitAuthorizationState = .unknown

    // MARK: - Wake check state

    var showWakeCheckPrompt: Bool = false
    private(set) var wakeCheckAlarm: Alarm?
    private var wakeCheckTask: Task<Void, Never>?
    private var wakeCheckTimeoutTask: Task<Void, Never>?
    /// Unacknowledged prompt → alarm re-rings after this long.
    static let wakeCheckPromptTimeout: TimeInterval = 2 * 60
    /// Delay of the re-arm scheduled by `failWakeCheck()` so AlarmKit actually rings.
    static let wakeCheckFailReArmDelay: TimeInterval = 5

    // MARK: - AlarmKit mission tracking

    var pendingMissionAlarmID: UUID?
    private(set) var pendingMissionAlarm: Alarm?
    /// The AlarmKit id currently alerting for the pending mission: the alarm's own
    /// id, or a re-arm/snooze id. Nil when the ring came from the notification fallback.
    private(set) var alertingAlarmKitID: UUID?

    private let registry = ReArmRegistry()
    private let ringingStore = RingingStateStore()
    private let wakeCheckStateKey = "com.morningcompanion.wakecheck.state"
    private var alarmObserverTask: Task<Void, Never>?

    static let escapeReArmDelay: TimeInterval = 30
    static let persistenceReArmDelay: TimeInterval = 2 * 60
    static let testAlarmDelay: TimeInterval = 30

    // MARK: - Reconcile debounce

    private var lastReconcile: Date?
    static let reconcileDebounce: TimeInterval = 30

    // MARK: - Snooze count tracking (per alarm, persisted in the App Group)

    private static let snoozeCountsKey = "com.morningcompanion.snooze.counts"
    private static var snoozeDefaults: UserDefaults { UserDefaults(suiteName: ReArmRegistry.suiteName) ?? .standard }
    private var snoozeCounts: [UUID: Int] = [:]

    func snoozeCount(for alarmID: UUID) -> Int { snoozeCounts[alarmID, default: 0] }

    private static func loadPersistedSnoozeCounts() -> [UUID: Int] {
        guard let data = snoozeDefaults.data(forKey: snoozeCountsKey),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: dict.compactMap { key, val in
            UUID(uuidString: key).map { ($0, val) }
        })
    }

    private func persistSnoozeCounts() {
        let dict = Dictionary(uniqueKeysWithValues: snoozeCounts.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            Self.snoozeDefaults.set(data, forKey: Self.snoozeCountsKey)
        }
    }

    init(
        alarmManager: AlarmManager,
        storageService: any StorageServiceProtocol,
        subscriptionService: any SubscriptionServiceProtocol,
        healthKitService: any HealthKitServiceProtocol,
        weatherService: any WeatherServiceProtocol,
        calendarService: any CalendarServiceProtocol,
        notificationDelegate: NotificationDelegate? = nil
    ) {
        self.alarmManager = alarmManager
        self.storageService = storageService
        self.subscriptionService = subscriptionService
        self.healthKitService = healthKitService
        self.weatherService = weatherService
        self.calendarService = calendarService
        self.appPreferences = AppPreferences(storage: storageService)
        self.streakManager = StreakManager(storage: storageService)
        self.sleepTrackingService = SleepTrackingService(
            repository: LocalSleepSessionRepository(storage: storageService)
        )
        self.notificationDelegate = notificationDelegate
        if let delegate = notificationDelegate { UNUserNotificationCenter.current().delegate = delegate }

        let completed: Bool
        do { completed = try storageService.load(key: StorageKeys.onboardingCompleted) }
        catch { completed = false }
        self.hasCompletedOnboarding = completed
        self.snoozeCounts = Self.loadPersistedSnoozeCounts()
    }

    func markOnboardingComplete() {
        try? storageService.save(true, key: StorageKeys.onboardingCompleted)
        hasCompletedOnboarding = true
    }

    // MARK: - AlarmKit authorization

    func refreshAlarmKitAuthorization() {
        alarmKitAuthorization = AlarmKitAuthorizationState(AlarmKit.AlarmManager.shared.authorizationState)
    }

    // MARK: - AlarmKit lifecycle

    func beginObservingAlarmKitUpdates() {
        guard alarmObserverTask == nil else { return }
        alarmObserverTask = Task { [weak self] in
            for await alarmKitAlarms in AlarmKit.AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                if let alerting = alarmKitAlarms.first(where: { $0.state == .alerting }) {
                    await self.beginPendingMission(alerting.id)
                }
            }
        }
    }

    func bootstrapAlarmKit() async {
        subscriptionService.start()
        refreshAlarmKitAuthorization()
        // Force-quit during a ring: show the ring screen right away (F1 step 7).
        await restoreRingingStateIfNeeded()

        for await alarmKitAlarms in AlarmKit.AlarmManager.shared.alarmUpdates {
            if let alerting = alarmKitAlarms.first(where: { $0.state == .alerting }) {
                await beginPendingMission(alerting.id)
            } else {
                await reconcileNow()
            }
            break
        }
        beginObservingAlarmKitUpdates()
        // Resume any pending wake check after relaunch
        resumeWakeCheckIfNeeded()
        await refreshWidgetSnapshot()
    }

    // MARK: - Scene lifecycle

    func onEnterForeground() {
        consumeHandoff()
        refreshAlarmKitAuthorization()
        if let alarm = pendingMissionAlarm {
            // Back on the ring screen: the 30 s escape re-arm is no longer needed;
            // keep a 2 min persistence re-arm instead.
            Task {
                await alarmManager.cancelReArms(for: alarm.id, kind: .reArm)
                await schedulePersistenceReArmIfNeeded(for: alarm)
            }
        }
        beginObservingAlarmKitUpdates()
        resumeWakeCheckIfNeeded()
        Task {
            await reconcileIfDue()
            await refreshWidgetSnapshot()
        }
    }

    func onLeaveForeground() {
        Task { await reArmIfPendingMission() }
    }

    // MARK: - Reconcile

    /// Foreground reconcile, debounced to at most once per `reconcileDebounce`.
    func reconcileIfDue() async {
        if let last = lastReconcile, Date().timeIntervalSince(last) < Self.reconcileDebounce { return }
        await reconcileNow()
    }

    private func reconcileNow() async {
        lastReconcile = .now
        // Never re-schedule something that is ringing right now.
        let alerting = Set(((try? AlarmKit.AlarmManager.shared.alarms) ?? []).filter { $0.state == .alerting }.map(\.id))
        await alarmManager.reconcile(skipIDs: alerting)
    }

    // MARK: - Handoff

    func consumeHandoff() {
        guard let id = MissionHandoff.take() else { return }
        Task { await beginPendingMission(id) }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "dawnwick" else { return }
        // Widget taps: dawnwick://tab/<name> and dawnwick://wind-down.
        switch url.host?.lowercased() {
        case "wind-down":
            openWindDown()
            return
        case "tab":
            let tabs = ["today": 0, "alarms": 1, "sleep": 2, "play": 3, "settings": 4]
            guard let name = url.pathComponents.dropFirst().first?.lowercased() else { return }
            // The streak lives on Today now; older widgets still ask for "progress".
            if name == "progress" || name == "streak" {
                selectedTabIndex = 0
                streakPageRequested = true
            } else if let tab = tabs[name] {
                selectedTabIndex = tab
            }
            return
        default:
            break
        }
        guard url.host?.lowercased() == "alarm",
              let rawID = url.pathComponents.dropFirst().first,
              let id = UUID(uuidString: rawID) else { return }
        Task { await beginPendingMission(id) }
    }

    // MARK: - Mission state machine

    /// Entry point for every "an alarm is ringing" signal: AlarmKit `alarmUpdates`,
    /// the Stop/Open intents (handoff), deep links, and notification taps.
    /// `id` is either an alarm id or a registered re-arm id.
    func beginPendingMission(_ id: UUID) async {
        // Already showing this exact alert (alarmUpdates re-emits while alerting).
        if alertingAlarmKitID == id, currentRingingAlarm != nil { return }

        // Case 1 + 2: a snooze / re-arm / wake-check / test id fired. Resolve the
        // original alarm first — the ring screen must exist before anything is stopped.
        if let entry = registry.entry(for: id) {
            await beginReArmedMission(reArmID: id, entry: entry)
            return
        }

        // Case 3: the alarm's own id fired.
        if pendingMissionAlarmID == id, currentRingingAlarm != nil {
            alertingAlarmKitID = id
            return
        }
        guard let alarm = await resolveAlarm(id) else {
            // Unknown id (deleted alarm whose AlarmKit copy survived): silence it.
            Log.alarm.warning("Alerting id \(id.uuidString, privacy: .public) has no alarm — stopping")
            try? AlarmKit.AlarmManager.shared.stop(id: id)
            try? AlarmKit.AlarmManager.shared.cancel(id: id)
            return
        }
        presentRing(alarm, alertingID: id)
        // Re-arms left over from an earlier occurrence are stale now.
        await alarmManager.cancelReArms(for: alarm.id, kind: .reArm)
        if wakeCheckAlarm?.id == id { await cancelWakeCheck() }
        await schedulePersistenceReArmIfNeeded(for: alarm)
    }

    private func beginReArmedMission(reArmID: UUID, entry: ReArmRegistry.Entry) async {
        let originalID = entry.originalID
        let alarm: Alarm?
        if let pending = pendingMissionAlarm, pending.id == originalID {
            alarm = pending
        } else {
            alarm = await resolveAlarm(originalID)
        }
        guard let alarm else {
            // Nothing to ring for (alarm deleted while snoozed). No ring state is at
            // risk, so silencing here is safe.
            Log.alarm.warning("Re-arm \(reArmID.uuidString, privacy: .public) has no original alarm — cancelling")
            try? AlarmKit.AlarmManager.shared.stop(id: reArmID)
            await alarmManager.cancelReArm(id: reArmID)
            return
        }

        let previousAlerting = alertingAlarmKitID
        presentRing(alarm, alertingID: reArmID)
        if entry.kind != .test {
            // It fired; it is no longer pending. Test entries stay until the mission
            // completes so the transient alarm can still be resolved after a relaunch.
            registry.remove(reArmID: reArmID)
        }
        if wakeCheckAlarm?.id == originalID || entry.kind == .wakeCheck {
            await cancelWakeCheck()
        }
        // Only now silence whatever was alerting before — never the alert we just adopted.
        if let previousAlerting, previousAlerting != reArmID {
            try? AlarmKit.AlarmManager.shared.stop(id: previousAlerting)
        }
        await schedulePersistenceReArmIfNeeded(for: alarm)
    }

    /// Sets every piece of ring state atomically and shows the ring screen.
    private func presentRing(_ alarm: Alarm, alertingID: UUID?) {
        pendingMissionAlarmID = alarm.id
        pendingMissionAlarm = alarm
        alertingAlarmKitID = alertingID
        if currentRingingAlarm?.id != alarm.id { currentRingingAlarm = alarm }
        ringingStore.save(alarmID: alarm.id, alertingID: alertingID)
        _ = try? AlarmLiveActivityController.start(
            alarmID: alarm.id, label: alarm.label, fireDate: .now,
            status: .ringing, snoozeCount: snoozeCount(for: alarm.id)
        )
        Task { await refreshWidgetSnapshot() }
    }

    /// Repository alarm, or the transient test alarm when `id` was registered by the test flow.
    private func resolveAlarm(_ id: UUID) async -> Alarm? {
        if let alarm = await alarmManager.alarm(id: id) { return alarm }
        if registry.isTestOriginal(id) { return Alarm.testAlarm(id: id, sound: appPreferences.defaultAlarmSound) }
        return nil
    }

    /// True while AlarmKit is alerting for the pending mission (own id or re-arm id).
    /// `RingingAlarmView` plays in-app audio only when this is false.
    func isAlarmKitAlerting(for alarm: Alarm) async -> Bool {
        if let alertingAlarmKitID, await alarmManager.isAlerting(id: alertingAlarmKitID) { return true }
        return await alarmManager.isAlerting(id: alarm.id)
    }

    func completeMission(for alarm: Alarm) {
        let ids = Set([alertingAlarmKitID, alarm.id].compactMap { $0 })
        for id in ids { try? AlarmKit.AlarmManager.shared.stop(id: id) }
        Task { _ = await AlarmLiveActivityController.end(alarmID: alarm.id, finalStatus: .dismissed) }
        let isTest = registry.isTestOriginal(alarm.id)
        Task {
            if isTest {
                await alarmManager.cancelReArms(for: alarm.id)
            } else {
                await alarmManager.completeOccurrence(for: alarm)
            }
            await refreshWidgetSnapshot()
        }
        // Clearing a mission is the one unambiguous signal that this person is awake.
        // Left to themselves they will not remember to stop last night's session —
        // being awake is the moment you stop thinking about sleep tracking.
        if !isTest {
            Task { await endSleepSessionOnWake() }
        }
        pendingMissionAlarmID = nil
        pendingMissionAlarm = nil
        alertingAlarmKitID = nil
        ringingStore.clear()
        MissionHandoff.clear()
        snoozeCounts.removeValue(forKey: alarm.id)
        persistSnoozeCounts()
    }

    private func endSleepSessionOnWake() async {
        guard sleepTrackingService.isActive else { return }
        _ = await sleepTrackingService.stopSession()
        Log.app.info("Sleep session ended automatically once the alarm was cleared")
    }

    func snoozePendingMission(alarm: Alarm) async {
        // Enforce snooze limit
        let current = snoozeCounts[alarm.id, default: 0]
        let max = alarm.snooze.maxCount
        guard max == -1 || current < max else { return }  // limit reached — no snooze

        snoozeCounts[alarm.id] = current + 1
        persistSnoozeCounts()

        let delay = alarm.snooze.durationSeconds
        guard pendingMissionAlarmID == alarm.id else {
            await alarmManager.snooze(alarm, delay: delay)
            return
        }

        // Schedule the snooze *before* silencing anything so the alarm can't be lost.
        await alarmManager.cancelReArms(for: alarm.id, kind: .reArm)
        let scheduled = await alarmManager.snooze(alarm, delay: delay) != nil
        if !scheduled {
            Log.alarm.error("Snooze for \(alarm.id.uuidString, privacy: .public) could not be scheduled — keeping the alarm ringing")
            snoozeCounts[alarm.id] = current
            persistSnoozeCounts()
            return
        }
        let ids = Set([alertingAlarmKitID, alarm.id].compactMap { $0 })
        for id in ids { try? AlarmKit.AlarmManager.shared.stop(id: id) }
        pendingMissionAlarmID = nil
        pendingMissionAlarm = nil
        alertingAlarmKitID = nil
        ringingStore.clear()
        MissionHandoff.clear()
        _ = await AlarmLiveActivityController.update(
            alarmID: alarm.id, fireDate: Date().addingTimeInterval(delay),
            status: .snoozed, snoozeCount: current + 1
        )
        await refreshWidgetSnapshot()
    }

    // MARK: - Test alarm

    /// Schedules a real AlarmKit alarm `testAlarmDelay` seconds out (F1 step 12).
    /// The transient alarm lives only in `ReArmRegistry` (kind `.test`) and is
    /// cleaned up when its mission completes or by reconcile once stale.
    @discardableResult
    func scheduleTestAlarm() async -> Bool {
        let alarm = Alarm.testAlarm(id: UUID(), sound: appPreferences.defaultAlarmSound)
        return await alarmManager.scheduleReArm(for: alarm, reArmID: UUID(), delay: Self.testAlarmDelay, kind: .test)
    }

    // MARK: - Wake check

    /// Called from MissionHostView.succeed() after the success screen has shown.
    func scheduleWakeCheck(for alarm: Alarm) async {
        guard alarm.wakeCheck.isEnabled else { return }

        // Persist wake check state so it survives relaunch
        let fireDate = Date().addingTimeInterval(alarm.wakeCheck.durationSeconds)
        let state = WakeCheckState(alarmID: alarm.id, fireDate: fireDate)
        try? storageService.save(state, key: wakeCheckStateKey)
        wakeCheckAlarm = alarm

        // Also schedule a local notification for the wake check (in-background path)
        await scheduleWakeCheckNotification(for: alarm, at: fireDate)

        // Background auto-fail: if nobody acknowledges within the timeout, AlarmKit
        // rings again on its own. Cancelled by acknowledgeWakeCheck().
        await alarmManager.cancelReArms(for: alarm.id, kind: .wakeCheck)
        await alarmManager.scheduleReArm(
            for: alarm, reArmID: UUID(),
            delay: alarm.wakeCheck.durationSeconds + Self.wakeCheckPromptTimeout,
            kind: .wakeCheck
        )

        // In-app timer (foreground path)
        startWakeCheckPromptTimer(after: alarm.wakeCheck.durationSeconds)
    }

    private func startWakeCheckPromptTimer(after delay: TimeInterval) {
        wakeCheckTask?.cancel()
        wakeCheckTask = Task { [weak self] in
            let nanos = UInt64(max(0, delay)) * 1_000_000_000
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.presentWakeCheckPrompt() }
        }
    }

    private func presentWakeCheckPrompt() {
        showWakeCheckPrompt = true
        // Foreground auto-fail (F1 step 6)
        wakeCheckTimeoutTask?.cancel()
        wakeCheckTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.wakeCheckPromptTimeout) * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard self.showWakeCheckPrompt else { return }
                self.failWakeCheck()
            }
        }
    }

    func acknowledgeWakeCheck() {
        Task { await cancelWakeCheck() }
    }

    func failWakeCheck() {
        let alarm = wakeCheckAlarm
        Task {
            await cancelWakeCheck()
            guard let alarm else { return }
            // Re-trigger through a registered re-arm so AlarmKit rings (Silent/Focus proof),
            // and show the ring screen right away — in-app audio bridges the 5 s gap.
            let reArmID = UUID()
            let scheduled = await alarmManager.scheduleReArm(
                for: alarm, reArmID: reArmID, delay: Self.wakeCheckFailReArmDelay, kind: .reArm
            )
            presentRing(alarm, alertingID: scheduled ? reArmID : nil)
        }
    }

    private func cancelWakeCheck() async {
        let alarmID = wakeCheckAlarm?.id
        wakeCheckTask?.cancel()
        wakeCheckTask = nil
        wakeCheckTimeoutTask?.cancel()
        wakeCheckTimeoutTask = nil
        showWakeCheckPrompt = false
        wakeCheckAlarm = nil
        storageService.remove(key: wakeCheckStateKey)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [WakeCheckNotificationAction.requestIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [WakeCheckNotificationAction.requestIdentifier])
        if let alarmID { await alarmManager.cancelReArms(for: alarmID, kind: .wakeCheck) }
    }

    private func resumeWakeCheckIfNeeded() {
        guard let state: WakeCheckState = try? storageService.load(key: wakeCheckStateKey) else { return }
        let remaining = state.fireDate.timeIntervalSinceNow
        Task {
            guard let alarm = await resolveAlarm(state.alarmID) else {
                storageService.remove(key: wakeCheckStateKey); return
            }
            wakeCheckAlarm = alarm
            if remaining <= 0 {
                // Already expired — show prompt immediately (its 2 min timeout starts now)
                presentWakeCheckPrompt()
            } else {
                startWakeCheckPromptTimer(after: remaining)
            }
        }
    }

    /// The bedtime reminder was tapped: go to Sleep and start the wind-down there.
    func openWindDown() {
        selectedTabIndex = 2
        windDownRequested = true
    }

    /// Wake-check notification tapped ("open") or its "I'm awake" action used.
    func handleWakeCheckAction(_ action: WakeCheckNotificationAction) async {
        switch action {
        case .awake:
            await cancelWakeCheck()
        case .open:
            if wakeCheckAlarm == nil {
                guard let state: WakeCheckState = try? storageService.load(key: wakeCheckStateKey),
                      let alarm = await resolveAlarm(state.alarmID) else { return }
                wakeCheckAlarm = alarm
            }
            if !showWakeCheckPrompt { presentWakeCheckPrompt() }
        }
    }

    private func scheduleWakeCheckNotification(for alarm: Alarm, at fireDate: Date) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Still awake?", comment: "Wake check notification title")
        content.body = alarm.label.isEmpty
            ? String(localized: "Tap to confirm you're awake, or the alarm rings again in 2 minutes.", comment: "Wake check notification body no label")
            : String(localized: "Wake check for \"\(alarm.label)\" — confirm within 2 minutes or it rings again.", comment: "Wake check notification body")
        content.categoryIdentifier = WakeCheckNotificationAction.categoryIdentifier
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireDate.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: WakeCheckNotificationAction.requestIdentifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Re-arm (escape prevention)

    private func reArmIfPendingMission() async {
        guard let alarm = pendingMissionAlarm else { return }
        // AlarmKit is still ringing system-wide: leaving the app changes nothing,
        // and the persistence re-arm already covers a system Stop.
        if await isAlarmKitAlerting(for: alarm) { return }
        await alarmManager.cancelReArms(for: alarm.id, kind: .reArm)
        let reArmDate = Date().addingTimeInterval(Self.escapeReArmDelay)
        _ = await AlarmLiveActivityController.update(alarmID: alarm.id, fireDate: reArmDate, status: .snoozed, snoozeCount: snoozeCount(for: alarm.id))
        await alarmManager.scheduleReArm(for: alarm, reArmID: UUID(), delay: Self.escapeReArmDelay, kind: .reArm)
    }

    private func schedulePersistenceReArmIfNeeded(for alarm: Alarm) async {
        guard pendingMissionAlarmID == alarm.id,
              registry.reArmIDs(for: alarm.id, kind: .reArm).isEmpty else { return }
        await alarmManager.scheduleReArm(for: alarm, reArmID: UUID(), delay: Self.persistenceReArmDelay, kind: .reArm)
    }

    // MARK: - Ringing state persistence

    private func restoreRingingStateIfNeeded() async {
        guard pendingMissionAlarmID == nil, let state = ringingStore.loadIfFresh() else {
            if ringingStore.load() != nil { ringingStore.clear() }
            return
        }
        guard let alarm = await resolveAlarm(state.alarmID) else { ringingStore.clear(); return }
        Log.alarm.info("Restoring ring screen for \(alarm.id.uuidString, privacy: .public) after relaunch")
        presentRing(alarm, alertingID: state.alertingID)
        await schedulePersistenceReArmIfNeeded(for: alarm)
    }

    // MARK: - Notification path

    func handleAlarmAction(alarmID: String, action: AlarmNotificationAction) async {
        switch action {
        case .default: await showRingScreen(for: alarmID)
        case .snooze:  await performBackgroundSnooze(alarmID: alarmID)
        case .dismiss: await showRingScreen(for: alarmID)
        }
    }

    private func showRingScreen(for alarmID: String) async {
        guard let uuid = UUID(uuidString: alarmID),
              let alarm = await resolveAlarm(uuid) else { return }
        // Notification fallback: AlarmKit is not involved, so in-app audio carries the ring.
        presentRing(alarm, alertingID: nil)
        await schedulePersistenceReArmIfNeeded(for: alarm)
    }

    private func performBackgroundSnooze(alarmID: String) async {
        guard let uuid = UUID(uuidString: alarmID),
              let alarm = await resolveAlarm(uuid) else { return }
        let current = snoozeCounts[uuid, default: 0]
        let max = alarm.snooze.maxCount
        guard max == -1 || current < max else { return }
        snoozeCounts[uuid] = current + 1
        persistSnoozeCounts()
        await alarmManager.snooze(alarm, delay: alarm.snooze.durationSeconds)
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // MARK: - Widget snapshot

    func refreshWidgetSnapshot(sleepDuration: TimeInterval? = nil, sleepHistory: [SleepEntry]? = nil) async {
        let alarms = (try? await alarmManager.fetchAll()) ?? []
        let next = alarms
            .compactMap { alarm -> (alarm: Alarm, date: Date)? in
                guard let date = NextAlarmCalculator.nextFireDate(for: alarm, after: .now, in: .current) else { return nil }
                return (alarm, date)
            }
            .min { $0.date < $1.date }
        // Covers due are spent and saved first, so every reader sees the same record.
        streakManager.settle(alarms: alarms)
        let record = streakManager.record
        let live = record.liveStreak(on: .now, hadAlarm: StreakRecord.scheduled(by: alarms))
        let streak = live > 0 ? live : nil
        let existing = WidgetSharedDataStore().read()
        let week = DayCell.currentWeek(record: record, alarms: alarms).map { cell in
            WidgetDay(date: cell.date, outcome: {
                switch cell.outcome {
                case .won: .won
                case .missed: .missed
                case .rest: .rest
                case .covered: .covered
                case .today: .today
                case .upcoming: .upcoming
                }
            }())
        }
        let snapshot = WidgetSharedSnapshot(
            nextAlarmDate: next?.date,
            nextAlarmLabel: next?.alarm.label.isEmpty == false ? next?.alarm.label : nil,
            streakDays: streak,
            sleepDuration: sleepDuration ?? existing?.sleepDuration,
            missions: next?.alarm.missions.map { WidgetMission(name: $0.kind.displayName, symbol: $0.kind.systemImage) },
            week: week,
            bestStreak: record.bestStreak > 0 ? record.bestStreak : nil,
            nights: widgetNights(from: sleepHistory) ?? existing?.nights ?? widgetNights(from: nil),
            lastWin: record.lastCompletionDate,
            scheduledDays: scheduledDays(from: .now, alarms: alarms).filter { !record.isCovered($0) },
            covers: record.covers
        )
        try? WidgetSharedDataStore().save(snapshot)
    }

    /// Today and the fortnight after it, the days an alarm is set for, for the
    /// widget's own check that the streak still stands.
    private func scheduledDays(from now: Date, alarms: [Alarm]) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let scheduled = StreakRecord.scheduled(by: alarms, calendar: calendar)
        return (0...WidgetSharedSnapshot.scheduleHorizon).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }.filter(scheduled)
    }

    /// The last seven nights for the Sleep widget: Health and tracked nights merged
    /// when the Sleep screen has them, otherwise the nights this app tracked.
    private func widgetNights(from history: [SleepEntry]?) -> [WidgetNight]? {
        let entries: [(Date, TimeInterval)]
        if let history {
            entries = history.map { ($0.date, $0.duration) }
        } else {
            let merged = DaySleepSummary.merge(sessions: sleepTrackingService.loadCompletedSessions(), healthEntries: [])
            entries = merged.compactMap { summary in summary.duration.map { (summary.date, $0) } }
        }
        guard !entries.isEmpty else { return nil }
        return entries
            .sorted { $0.0 < $1.0 }
            .suffix(7)
            .map { WidgetNight(date: $0.0, duration: $0.1) }
    }

    // MARK: - Factories

    static func live() -> AppContainer {
        let storage = UserDefaultsStorageService.appGroup()
        let repository = LocalAlarmRepository(storage: storage)
        let engine = ReliableAlarmEngineService(
            primary: AlarmKitAlarmService(),
            fallback: AlarmNotificationService()
        )
        let delegate = NotificationDelegate()
        let locationProvider = LocationProvider()
        let placeNameResolver = PlaceNameResolver(storage: storage)

        #if DEBUG
        DebugLaunch.applyForcedTierToSharedCache()
        #endif

        let subscriptions: any SubscriptionServiceProtocol = {
            #if DEBUG
            if let forced = DebugLaunch.forcedTier { return StubSubscriptionService(currentTier: forced) }
            #endif
            return RevenueCatSubscriptionService()
        }()

        let container = AppContainer(
            alarmManager: AlarmManager(repository: repository, engine: engine),
            storageService: storage,
            subscriptionService: subscriptions,
            healthKitService: HealthKitSleepService(),
            weatherService: FallbackWeatherService(
                primary: WeatherKitService(locationProvider: locationProvider, placeNameResolver: placeNameResolver),
                fallback: OpenMeteoWeatherService(locationProvider: locationProvider, placeNameResolver: placeNameResolver),
                storage: storage
            ),
            calendarService: EventKitCalendarService(),
            notificationDelegate: delegate
        )
        (subscriptions as? RevenueCatSubscriptionService)?.onTierChange = { [weak container] _ in
            // Gated screens read `isPremium` directly; the widget needs a fresh snapshot.
            Task { await container?.refreshWidgetSnapshot() }
        }
        delegate.onAlarmAction = { [weak container] alarmID, action in
            guard let container else { return }
            await container.handleAlarmAction(alarmID: alarmID, action: action)
        }
        delegate.onWakeCheckAction = { [weak container] action in
            guard let container else { return }
            await container.handleWakeCheckAction(action)
        }
        delegate.onBedtimeReminder = { [weak container] in
            guard let container else { return }
            container.openWindDown()
        }
        return container
    }

    static func preview(tier: SubscriptionTier = .premium) -> AppContainer {
        AppContainer(
            alarmManager: AlarmManager(
                repository: MockAlarmRepository(),
                engine: StubAlarmEngineService(),
                entitlements: FixedEntitlementProvider(tier.isPremium)
            ),
            storageService: InMemoryStorageService(),
            subscriptionService: StubSubscriptionService(currentTier: tier),
            healthKitService: StubHealthKitService(),
            weatherService: StubWeatherService(),
            calendarService: StubCalendarService()
        )
    }
}

// MARK: - Wake check state (persisted)

private struct WakeCheckState: Codable {
    let alarmID: UUID
    let fireDate: Date
}

// MARK: - Storage keys

enum StorageKeys {
    static let onboardingCompleted = "com.morningcompanion.onboarding.completed"
    static let streakRecord        = "com.morningcompanion.streak.record"
    static let morningBriefCache   = "com.morningcompanion.today.brief.cache"
    static let weatherPrimaryBackoff = "com.morningcompanion.weather.primaryBackoff"
    static let weatherPlaceName    = "com.morningcompanion.weather.placeName"
    static let bedtimeReminder     = "com.morningcompanion.sleep.bedtimeReminder"
}
