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
| 6 | Onboarding, Premium (RevenueCat paywall, free-tier gates, sleep history, Premium missions swapped for Math at ring time on a lapsed account), app icons (activity-alias), widgets (Glance: Next Alarm, Cat, Streak, Sleep), release signing | **done**, not yet built: written without an Android SDK |

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

## Companions

Besides the cat, six companions can stand in for it everywhere but the games: puppy,
chick, canary, lamb, owlet and hamster (`companion/Companions.kt`, drawn in
`ui/cat/CompanionArt.kt` with the cat's eyes and moods, so the cat's own `CatArt` is untouched).
Each has its own voice: an alarm call that replaces the "Meow" tone, three tap sounds and a
calm loop (`res/raw/pet_*.ogg`; sources and licences in `SOUNDS.md`, all CC0).

| Companion | How it opens |
|---|---|
| Cat | free |
| Chick | a 14-morning streak (best streak, kept once earned) |
| Owlet | 7 tracked nights of an hour or more (kept once earned) |
| Puppy, canary, lamb, hamster | Premium, or bought one at a time |

Premium opens every companion. The one-off purchases are non-consumable in-app products in
Google Play, `dawnwick_companion_puppy`, `dawnwick_companion_canary`, `dawnwick_companion_lamb`
and `dawnwick_companion_hamster` (about $1.99 each), added to RevenueCat as products; ownership
is read from RevenueCat's `allPurchasedProductIds`. If Premium ends, a bought or earned companion
stays; a companion that came only with Premium gives way to the cat until Premium returns.

## Release signing

Create `keystore.properties` next to `settings.gradle.kts` (it is git-ignored):

```
storeFile=/full/path/to/dawnwick.jks
storePassword=...
keyAlias=dawnwick
keyPassword=...
```

Without it, release builds are signed with the debug key: they install on a phone but
Google Play refuses them.

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
Strings live in `tools/strings.py` (English, Uzbek, Russian) and `tools/translations/*.json`
(German, Spanish, French, Italian, Japanese, Korean, Brazilian Portuguese, Turkish, Simplified
and Traditional Chinese: the iOS app's languages). Run `python3 tools/strings.py` after editing
either; never edit the generated `strings.xml`. Most of the ten come from the iOS app's
translations; the Android-only strings were translated without a native speaker and are worth
a review. Android 13+ lists every language in the app's system language setting.
