import SwiftUI
import os

@main
struct MorningCompanionApp: App {
    @State private var appContainer = AppContainer.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BrandAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appContainer)
                // Onboarding is yolk and paper whatever the setting: it is the first
                // look at the app, and it should look like the icon that was tapped.
                .preferredColorScheme(appContainer.hasCompletedOnboarding
                                      ? appContainer.appPreferences.appearance.colorScheme
                                      : .light)
                // No authorization request here on purpose. iOS asks once, and a
                // prompt that arrives before the user has read a word is answered
                // "Don't Allow" often enough to matter — after which nothing in the
                // app can ask again. Onboarding asks, behind a button that says why;
                // for anyone already past onboarding, AlarmKitAlarmService requests it
                // when the first alarm is actually scheduled.
                .task {
                    DiagnosticsReporter.shared.start()
                    await appContainer.bootstrapAlarmKit()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                appContainer.onEnterForeground()
            case .background:
                appContainer.onLeaveForeground()
            default:
                break
            }
        }
    }
}
