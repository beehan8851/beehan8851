import Foundation
import Testing
import UserNotifications
@testable import MorningCompanion

/// The onboarding flow's decisions, without a device that has real permissions.
///
/// What is worth pinning down here is the order of the steps, what happens when a user
/// refuses — the case a simulator run never reaches by accident — and that the alarm
/// the user builds on the last screen is the alarm that gets saved.
@Suite("Onboarding")
@MainActor
struct OnboardingModelTests {

    private func makeModel(
        alarm: AlarmKitAuthorizationState = .notDetermined,
        notifications: UNAuthorizationStatus = .notDetermined,
        alarmOnRequest: AlarmKitAuthorizationState = .authorized,
        notificationsOnRequest: UNAuthorizationStatus = .authorized
    ) -> OnboardingModel {
        OnboardingModel(permissions: StubOnboardingPermissions(state: .init(
            alarm: alarm,
            notifications: notifications,
            alarmOnRequest: alarmOnRequest,
            notificationsOnRequest: notificationsOnRequest
        )))
    }

    private func makeManager() -> AlarmManager {
        // Empty, not the sample list: two seeded alarms would hit the free-tier
        // limit and the first alarm would be rejected for the wrong reason.
        AlarmManager(repository: MockAlarmRepository(alarms: []), engine: StubAlarmEngineService())
    }

    // MARK: - Steps

    @Test("Starts on the welcome step and advances in order")
    func stepOrder() {
        let model = makeModel()
        #expect(model.step == .welcome)
        model.advance()
        #expect(model.step == .permissions)
        model.advance()
        #expect(model.step == .firstAlarm)
        #expect(model.isLastStep)
    }

    @Test("Advancing past the last step does nothing")
    func advancePastEnd() {
        let model = makeModel()
        model.go(to: .firstAlarm)
        model.advance()
        #expect(model.step == .firstAlarm)
    }

    // MARK: - Permissions

    @Test("Nothing is requested until the user asks for it")
    func noRequestOnRefresh() async {
        let model = makeModel()
        await model.refreshPermissions()
        #expect(model.alarmAuthorization == .notDetermined)
        #expect(model.notificationAuthorization == .notDetermined)
        #expect(!model.hasDecidedAlarmPermission)
    }

    @Test("Granting both permissions lets alarms ring")
    func bothGranted() async {
        let model = makeModel()
        await model.requestPermissions()
        #expect(model.canAlarmsRing)
        #expect(!model.isAnyPermissionDenied)
        #expect(model.permissionsAreSettled)
    }

    @Test("Refusing alarms is surfaced, not swallowed")
    func alarmDenied() async {
        let model = makeModel(alarmOnRequest: .denied)
        await model.requestPermissions()
        #expect(!model.canAlarmsRing)
        #expect(model.isAnyPermissionDenied)
        // Decided, so the screen stops offering to ask again — iOS would not prompt.
        #expect(model.hasDecidedAlarmPermission)
    }

    @Test("Refusing notifications alone still leaves alarms working")
    func notificationsDeniedOnly() async {
        let model = makeModel(notificationsOnRequest: .denied)
        await model.requestPermissions()
        #expect(model.canAlarmsRing)
        #expect(model.isAnyPermissionDenied)
    }

    @Test("A permission already decided before onboarding is not asked for again")
    func previouslyDecided() async {
        let model = makeModel(alarm: .denied, notifications: .authorized)
        await model.refreshPermissions()
        #expect(model.hasDecidedAlarmPermission)
        await model.requestPermissions()
        #expect(model.alarmAuthorization == .denied)   // the stub would have granted it
    }

    // MARK: - First alarm

    @Test("The alarm saved is the one the user built")
    func firstAlarmMatchesChoices() async {
        let model = makeModel()
        model.wakeTime = AlarmTime(hour: 6, minute: 15)
        model.mission = .shake

        let manager = makeManager()
        #expect(await model.saveFirstAlarm(using: manager))

        let saved = try? await manager.fetchAll()
        #expect(saved?.count == 1)
        #expect(saved?.first?.wallClockTime == AlarmTime(hour: 6, minute: 15))
        #expect(saved?.first?.recurrence == .daily)
        #expect(saved?.first?.missions.first?.kind == .shake)
        #expect(saved?.first?.isEnabled == true)
    }

    @Test("Every mission onboarding offers produces a saveable alarm")
    func everyOfferedMissionSaves() async {
        for kind in [MissionKind.math, .shake] {
            let model = makeModel()
            model.mission = kind
            #expect(await model.saveFirstAlarm(using: makeManager()), "\(kind) was rejected")
        }
    }

    @Test("Onboarding missions use their gentlest setting")
    func gentleDefaults() {
        #expect(MissionKind.math.onboardingConfig == .math(difficulty: .easy, rounds: 1))
        if case .shake(let count) = MissionKind.shake.onboardingConfig {
            #expect(count == 15)
        } else {
            Issue.record("shake did not produce a shake config")
        }
    }

    @Test("A save failure keeps the user on the step with a reason")
    func saveFailureIsReported() async {
        let model = makeModel()
        model.wakeTime = AlarmTime(hour: 25, minute: 0)   // rejected by validation
        let manager = makeManager()
        #expect(await model.saveFirstAlarm(using: manager) == false)
        #expect(model.alarmSaveError != nil)
    }
}
