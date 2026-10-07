import SwiftUI

// MARK: - Presentation mode

enum AlarmEditorMode: Identifiable {
    case create
    case edit(Alarm)
    var id: String {
        switch self { case .create: return "create"; case .edit(let a): return a.id.uuidString }
    }
}

// MARK: - ViewModel

@Observable
final class AlarmEditorViewModel {

    enum ScheduleMode: String, CaseIterable, Identifiable {
        case oneTime  = "One-time"
        case daily    = "Daily"
        case weekdays = "Weekdays"
        case weekends = "Weekends"
        case custom   = "Custom"
        var id: String { rawValue }
    }

    var hour: Int
    var minute: Int
    var label: String
    var scheduleMode: ScheduleMode
    var customDays: Set<Weekday>
    var oneTimeDate: Date
    var missions: [MissionConfig]
    var sound: AlarmSound
    var volume: Float
    var gradualWakeDuration: GradualWakeDuration
    var snooze: SnoozeConfig
    var wakeCheck: WakeCheckConfig

    var effectiveDays: Set<Weekday> {
        switch scheduleMode {
        case .oneTime:  return []
        case .daily:    return Set(Weekday.allCases)
        case .weekdays: return [.monday, .tuesday, .wednesday, .thursday, .friday]
        case .weekends: return [.saturday, .sunday]
        case .custom:   return customDays
        }
    }

    func toggleDay(_ day: Weekday) {
        var days = effectiveDays
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
        // Empty selection = one-time (no repeat days)
        if days.isEmpty { scheduleMode = .oneTime } else { applyDays(days) }
    }

    func applyDays(_ days: Set<Weekday>) {
        let allWeekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let allWeekends: Set<Weekday> = [.saturday, .sunday]
        if days == Set(Weekday.allCases) { scheduleMode = .daily }
        else if days == allWeekdays      { scheduleMode = .weekdays }
        else if days == allWeekends      { scheduleMode = .weekends }
        else                             { scheduleMode = .custom; customDays = days }
    }

    var scheduleSummaryText: String {
        switch scheduleMode {
        case .oneTime:  return String(localized: "One-time",  comment: "Schedule summary")
        case .daily:    return String(localized: "Every day", comment: "Schedule summary")
        case .weekdays: return String(localized: "Mon – Fri", comment: "Schedule summary")
        case .weekends: return String(localized: "Sat – Sun", comment: "Schedule summary")
        case .custom:
            if customDays.isEmpty { return String(localized: "Select days", comment: "Schedule summary empty") }
            let order: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
            return order
                .filter { customDays.contains($0) }
                .map { String($0.shortName.prefix(3)).capitalized }
                .joined(separator: ", ")
        }
    }

    var isSaving = false
    var saveError: String? = nil
    /// True when the error is a scheduling problem the user can fix in Settings
    /// (AlarmKit / notification permission), so the alert offers a Settings button.
    var saveErrorNeedsSettings = false
    /// True when the free alarm limit refused the save, so the alert offers Upgrade.
    var saveErrorNeedsPaywall = false

    var isEditing: Bool { existingAlarm != nil }

    var canSave: Bool {
        if missions.isEmpty { return false }
        if missions.contains(where: { !$0.isConfigured }) { return false }
        if scheduleMode == .custom && customDays.isEmpty { return false }
        return true
    }

    /// Whether Cancel would throw something away.
    var hasChanges: Bool { buildAlarm() != initialDraft }

    var ringsInText: String {
        let dummy = buildAlarm()
        guard let next = NextAlarmCalculator.nextFireDate(for: dummy, after: .now, in: .current) else {
            return String(localized: "—", comment: "No next fire date")
        }
        let diff = next.timeIntervalSinceNow
        if diff < 60 { return String(localized: "Rings in < 1 min", comment: "Rings in less than a minute") }
        if diff < 3600 {
            let m = Int(diff / 60)
            return String(localized: "Rings in \(m) min", comment: "Rings in minutes")
        }
        let h = Int(diff / 3600)
        let m = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        return m > 0
            ? String(localized: "Rings in \(h)h \(m)m", comment: "Rings in hours and minutes")
            : String(localized: "Rings in \(h)h", comment: "Rings in hours")
    }

