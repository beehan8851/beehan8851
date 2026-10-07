# Dawnwick for Android

The iOS app MorningCompanion ("Dawnwick", SwiftUI) rebuilt as a native Android app:
Kotlin, Jetpack Compose, no cross-platform layer.

## Stages

| # | Stage | State |
|---|-------|-------|
| 1 | Foundation + alarms: model, scheduling, ringing, snooze, re-arms, wake check, editor, missions (Math, Shake, Memory, Typing) | **done** |
| 2 | Remaining missions: Steps, Jump, QR (CameraX + ML Kit), Draw, Catch the cat | **done** |
| 3 | Today: weather (Open-Meteo), calendar, morning brief, streak | **done** |
| 4 | Sleep: tracking, noise monitor, white noise, wind-down, bedtime reminder, Health Connect | **done** |
| 5 | Games: Catch the cat, Laser, Which box?, Cat Naps, Play tab, Today's game | **done** |
| 6 | Onboarding, Premium (RevenueCat paywall, free-tier gates), widgets (Glance: Next Alarm, Cat, Streak, Sleep) | **done**, not yet built: written without an Android SDK |

## How an alarm rings

`AlarmService` is the one write boundary (validate → persist → cancel stale re-arms →
schedule), ported from the iOS `AlarmManager`. `SystemAlarmEngine` schedules with
`AlarmManager.setAlarmClock`, the one Android schedule that fires on time in Doze.
`AlarmReceiver` starts `RingService` (foreground, alarm stream, vibration, full-screen
notification), which opens `RingActivity` over the lock screen.

The iOS invariants are kept (`RingController`):
- the sound stops only when the mission is done or the snooze is scheduled;
- every snooze / re-arm is registered (`ReArmRegistry`) so editing, disabling or
  deleting an alarm cancels all of them;
- while an alarm rings a re-arm two minutes out is always registered, so a killed
  process or a reboot cannot end the ring without the mission;
- reboot, clock and time-zone changes reschedule everything (`RescheduleReceiver`).

## Premium (RevenueCat)

Put RevenueCat's public Google key (`goog_…`, app.revenuecat.com → Project → API keys)
in `local.properties`:

```
revenuecat.key=goog_xxxxxxxx
```

or pass `-PrevenuecatKey=goog_xxxxxxxx`. RevenueCat needs an entitlement `premium`
and an offering `default` with annual and monthly packages. Without a key there is no
store: debug builds run with Premium open so everything can be tried, release builds
run free.

## Build

```
./gradlew :app:testDebugUnitTest      # JVM tests (the Swift suites, ported)
./gradlew :app:assembleRelease
```

Cat Naps makes each day's puzzles from the date with its own SplitMix64, drawing
the numbers in the same order as the Swift code, so a day's puzzle is the same on
Android and iOS (pinned in `CatNapTests`).

Debug builds: `adb shell setprop debug.dawnwick.slowgames 1` slows the games right
down (a cat that sits for a minute, five-minute rounds) for testing by hand.

`gradle.properties` caps the heap at 3 GB: the build machine has 7 GB.
Strings live in `tools/strings.py` (English, Uzbek, Russian); run it after editing.
