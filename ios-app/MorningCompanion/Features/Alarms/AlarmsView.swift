import SwiftUI
import UIKit
import UserNotifications

// MARK: - ViewModel

@Observable
final class AlarmsViewModel {
    var state: FeatureLoadState<[Alarm]> = .idle

    private let manager: AlarmManager

    init(manager: AlarmManager) { self.manager = manager }

    func load() async {
        state = .loading
        await silentReload()
    }

    func silentReload() async {
        do {
            let alarms = try await manager.fetchAll()
            state = alarms.isEmpty ? .empty : .loaded(alarms)
        } catch {
            state = .failure(error)
        }
    }

    /// Returns false when the free alarm limit blocked the change, so the caller can
    /// show the paywall instead of silently doing nothing.
    @discardableResult
    func toggle(_ alarm: Alarm) async -> Bool {
        if case .loaded(var alarms) = state,
           let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx].isEnabled.toggle()
            state = .loaded(alarms)
        }
        var updated = alarm; updated.isEnabled.toggle()
        let result = await manager.save(updated)
        await silentReload()   // restores the real state when the save was refused
        if case .failure(.freeAlarmLimit) = result { return false }
        return true
    }

    func delete(id: UUID) async {
        if case .loaded(let alarms) = state {
            let remaining = alarms.filter { $0.id != id }
            state = remaining.isEmpty ? .empty : .loaded(remaining)
        }
        _ = await manager.delete(id: id)
        await silentReload()
    }

    @discardableResult
    func duplicate(_ alarm: Alarm) async -> Bool {
        var copy = alarm
        copy.id = UUID()
        copy.isEnabled = false
        let result = await manager.save(copy)
        await silentReload()
        if case .failure(.freeAlarmLimit) = result { return false }
        return true
    }

    /// Whether a *new* alarm can be created right now, checked before the editor opens
    /// so the free user meets the paywall instead of a rejected save.
    func canCreateAlarm(isPremium: Bool) -> Bool {
        guard !isPremium else { return true }
        guard case .loaded(let alarms) = state else { return true }
        return alarms.count < FreeTier.enabledAlarmLimit
    }

    /// Sort: enabled first, then by next occurrence; disabled sorted by time-of-day.
    func sorted(_ alarms: [Alarm]) -> [Alarm] {
        let now = Date()
        return alarms.sorted { a, b in
            if a.isEnabled != b.isEnabled { return a.isEnabled && !b.isEnabled }
            let aNext = NextAlarmCalculator.nextFireDate(for: a, after: now, in: .current)
            let bNext = NextAlarmCalculator.nextFireDate(for: b, after: now, in: .current)
            if let an = aNext, let bn = bNext { return an < bn }
            if aNext != nil { return true }
            if bNext != nil { return false }
            let at = a.wallClockTime.hour * 60 + a.wallClockTime.minute
            let bt = b.wallClockTime.hour * 60 + b.wallClockTime.minute
            return at < bt
        }
    }

    /// Summary text for the next upcoming alarm.
    func nextAlarmSummary(from alarms: [Alarm]) -> String? {
        let now = Date()
        guard let next = alarms
            .compactMap({ alarm -> Date? in NextAlarmCalculator.nextFireDate(for: alarm, after: now, in: .current) })
            .min() else { return nil }
        let diff = next.timeIntervalSinceNow
        if diff < 3600 {
            let m = max(1, Int(diff / 60))
            return String(localized: "Next alarm in \(m) min", comment: "Next alarm summary minutes")
        }
        let h = Int(diff / 3600)
        let m = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        return m > 0
            ? String(localized: "Next alarm in \(h)h \(m)m", comment: "Next alarm summary h+m")
            : String(localized: "Next alarm in \(h)h",       comment: "Next alarm summary hours")
    }
}

// MARK: - View