    private let existingAlarm: Alarm?
    private let manager: AlarmManager
    /// Stable id for a new alarm, so `hasChanges` compares like with like.
    private let draftID: UUID
    private var initialDraft: Alarm!

    init(alarm: Alarm? = nil, manager: AlarmManager, defaultSound: AlarmSound = .default) {
        self.existingAlarm = alarm
        self.manager = manager
        self.draftID = alarm?.id ?? UUID()
        if let alarm {
            hour  = alarm.wallClockTime.hour
            minute = alarm.wallClockTime.minute
            label = alarm.label
            missions = alarm.missions
            sound = alarm.sound
            volume = max(AlarmManager.minimumVolume, alarm.volume)
            gradualWakeDuration = alarm.gradualWakeDuration
            snooze = alarm.snooze
            wakeCheck = alarm.wakeCheck

            switch alarm.recurrence {
            case .oneTime(let ad):
                scheduleMode = .oneTime
                var dc = DateComponents()
                dc.year = ad.year; dc.month = ad.month; dc.day = ad.day
                oneTimeDate = Calendar.current.date(from: dc) ?? .now
                customDays = []
            case .daily:
                scheduleMode = .daily; customDays = []; oneTimeDate = .now
            case .repeating(let days):
                let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
                let weekends: Set<Weekday> = [.saturday, .sunday]
                if days == weekdays      { scheduleMode = .weekdays; customDays = [] }
                else if days == weekends { scheduleMode = .weekends; customDays = [] }
                else                     { scheduleMode = .custom;   customDays = days }
                oneTimeDate = .now
            }
        } else {
            hour = 7; minute = 0; label = ""
            scheduleMode = .daily; customDays = []; oneTimeDate = .now
            missions = [.defaultMath]
            sound = defaultSound; volume = 1.0; gradualWakeDuration = .off
            snooze = .default; wakeCheck = .off
        }
        initialDraft = buildAlarm()
    }

    func save() async -> Bool {
        isSaving = true; saveError = nil; saveErrorNeedsSettings = false; saveErrorNeedsPaywall = false
        defer { isSaving = false }

        // Soft-lock policy (F1 step 11): refuse missions this device cannot run.
        if let reason = MissionCapability.firstBlockingReason(in: missions) {
            saveError = reason
            return false
        }

        if missions.contains(where: { $0.kind == .steps }) {
            await MotionPermission.requestIfNeeded()
        }

        let result = await manager.save(buildAlarm())
        switch result {
        case .success:
            return true
        case .partialSuccess(_, let schedulingError):
            // Persisted but NOT scheduled — the alarm will not ring. Surface it (audit §3 P1).
            saveError = String(
                localized: "The alarm was saved but could not be scheduled: \(schedulingError.localizedDescription)",
                comment: "Alarm saved but scheduling failed"
            )
            saveErrorNeedsSettings = true
            return false
        case .failure(let e):
            saveError = e.localizedDescription
            if case .freeAlarmLimit = e { saveErrorNeedsPaywall = true }
            return false
        case .deleted:
            return false
        }
    }

    /// Removes the alarm being edited. Only meaningful in edit mode.
    func delete() async {
        guard let existingAlarm else { return }
        _ = await manager.delete(id: existingAlarm.id)
    }

    /// Saves a disabled copy of the alarm being edited, as it is on screen now.
    /// Returns false when the free alarm limit refused it.
    func duplicate() async -> Bool {
        var copy = buildAlarm()
        copy.id = UUID()
        copy.isEnabled = false
        let result = await manager.save(copy)
        if case .failure(let e) = result {
            saveError = e.localizedDescription
            if case .freeAlarmLimit = e { saveErrorNeedsPaywall = true }
            return false
        }
        return true
    }

    private func buildAlarm() -> Alarm {
        let recurrence: AlarmRecurrence
        switch scheduleMode {
        case .oneTime:  recurrence = .oneTime(date: AlarmDate(from: oneTimeDate))
        case .daily:    recurrence = .daily
        case .weekdays: recurrence = .repeating(days: [.monday, .tuesday, .wednesday, .thursday, .friday])
        case .weekends: recurrence = .repeating(days: [.saturday, .sunday])
        case .custom:   recurrence = .repeating(days: customDays)
        }
        return Alarm(
            id:              draftID,
            label:           label.trimmingCharacters(in: .whitespaces),
            wallClockTime:   AlarmTime(hour: hour, minute: minute),
            recurrence:      recurrence,
            missions:        missions,
            sound:           sound,
            volume:          volume,
            gradualWakeDuration: gradualWakeDuration,
            snooze:          snooze,
            wakeCheck:       wakeCheck,
            isEnabled:       existingAlarm?.isEnabled ?? true
        )
    }
}

// MARK: - Editor view

/// The time on a yolk band at the top — two drums of large numerals that stay in view —
/// and the rest as a list under it: when it repeats, the missions as small moving
/// tiles, the label, the sound, snooze and wake check. Delete and Duplicate live at
/// the bottom of an existing alarm; Cancel asks before throwing edits away.
struct AlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppContainer.self) private var container
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pageLayout) private var pageLayout
    @Environment(\.colorScheme) private var colorScheme
    /// The weekday circle grows with the letter inside it.
    @ScaledMetric(relativeTo: .subheadline) private var dayCircleSize: CGFloat = 38
    @State private var viewModel: AlarmEditorViewModel
    @State private var showSaveError = false
    @State private var missionEditorIndex: Int?
    @State private var showMissionPicker = false
    @State private var paywallFeature: PremiumFeature?
    @State private var showDiscardDialog = false
    @State private var showDeleteDialog = false
    @FocusState private var labelFocused: Bool
    @State private var previewPlayer = AlarmAudioPlayer()
    @State private var previewingSound: AlarmSound? = nil

    private let weekdayOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    init(mode: AlarmEditorMode, manager: AlarmManager, defaultSound: AlarmSound = .default) {
        let alarm: Alarm? = { if case .edit(let a) = mode { return a }; return nil }()
        _viewModel = State(wrappedValue: AlarmEditorViewModel(alarm: alarm, manager: manager, defaultSound: defaultSound))
    }

    var body: some View {
        NavigationStack {
            content
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(viewModel.isEditing
                             ? String(localized: "Edit Alarm", comment: "Editor nav title")
                             : String(localized: "New Alarm",  comment: "Editor nav title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
            .onDisappear { previewPlayer.stop(); previewingSound = nil }
            .alert(saveAlertTitle, isPresented: $showSaveError) {
                if viewModel.saveErrorNeedsSettings {
                    Button(String(localized: "Settings", comment: "Open settings")) {
                        openURL(URL(string: "app-settings:")!)
                    }
                }
                if viewModel.saveErrorNeedsPaywall {
                    Button(String(localized: "See Premium", comment: "Open paywall from save error")) {
                        paywallFeature = .unlimitedAlarms
                    }
                }
                Button(String(localized: "OK", comment: "Dismiss")) {}
            } message: { Text(viewModel.saveError ?? "") }
            .confirmationDialog(
                String(localized: "Discard changes?", comment: "Unsaved changes dialog title"),
                isPresented: $showDiscardDialog,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Discard Changes", comment: "Unsaved changes, discard"), role: .destructive) { dismiss() }
                Button(String(localized: "Keep Editing", comment: "Unsaved changes, keep editing"), role: .cancel) {}
            }
            .confirmationDialog(
                String(localized: "Delete this alarm?", comment: "Delete alarm confirmation title"),
                isPresented: $showDeleteDialog,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete Alarm", comment: "Delete alarm confirmation button"), role: .destructive) {
                    Task { await viewModel.delete(); dismiss() }
                }
            }
            .paywall(for: $paywallFeature)
            .sheet(item: $missionEditorIndex) { idx in
                MissionEditorView(config: Binding(
                    get: { viewModel.missions[idx] },
                    set: { viewModel.missions[idx] = $0 }
                ))
                .appAppearance()
            }
            .sheet(isPresented: $showMissionPicker) { MissionPickerView(missions: $viewModel.missions).appAppearance() }
        }
        .tint(DesignTokens.Colors.accent)
    }

    /// The drums stay pinned above the list. At accessibility sizes they would take
    /// the whole screen, so the system wheel scrolls with the list instead.
    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            List {
                timeSection
                sections
            }
            .listStyle(.insetGrouped)
            .mcList()
        } else if pageLayout == .spread {
            // Open like a book: the time on the left page, the size of a page, with the
            // cat asleep under it until then; everything else on the right.
            HStack(spacing: PageLayout.gutter) {
                timeBand(tall: true)
                    .padding(.leading, 12)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                List { sections }
                    .listStyle(.insetGrouped)
                    .mcList()
                    .contentMargins(.top, DesignTokens.Spacing.xs, for: .scrollContent)
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                timeBand()
                    .padding(.horizontal, 12)
                    .padding(.top, DesignTokens.Spacing.xxs)
                List { sections }
                    .listStyle(.insetGrouped)
                    .mcList()
                    .contentMargins(.top, DesignTokens.Spacing.xs, for: .scrollContent)
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        scheduleSection
        missionsSection
        labelSection
        soundSection
        snoozeSection
        wakeCheckSection
        if viewModel.isEditing { manageSection }
    }

    private var saveAlertTitle: String {
        if viewModel.saveErrorNeedsPaywall {
            return String(localized: "Alarm Limit Reached", comment: "Free alarm limit alert title")
        }
        return viewModel.saveErrorNeedsSettings
            ? String(localized: "Alarm Won't Ring", comment: "Scheduling error title")
            : String(localized: "Could Not Save", comment: "Save error")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel", comment: "Cancel")) {
                if viewModel.hasChanges { showDiscardDialog = true } else { dismiss() }
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        ToolbarItem(placement: .confirmationAction) {
            ZStack {
                Button(String(localized: "Save", comment: "Save")) {
                    Task { if await viewModel.save() { dismiss() } else { showSaveError = true } }
                }
                .fontWeight(.bold)
                .foregroundStyle(viewModel.canSave ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
                .disabled(!viewModel.canSave || viewModel.isSaving)
                .opacity(viewModel.isSaving ? 0 : 1)
                if viewModel.isSaving { ProgressView().tint(DesignTokens.Colors.accent).scaleEffect(0.85) }
            }
        }
    }

    // MARK: - Time

    /// The hero band: the drums, and how long until it rings. Yolk by day; ink with
    /// yolk numerals in the dark appearance, where alarms are mostly set at night.
    private func timeBand(tall: Bool = false) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            if tall { Spacer(minLength: 0) }
            TimeDrumPicker(hour: $viewModel.hour, minute: $viewModel.minute)
            Text(viewModel.ringsInText)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.onHeroSecondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: DesignTokens.Motion.controls), value: viewModel.hour)
                .animation(.easeInOut(duration: DesignTokens.Motion.controls), value: viewModel.minute)
            if tall {
                Spacer(minLength: DesignTokens.Spacing.s)
                // Asleep on its moon on the night band; on the yolk the moon would
                // vanish, so by day it sits up and waits for the time.
                if colorScheme == .dark {
                    CatMascot(mood: .sleeping, ground: .dark)
                        .frame(width: 150)
                        .accessibilityHidden(true)
                } else {
                    CatStage(mood: .awake, ground: .light)
                        .frame(width: 104)
                }
            }
        }
        .padding(.top, DesignTokens.Spacing.xs)
        .padding(.bottom, tall ? DesignTokens.Spacing.m : DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: tall ? .infinity : nil)
        .background(DesignTokens.Colors.heroBand, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
    }

    /// The wheel works on a Date; the model keeps hour and minute.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: viewModel.hour, minute: viewModel.minute, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                viewModel.hour = parts.hour ?? viewModel.hour
                viewModel.minute = parts.minute ?? viewModel.minute
            }
        )
    }

    /// The system wheel, on the page like Clock's own alarm sheet, with the time
    /// until it rings underneath.
    private var timeSection: some View {
        Section {
            DatePicker(String(localized: "Alarm time", comment: "Alarm time picker label"),
                       selection: timeBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        } footer: {
            Text(viewModel.ringsInText)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: DesignTokens.Motion.controls), value: viewModel.hour)
                .animation(.easeInOut(duration: DesignTokens.Motion.controls), value: viewModel.minute)
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section {
            presetBar
                .listRowSeparator(.hidden)
            // Seven circles share the row until the letters outgrow them; then the
            // circles grow with the type and wrap onto a second line.
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    ChipFlow(spacing: DesignTokens.Spacing.xs) {
                        ForEach(weekdayOrder, id: \.self) { dayCircle($0) }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(weekdayOrder, id: \.self) { dayCircle($0).frame(maxWidth: .infinity) }
                    }
                }
            }
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .listRowSeparator(.hidden)

            if viewModel.scheduleMode == .oneTime {
                DatePicker(
                    selection: $viewModel.oneTimeDate,
                    in: Date.now...,
                    displayedComponents: .date
                ) {
                    Text(String(localized: "Date", comment: "One-time date label"))
                        .font(.mcBody)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                .datePickerStyle(.compact)
            }
        } header: {
            Text(String(localized: "Schedule", comment: "Schedule section"))
        } footer: {
            // The presets name themselves; only a hand-picked set needs reading back.
            if viewModel.scheduleMode == .custom {
                Text(viewModel.scheduleSummaryText)
            }
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }

    /// The four common answers in one row; the circles below cover the rest.
    private var presetBar: some View {
        let presets: [(AlarmEditorViewModel.ScheduleMode, String)] = [
            (.oneTime, String(localized: "One-time", comment: "Schedule summary")),
            (.daily, String(localized: "Every day", comment: "Schedule summary")),
            (.weekdays, String(localized: "Weekdays", comment: "Recurrence weekdays")),
            (.weekends, String(localized: "Weekends", comment: "Recurrence weekends")),
        ]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(presets, id: \.0) { presetButton($0.0, $0.1) } }
            VStack(spacing: 6) { ForEach(presets, id: \.0) { presetButton($0.0, $0.1) } }
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private func presetButton(_ mode: AlarmEditorViewModel.ScheduleMode, _ title: String) -> some View {
        let selected = viewModel.scheduleMode == mode
        return Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.22)) {
                switch mode {
                case .oneTime:  viewModel.scheduleMode = .oneTime
                case .daily:    viewModel.applyDays(Set(Weekday.allCases))
                case .weekdays: viewModel.applyDays([.monday, .tuesday, .wednesday, .thursday, .friday])
                case .weekends: viewModel.applyDays([.saturday, .sunday])
                case .custom:   break
                }
            }
        } label: {
            Text(title)
                .font(.system(.footnote, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(selected ? DesignTokens.Colors.background : DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? DesignTokens.Colors.accent : DesignTokens.Colors.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func dayCircle(_ day: Weekday) -> some View {
        let selected = viewModel.effectiveDays.contains(day)
        return Button {
            Haptics.impact(.light)
            withAnimation(.snappy(duration: 0.22)) { viewModel.toggleDay(day) }
        } label: {
            Text(String(day.shortName.prefix(1)).uppercased())
                .font(.system(.subheadline, weight: .heavy).width(.expanded))
                .frame(width: dayCircleSize, height: dayCircleSize)
                .background(Circle().fill(selected ? DesignTokens.Colors.accent : DesignTokens.Colors.surfaceSecondary))
                .foregroundStyle(selected ? DesignTokens.Colors.background : DesignTokens.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        // The circle shows one letter, which VoiceOver would read as "M" — and
        // Tuesday and Thursday would both be "T".
        .accessibilityLabel(day.displayName)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Label

    private var labelSection: some View {
        Section {
            TextField(String(localized: "Name this alarm", comment: "Label placeholder"), text: $viewModel.label)
                .font(.mcBody)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .focused($labelFocused)
                .submitLabel(.done)
                .onSubmit { labelFocused = false }
        } header: {
            Text(String(localized: "Label", comment: "Label section"))
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }

    // MARK: - Missions

    private var missionsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.missions.enumerated()), id: \.offset) { idx, mission in
                        missionTile(index: idx, mission: mission)
                    }
                    if viewModel.missions.count < 3 { addMissionTile }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        } header: {
            Text(String(localized: "Wake Missions", comment: "Missions section"))
        } footer: {
            Text(String(localized: "Up to three, in this order. Touch and hold one to move or remove it.", comment: "Missions section footer"))
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }

    /// One mission of the sequence: its place, its name and settings, and its picture.
    private func missionTile(index: Int, mission: MissionConfig) -> some View {
        Button {
            Haptics.impact(.light)
            missionEditorIndex = index
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("\(index + 1)")
                        .font(.system(.caption, weight: .heavy).width(.expanded))
                        .foregroundStyle(DesignTokens.Colors.ink)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(DesignTokens.Colors.yolk))
                    Spacer(minLength: 0)
                    if !mission.isConfigured {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.yolk)
                            .accessibilityLabel(String(localized: "Setup needed", comment: "Mission setup required badge"))
                    }
                }
                Spacer(minLength: 4)
                MissionArt(kind: mission.kind)
                    .frame(width: 66, height: 44)
                    .padding(.leading, -4)
                Text(mission.displayName)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.onTile)
                    .lineLimit(1)
                Text(mission.isConfigured
                     ? mission.configSummary
                     : String(localized: "Setup needed", comment: "Mission setup required badge"))
                    .font(.mcCaption)
                    .foregroundStyle(mission.isConfigured ? DesignTokens.Colors.onTile.opacity(0.6) : DesignTokens.Colors.yolk)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 132, height: 156, alignment: .topLeading)
            .background(DesignTokens.Colors.tile, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .contextMenu {
            if index > 0 {
                Button {
                    withAnimation(.snappy) { viewModel.missions.swapAt(index, index - 1) }
                } label: {
                    Label(String(localized: "Move Earlier", comment: "Mission tile menu: move one place earlier"), systemImage: "arrow.left")
                }
            }
            if index < viewModel.missions.count - 1 {
                Button {
                    withAnimation(.snappy) { viewModel.missions.swapAt(index, index + 1) }
                } label: {
                    Label(String(localized: "Move Later", comment: "Mission tile menu: move one place later"), systemImage: "arrow.right")
                }
            }
            Button(role: .destructive) {
                withAnimation(.snappy) { _ = viewModel.missions.remove(at: index) }
            } label: {
                Label(String(localized: "Remove", comment: "Mission tile menu: remove from the alarm"), systemImage: "minus.circle")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index + 1). \(mission.displayName)")
        .accessibilityValue(mission.isConfigured ? mission.configSummary : String(localized: "Setup needed", comment: "Mission setup required badge"))
        .accessibilityAddTraits(.isButton)
    }

    private var addMissionTile: some View {
        Button {
            Haptics.impact(.light)
            showMissionPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(DesignTokens.Colors.surfaceSecondary))
                Spacer(minLength: 0)
                Text(String(localized: "Add Mission", comment: "Add mission button"))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(String(localized: "\(viewModel.missions.count) of 3", comment: "Mission count"))
                    .font(.mcCaption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(12)
            .frame(width: 132, height: 156, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: - Sound

    private var soundSection: some View {
        Section {
            ForEach(AlarmSound.allCases, id: \.self) { soundRow($0) }
            volumeRow
            Picker(selection: $viewModel.gradualWakeDuration) {
                ForEach(GradualWakeDuration.allCases, id: \.self) { d in Text(d.displayName).tag(d) }
            } label: {
                Text(String(localized: "Gradual Wake", comment: "Gradual wake label"))
                    .font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            .pickerStyle(.menu)
        } header: {
            Text(String(localized: "Sound", comment: "Sound section"))
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }

    private func soundRow(_ s: AlarmSound) -> some View {
        let isPlaying = previewingSound == s
        let isSelected = s == viewModel.sound
        return Button {
            Haptics.selection()
            viewModel.sound = s
            previewSound(s)
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                    .font(.mcCallout)
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.displayName).font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(s.description).font(.mcFootnote).foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.mcFootnoteSemibold)
                        .foregroundStyle(DesignTokens.Colors.emberText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func previewSound(_ s: AlarmSound) {
        previewPlayer.stop()
        previewingSound = s
        previewPlayer.play(sound: s, volume: viewModel.volume)
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if previewingSound == s {
                previewPlayer.fadeOut(duration: 0.5)
                previewingSound = nil
            }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "speaker").font(.mcFootnote).foregroundStyle(DesignTokens.Colors.textTertiary)
            // Floor matches AlarmManager.minimumVolume — a silent alarm is not an alarm.
            Slider(value: $viewModel.volume, in: AlarmManager.minimumVolume...1, step: 0.05)
                .tint(DesignTokens.Colors.accent)
                .accessibilityLabel(String(localized: "Volume", comment: "Volume slider"))
            Image(systemName: "speaker.wave.3").font(.mcFootnote).foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    // MARK: - Snooze

    private var snoozeSection: some View {
        Section {
            Picker(selection: $viewModel.snooze.durationMinutes) {
                Text(String(localized: "Off", comment: "Snooze off")).tag(0)
                ForEach([3, 5, 10], id: \.self) { m in Text("\(m) min").tag(m) }
            } label: {
                Text(String(localized: "Duration", comment: "Snooze duration label"))
                    .font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            .pickerStyle(.menu)

            if viewModel.snooze.isEnabled {
                Picker(selection: $viewModel.snooze.maxCount) {
                    ForEach(SnoozeConfig.maxCountOptions, id: \.self) { n in
                        Text(n == -1 ? String(localized: "Unlimited", comment: "Unlimited snooze") : "\(n)").tag(n)
                    }
                } label: {
                    Text(String(localized: "Max Snoozes", comment: "Max snooze count label"))
                        .font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text(String(localized: "Snooze", comment: "Snooze section"))
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }

    // MARK: - Wake Check

    private var wakeCheckSection: some View {
        Section {
            Picker(selection: $viewModel.wakeCheck.durationMinutes) {
                ForEach(WakeCheckConfig.durationOptions, id: \.self) { m in
                    Text(m == 0 ? String(localized: "Off", comment: "Wake check off") : "\(m) min").tag(m)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Still Awake?", comment: "Wake check row title"))
                        .font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(String(localized: "Re-rings if you fall back asleep", comment: "Wake check description"))
                        .font(.mcFootnote).foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text(String(localized: "Wake Check", comment: "Wake check section"))
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }

    // MARK: - Manage (edit mode only)

    private var manageSection: some View {
        Section {
            Button {
                Task {
                    if await viewModel.duplicate() { dismiss() } else { showSaveError = true }
                }
            } label: {
                Text(String(localized: "Duplicate Alarm", comment: "Duplicate alarm button"))
                    .font(.mcBody)
                    .foregroundStyle(DesignTokens.Colors.emberText)
            }
            Button(role: .destructive) {
                showDeleteDialog = true
            } label: {
                Text(String(localized: "Delete Alarm", comment: "Delete alarm button"))
                    .font(.mcBody)
                    .foregroundStyle(DesignTokens.Colors.destructive)
            }
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }
}

// MARK: - Identifiable Int for sheet binding

extension Int: @retroactive Identifiable { public var id: Int { self } }

// MARK: - Previews

#Preview("New alarm") {
    AlarmEditorView(mode: .create, manager: AppContainer.preview().alarmManager)
        .environment(AppContainer.preview())
}

#Preview("Edit") {
    AlarmEditorView(mode: .edit(Alarm.samples[0]), manager: AppContainer.preview().alarmManager)
        .environment(AppContainer.preview())
}