struct AlarmsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @State private var viewModel: AlarmsViewModel?
    @State private var editorMode: AlarmEditorMode?
    @State private var notificationsDenied = false
    @State private var testAlarmMessage: String?
    @State private var paywallFeature: PremiumFeature?
    /// The alarm a swipe or menu asked to delete; the confirmation dialog owns it.
    @State private var pendingDelete: Alarm?

    private var alarmKitDenied: Bool {
        switch container.alarmKitAuthorization {
        case .denied, .notDetermined: return true
        case .authorized, .unknown:   return false
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: DesignTokens.Spacing.xs) {
                if alarmKitDenied { alarmKitBanner }
                if notificationsDenied { permissionBanner }
                content
            }
        }
        .alert(
            String(localized: "Test alarm", comment: "Test alarm alert title"),
            isPresented: Binding(get: { testAlarmMessage != nil }, set: { if !$0 { testAlarmMessage = nil } })
        ) {
            Button(String(localized: "OK", comment: "Dismiss")) {}
        } message: { Text(testAlarmMessage ?? "") }
        .paywall(for: $paywallFeature)
        .confirmationDialog(
            String(localized: "Delete this alarm?", comment: "Delete alarm confirmation title"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { alarm in
            Button(String(localized: "Delete Alarm", comment: "Delete alarm confirmation button"), role: .destructive) {
                Task { await viewModel?.delete(id: alarm.id); await container.refreshWidgetSnapshot() }
            }
        } message: { alarm in
            Text(deleteMessage(for: alarm))
        }
        .navigationTitle(String(localized: "Alarms", comment: "Alarms nav title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar }
        .fullScreenCover(item: $editorMode, onDismiss: {
            Task {
                await viewModel?.silentReload()
                await container.refreshWidgetSnapshot()
            }
        }) { mode in
            AlarmEditorView(mode: mode, manager: container.alarmManager, defaultSound: container.appPreferences.defaultAlarmSound)
                .readsPageLayout()
                .appAppearance()
        }
        .task {
            let vm = AlarmsViewModel(manager: container.alarmManager)
            viewModel = vm
            await vm.load()
        }
        .onAppear {
            container.refreshAlarmKitAuthorization()
            Task { await checkNotificationPermission() }
            #if DEBUG
            if DebugLaunch.openEditor, editorMode == nil { editorMode = .create }
            #endif
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { createAlarm() } label: {
                Image(systemName: "plus").fontWeight(.semibold)
            }
            .tint(DesignTokens.Colors.accent)
            .accessibilityLabel(String(localized: "New Alarm", comment: "Create alarm"))
        }
    }

    // MARK: - Test alarm

    /// An alarm app is only trusted once it has been heard. The test sits under the
    /// list, in plain sight, instead of behind the + menu where nobody looked for it.
    private var testAlarmRow: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(width: 40, height: 40)
                .background(DesignTokens.Colors.surfaceSecondary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Hear it before you trust it", comment: "Test alarm row title on the Alarms list"))
                    .font(.mcHeadline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(String(localized: "A real alarm in 30 seconds, at full volume.", comment: "Test alarm row detail on the Alarms list"))
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DesignTokens.Spacing.xs)
            Button { Task { await scheduleTestAlarm() } } label: {
                Text(String(localized: "Test", comment: "Test alarm button on the Alarms list"))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.onAccent)
                    .padding(.horizontal, DesignTokens.Spacing.s)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(DesignTokens.Colors.accentFill, in: Capsule())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityHint(String(localized: "Schedules a real alarm 30 seconds from now", comment: "Test alarm button, VoiceOver hint"))
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    // MARK: - AlarmKit banner

    /// Shown while the "Alarms & Timers" permission is not granted: alarms then run on
    /// the notification fallback, which respects the ringer switch and stops after 30 s.
    private var alarmKitBanner: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "alarm.waves.left.and.right").font(.mcSubhead).foregroundStyle(DesignTokens.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Alarms won't ring reliably", comment: "AlarmKit banner title"))
                    .font(.mcSubhead).fontWeight(.medium).foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(String(localized: "Enable Alarms & Timers in Settings so alarms ring through Silent mode and Focus.", comment: "AlarmKit banner body"))
                    .font(.mcCaption).foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Spacer()
            Button(String(localized: "Settings", comment: "Open settings")) { openURL(URL(string: "app-settings:")!) }
                .font(.system(.subheadline, weight: .bold)).foregroundStyle(DesignTokens.Colors.accent)
        }
        .padding(.horizontal, DesignTokens.Spacing.s).padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
        .padding(.horizontal, DesignTokens.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Permission banner

    private var permissionBanner: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "bell.slash").font(.mcSubhead).foregroundStyle(DesignTokens.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Notifications disabled", comment: "Permission banner title"))
                    .font(.mcSubhead).fontWeight(.medium).foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(String(localized: "Alarms won't fire. Enable in Settings.", comment: "Permission banner body"))
                    .font(.mcCaption).foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Spacer()
            Button(String(localized: "Settings", comment: "Open settings")) { openURL(URL(string: "app-settings:")!) }
                .font(.system(.subheadline, weight: .bold)).foregroundStyle(DesignTokens.Colors.accent)
        }
        .padding(.horizontal, DesignTokens.Spacing.s).padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
        .padding(.horizontal, DesignTokens.Spacing.s)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state ?? .idle {
        case .idle, .loading:
            VStack { Spacer(); ProgressView().tint(DesignTokens.Colors.textSecondary); Spacer() }.frame(maxWidth: .infinity)
        case .empty:
            emptyState
        case .loaded(let alarms):
            alarmList(alarms: alarms)
        case .failure(let error):
            errorState(error)
        }
    }

    // MARK: - Empty

    /// Nothing set: the cat, awake and waiting, and the one thing to do.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.s) {
                CatMascot(mood: .awake)
                    .frame(width: 150)
                    .padding(.bottom, DesignTokens.Spacing.xs)
                Text(String(localized: "No alarms yet", comment: "Alarms empty heading"))
                    .font(.mcTitle2)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(String(localized: "Add an alarm and choose the mission that turns it off.", comment: "Alarms empty detail"))
                    .font(.mcBody)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { createAlarm() } label: {
                    Text(String(localized: "Add your first alarm", comment: "Alarms empty state button"))
                        .mcPrimaryButton()
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.top, DesignTokens.Spacing.s)
            }
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.top, DesignTokens.Spacing.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }

    private func errorState(_ error: Error) -> some View {
        VStack {
            Spacer()
            VStack(spacing: DesignTokens.Spacing.m) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 48, weight: .thin)).foregroundStyle(DesignTokens.Colors.destructive)
                Text(error.localizedDescription).font(.mcCallout).foregroundStyle(DesignTokens.Colors.textSecondary).multilineTextAlignment(.center)
                Button(String(localized: "Try Again", comment: "Retry button")) { Task { await viewModel?.load() } }
                    .font(.mcSubhead).foregroundStyle(DesignTokens.Colors.accent)
            }.padding(DesignTokens.Spacing.l)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    // MARK: - List

    private func alarmList(alarms: [Alarm]) -> some View {
        let sorted = viewModel?.sorted(alarms) ?? alarms
        return List {
            Section {
            ForEach(sorted) { alarm in
                AlarmRowView(
                    alarm: alarm,
                    onTap: { editorMode = .edit(alarm) },
                    onToggle: {
                        Task {
                            let allowed = await viewModel?.toggle(alarm) ?? true
                            if !allowed { paywallFeature = .unlimitedAlarms }
                            await container.refreshWidgetSnapshot()
                        }
                    }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = alarm
                    } label: {
                        Label(String(localized: "Delete", comment: "Delete swipe action"), systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        editorMode = .edit(alarm)
                    } label: {
                        Label(String(localized: "Edit", comment: "Context menu edit"), systemImage: "pencil")
                    }
                    Button {
                        Task {
                            let allowed = await viewModel?.duplicate(alarm) ?? true
                            if !allowed { paywallFeature = .unlimitedAlarms }
                        }
                    } label: {
                        Label(String(localized: "Duplicate", comment: "Context menu duplicate"), systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        pendingDelete = alarm
                    } label: {
                        Label(String(localized: "Delete", comment: "Context menu delete"), systemImage: "trash")
                    }
                }
            }
            } header: {
                // Next alarm summary. Only while something is going to ring; the minute
                // count ticks over on its own.
                if viewModel?.nextAlarmSummary(from: alarms) != nil {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Label(viewModel?.nextAlarmSummary(from: alarms) ?? "", systemImage: "moon.zzz.fill")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .labelStyle(AccentIconLabelStyle())
                    }
                    .textCase(nil)
                }
            }
            .mcRows()

            Section { testAlarmRow }
                .mcRows()
        }
        .listStyle(.insetGrouped)
        .mcList()
        .animation(.easeInOut(duration: DesignTokens.Motion.controls), value: alarms.map(\.id))
    }

    // MARK: - Helpers

    /// The limit is enforced in `AlarmManager.save`; this only decides whether the
    /// user sees the editor or the paywall first.
    private func createAlarm() {
        if viewModel?.canCreateAlarm(isPremium: container.isPremium) ?? true {
            editorMode = .create
        } else {
            paywallFeature = .unlimitedAlarms
        }
    }

    private func deleteMessage(for alarm: Alarm) -> String {
        let time = alarm.wallClockTime.displayString
        return alarm.label.isEmpty
            ? String(localized: "The \(time) alarm will be removed.", comment: "Delete alarm confirmation message")
            : String(localized: "“\(alarm.label)” at \(time) will be removed.", comment: "Delete alarm confirmation message with label")
    }

    private func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = (settings.authorizationStatus == .denied)
    }

    /// Real AlarmKit alarm 30 s out (F1 step 12) — lets the user hear the system
    /// alert at alarm volume, through Silent mode and Focus, before relying on it.
    private func scheduleTestAlarm() async {
        Haptics.impact(.light)
        let ok = await container.scheduleTestAlarm()
        testAlarmMessage = ok
            ? String(localized: "Your test alarm rings in 30 seconds. Lock the phone to check the Lock Screen alert.", comment: "Test alarm scheduled")
            : String(localized: "The test alarm could not be scheduled. Check Alarms & Timers and Notifications in Settings.", comment: "Test alarm failed")
    }
}

/// A label whose symbol carries the accent and whose title keeps its own colour.
struct AccentIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(DesignTokens.Colors.accent)
            configuration.title
        }
    }
}

#Preview {
    NavigationStack { AlarmsView() }
        .environment(AppContainer.preview())
}
