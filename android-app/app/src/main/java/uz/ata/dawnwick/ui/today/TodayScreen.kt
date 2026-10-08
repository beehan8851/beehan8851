package uz.ata.dawnwick.ui.today

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Bed
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.LocationOff
import androidx.compose.material.icons.rounded.WbCloudy
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.ActivityCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.NextAlarmCalculator
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.streak.CatTrick
import uz.ata.dawnwick.streak.DayCell
import uz.ata.dawnwick.streak.DayOutcome
import uz.ata.dawnwick.streak.StreakDays
import uz.ata.dawnwick.streak.StreakRecord
import uz.ata.dawnwick.today.CalendarReader
import uz.ata.dawnwick.today.Locator
import uz.ata.dawnwick.today.WeatherProblem
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.TappableCat
import uz.ata.dawnwick.ui.components.AlarmTimeText
import uz.ata.dawnwick.ui.components.keepAboveKeyboard
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.missions.Camera
import uz.ata.dawnwick.ui.missions.missionNameRes
import uz.ata.dawnwick.ui.permissions.PermissionBanner
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/**
 * Today: the next alarm under the cat, the week as paw prints, then the facts of the
 * morning — calendar and weather — and one line of focus.
 *
 * The cat is the status: asleep when tonight's alarm is set, pleased once the
 * morning is won, unimpressed after a miss, awake otherwise. Nothing here asks for
 * a permission on its own; the rows offer, and the tap is the consent.
 */
@Composable
fun TodayScreen(alarms: List<Alarm>, onAddAlarm: () -> Unit, onAllGames: () -> Unit = {}) {
    val context = LocalContext.current
    val activity = context as? Activity
    val graph = context.graph
    val scope = rememberCoroutineScope()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var brief by remember { mutableStateOf(graph.brief.cached()) }
    var record by remember { mutableStateOf(graph.streak.load()) }
    var focus by remember { mutableStateOf(graph.brief.focus()) }
    var weatherOpen by remember { mutableStateOf(false) }
    var streakOpen by remember { mutableStateOf(false) }
    var permissionTick by remember { mutableLongStateOf(0) }
    var playing by remember { mutableStateOf<uz.ata.dawnwick.ui.games.MorningGame?>(null) }
    var gameRevision by remember { mutableIntStateOf(0) }

    var slept by remember { mutableStateOf<Long?>(null) }
    fun refresh() {
        now = System.currentTimeMillis()
        record = graph.streak.settle(alarms)
        scope.launch { brief = graph.brief.refresh() }
        // Last night: the longest of what was tracked here since yesterday and what Health Connect has for today.
        scope.launch {
            val zone = java.time.ZoneId.systemDefault()
            val since = LocalDate.now(zone).minusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
            val local = graph.sleep.repository.loadCompleted().filter { it.startMillis >= since }.mapNotNull { it.durationMillis }.maxOrNull()
            val health = graph.health.history(1).firstOrNull { it.date == LocalDate.now(zone) }?.durationMillis
            slept = listOfNotNull(local, health).maxOrNull()
        }
    }
    LifecycleResumeEffect(alarms) {
        refresh()
        onPauseOrDispose { }
    }
    LaunchedEffect(Unit) { while (true) { delay(30_000); now = System.currentTimeMillis() } }

    val prefs = graph.store
    val locationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { prefs.putBoolean(ASKED_LOCATION, true); permissionTick++; refresh() }
    val calendarLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { prefs.putBoolean(ASKED_CALENDAR, true); permissionTick++; refresh() }

    val today = LocalDate.now()
    val since = remember { graph.streak.since() }
    val hadAlarm = StreakRecord.scheduledBy(alarms, since)
    val week = StreakDays.week(today, record, alarms, since)
    val live = record.liveStreak(today, hadAlarm)
    val wokeToday = record.isCompleted(today)
    val next = alarms.mapNotNull { a -> NextAlarmCalculator.nextFireTime(a)?.let { a to it.toEpochMilli() } }.minByOrNull { it.second }
    val mood = heroMood(wokeToday, week, next != null)

    // A won morning: the cat leaps by itself a moment after Today opens, and at 3, 7
    // and 30 mornings the store's rating sheet is offered — never on a bad morning.
    val wonStreak = if (wokeToday) live else 0
    var celebration by remember { mutableIntStateOf(0) }
    LaunchedEffect(wonStreak) {
        if (wonStreak <= 0) return@LaunchedEffect
        delay(600)
        celebration++
        if (wonStreak in REVIEW_MILESTONES && !prefs.getBoolean("review.asked.$wonStreak")) {
            prefs.putBoolean("review.asked.$wonStreak", true)
            delay(900)
            activity?.let { a ->
                val manager = com.google.android.play.core.review.ReviewManagerFactory.create(a)
                manager.requestReviewFlow().addOnSuccessListener { info -> manager.launchReviewFlow(a, info) }
            }
        }
    }

    // The page shrinks to the space above the keyboard, so the focus line can scroll up into view.
    Column(Modifier.fillMaxSize().background(Dawn.colors.background).imePadding().verticalScroll(rememberScrollState()).padding(bottom = Spacing.l)) {
        Text(
            stringResource(R.string.tab_today),
            style = DawnType.display(34), color = Dawn.colors.textPrimary,
            modifier = Modifier.padding(start = Spacing.s, top = Spacing.s),
        )
        Text(
            today.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(Locale.getDefault())),
            style = DawnType.callout, color = Dawn.colors.textSecondary,
            modifier = Modifier.padding(start = Spacing.s, bottom = Spacing.xs),
        )
        PermissionBanner()
        Column(Modifier.padding(horizontal = Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.l)) {
            Hero(mood, next, now, live, if (mood == CatMood.PROUD) celebration else 0, onAddAlarm)
            StreakCard(live, week, record) { streakOpen = true }

            // One of the morning games, a different one each day, and the way to the rest.
            val game = uz.ata.dawnwick.ui.games.MorningGame.ofTheDay(today)
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.todays_game).uppercase(), style = DawnType.section, color = Dawn.colors.textSecondary,
                        modifier = Modifier.padding(start = 4.dp).weight(1f))
                    Text(stringResource(R.string.all_games), style = DawnType.headline.copy(fontSize = 15.sp), color = Dawn.colors.accent,
                        modifier = Modifier.pressable(onClick = onAllGames).padding(vertical = 10.dp, horizontal = 4.dp))
                }
                val gameBest = remember(gameRevision, game) { game.best(graph.store) }
                uz.ata.dawnwick.ui.games.GameCard(game, gameBest) { playing = game }
            }

            // Calendar, then weather: each shows its fact or offers to fetch it.
            val rows = mutableListOf<@Composable () -> Unit>()
            val calendarAllowed = remember(permissionTick) { CalendarReader.allowed(context) }
            val event = brief.event
            if (event != null) {
                rows += { InfoRow(Icons.Rounded.CalendarMonth, event.title, TimeFormat.clock(context, event.startMillis)) }
            } else if (!calendarAllowed && !prefs.getBoolean(ASKED_CALENDAR)) {
                rows += { OfferRow(Icons.Rounded.CalendarMonth, stringResource(R.string.calendar_offer), stringResource(R.string.calendar_connect)) { calendarLauncher.launch(CalendarReader.PERMISSION) } }
            }
            val weather = brief.weather
            val locationAllowed = remember(permissionTick) { Locator.allowed(context) }
            if (weather != null) {
                rows += {
                    InfoRow(WeatherStyle.icon(weather.code, weather.isDay),
                        "${WeatherStyle.degrees(weather.temperature)}°  ${stringResource(WeatherStyle.description(weather.code))}",
                        stringResource(R.string.high_low, WeatherStyle.degrees(weather.high), WeatherStyle.degrees(weather.low)),
                        onClick = { weatherOpen = true })
                }
            } else if (!locationAllowed) {
                val refused = prefs.getBoolean(ASKED_LOCATION) && activity != null &&
                    !ActivityCompat.shouldShowRequestPermissionRationale(activity, Locator.PERMISSION)
                if (refused) {
                    rows += { OfferRow(Icons.Rounded.LocationOff, stringResource(R.string.weather_location_off), stringResource(R.string.turn_on)) { Camera.openAppSettings(context) } }
                } else {
                    rows += { OfferRow(Icons.Rounded.WbCloudy, stringResource(R.string.weather_offer), stringResource(R.string.weather_add)) { locationLauncher.launch(Locator.PERMISSION) } }
                }
            } else if (brief.weatherProblem != null) {
                rows += { InfoRow(Icons.Rounded.WbCloudy, stringResource(if (brief.weatherProblem == WeatherProblem.LOCATION) R.string.weather_no_location else R.string.weather_unavailable), null) }
            }
            slept?.let { ms ->
                rows += { InfoRow(Icons.Rounded.Bed, stringResource(R.string.slept, uz.ata.dawnwick.ui.sleep.sleepDuration(ms)), null) }
            }
            if (rows.isNotEmpty()) {
                SectionTitle(stringResource(R.string.today_section)) {
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary)) {
                        rows.forEachIndexed { i, row ->
                            if (i > 0) Box(Modifier.padding(start = 52.dp).fillMaxWidth().height(0.5.dp).background(Dawn.colors.separator))
                            row()
                        }
                    }
                }
            }

            SectionTitle(stringResource(R.string.focus_title)) {
                val focusManager = LocalFocusManager.current
                OutlinedTextField(
                    value = focus,
                    onValueChange = { focus = it.take(140); graph.brief.saveFocus(focus) },
                    placeholder = { Text(stringResource(R.string.focus_placeholder), color = Dawn.colors.textTertiary) },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                    shape = RoundedCornerShape(Radius.m),
                    colors = OutlinedTextFieldDefaults.colors(
                        unfocusedContainerColor = Dawn.colors.surfacePrimary, focusedContainerColor = Dawn.colors.surfacePrimary,
                        unfocusedBorderColor = Dawn.colors.surfacePrimary, focusedBorderColor = Dawn.colors.accent,
                    ),
                    modifier = Modifier.fillMaxWidth().keepAboveKeyboard(),
                )
            }
        }
    }

    val w = brief.weather
    if (weatherOpen && w != null) WeatherDetail(w) { weatherOpen = false }
    if (streakOpen) StreakPage(record, live, alarms, since) { streakOpen = false }
    playing?.let { g -> uz.ata.dawnwick.ui.games.GameHost(g) { playing = null; gameRevision++ } }
}

private val REVIEW_MILESTONES = setOf(3, 7, 30)
private const val ASKED_LOCATION = "today.asked.location"
private const val ASKED_CALENDAR = "today.asked.calendar"

/** How the cat is doing: the morning first, then the clock. */
private fun heroMood(wokeToday: Boolean, week: List<DayCell>, hasAlarm: Boolean): CatMood {
    if (wokeToday) return CatMood.PROUD
    if (week.lastOrNull { it.outcome == DayOutcome.WON || it.outcome == DayOutcome.MISSED }?.outcome == DayOutcome.MISSED) return CatMood.GRUMPY
    if (!hasAlarm) return CatMood.AWAKE
    val hour = LocalTime.now().hour
    return if (hour >= 19 || hour < 5) CatMood.SLEEPING else CatMood.AWAKE
}

/**
 * The band: the next alarm and the cat. Yolk by day, ink at night while the cat
 * sleeps — and always ink in the dark theme, where a page of yellow is a lamp.
 */
@Composable
private fun Hero(mood: CatMood, next: Pair<Alarm, Long>?, now: Long, streak: Int, cue: Int, onAddAlarm: () -> Unit) {
    val context = LocalContext.current
    val night = mood == CatMood.SLEEPING || Dawn.colors.isDark
    val primary = if (night) DawnColors.Paper else DawnColors.Ink
    val secondary = if (night) DawnColors.NightTextSecondary else DawnColors.OnYolkSecondary
    val timeColor = if (night) DawnColors.Yolk else DawnColors.Ink
    Column(
        Modifier.fillMaxWidth().defaultMinSize(minHeight = 236.dp).clip(RoundedCornerShape(Radius.xl))
            .background(if (night) DawnColors.Ink else DawnColors.Yolk).padding(horizontal = 20.dp, vertical = Spacing.s),
    ) {
        if (next != null) {
            val (alarm, fire) = next
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(relativeDay(context, fire), style = DawnType.headline, color = secondary, modifier = Modifier.weight(1f))
                Text(stringResource(R.string.rings_in, TimeFormat.until(context, fire - now)), style = DawnType.callout.copy(fontWeight = FontWeight.Bold),
                    color = if (night) DawnColors.Yolk else DawnColors.Ink)
            }
            AlarmTimeText(alarm.wallClockTime, 76, timeColor, periodColor = secondary)
        } else {
            Text(stringResource(R.string.no_alarm_set), style = DawnType.title, color = primary)
            Text(stringResource(R.string.no_alarm_detail), style = DawnType.callout, color = secondary)
            Spacer(Modifier.height(Spacing.xs))
            Box(
                Modifier.clip(RoundedCornerShape(12.dp)).background(if (night) DawnColors.Yolk else DawnColors.Ink)
                    .pressable(onClick = onAddAlarm).padding(horizontal = Spacing.m, vertical = 13.dp),
            ) { Text(stringResource(R.string.set_an_alarm), style = DawnType.button, color = if (night) DawnColors.Ink else DawnColors.Yolk) }
        }
        Spacer(Modifier.weight(1f, fill = false).height(Spacing.s))
        Row(verticalAlignment = Alignment.Bottom) {
            Column(Modifier.weight(1f).padding(bottom = Spacing.xs)) {
                next?.first?.let { alarm ->
                    val summary = (listOf(alarm.label) + alarm.missions.joinToString(", ") { context.getString(missionNameRes(it.kind)) })
                        .filter { it.isNotBlank() }.joinToString(" · ")
                    if (summary.isNotEmpty()) Text(summary, style = DawnType.callout, color = secondary, maxLines = 2)
                }
                val line = when (mood) {
                    CatMood.SLEEPING -> stringResource(R.string.cat_line_sleeping)
                    CatMood.PROUD -> if (streak > 0) stringResource(R.string.cat_line_proud, streak) else null
                    CatMood.GRUMPY -> stringResource(R.string.cat_line_grumpy)
                    else -> null
                }
                if (line != null) Text(line, style = DawnType.callout.copy(fontWeight = FontWeight.SemiBold), color = primary)
            }
            // Tap it: it hops; stroke it: it purrs. On a won morning it leaps by itself.
            TappableCat(mood, if (mood == CatMood.SLEEPING) 132.dp else 104.dp, ground = if (night) CatGround.DARK else CatGround.LIGHT, cue = cue)
        }
    }
}

/** "Today", "Tomorrow", or the weekday. */
private fun relativeDay(context: android.content.Context, millis: Long): String {
    val day = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate()
    val today = LocalDate.now()
    return when (day) {
        today -> context.getString(R.string.day_today)
        today.plusDays(1) -> context.getString(R.string.day_tomorrow)
        else -> context.resources.getStringArray(R.array.weekday_long)[day.dayOfWeek.value % 7]
    }
}

@Composable
private fun SectionTitle(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Text(title.uppercase(), style = DawnType.section, color = Dawn.colors.textSecondary, modifier = Modifier.padding(start = 4.dp))
        content()
    }
}

/** The streak, the week as paw prints, the next trick and the covers. Opens the streak page. */
@Composable
private fun StreakCard(live: Int, week: List<DayCell>, record: StreakRecord, onOpen: () -> Unit) {
    val colors = Dawn.colors
    SectionTitle(stringResource(R.string.streak_title)) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(colors.surfacePrimary).pressable(onClick = onOpen).padding(Spacing.s),
            verticalArrangement = Arrangement.spacedBy(Spacing.s),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    if (live > 0) StreakNumber(live, 40) else
                        Text(stringResource(R.string.streak_empty), style = DawnType.callout, color = colors.textSecondary)
                }
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = colors.textTertiary)
            }
            WeekStrip(week)
            val trick = CatTrick.next(record.bestStreak)
            if (trick != null || record.covers > 0) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (trick != null) Text(stringResource(R.string.next_trick, trick.days, stringResource(trickName(trick))),
                        style = DawnType.footnote.copy(fontWeight = FontWeight.SemiBold), color = colors.textSecondary, modifier = Modifier.weight(1f))
                    else Spacer(Modifier.weight(1f))
                    repeat(record.covers) { DayGlyph(DayOutcome.COVERED, Modifier.size(18.dp)) }
                }
            }
        }
    }
}

/** "12 days in a row", the number set large. */
@Composable
fun StreakNumber(days: Int, size: Int) {
    val words = LocalContext.current.resources.getQuantityString(R.plurals.days_in_a_row, days, days)
    val (before, after) = words.split("$days", limit = 2).let { it[0].trim() to it.getOrElse(1) { "" }.trim() }
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        if (before.isNotEmpty()) Text(before, style = DawnType.callout, color = Dawn.colors.textSecondary, modifier = Modifier.padding(bottom = 6.dp))
        Text("$days", style = DawnType.display(size), color = Dawn.colors.textPrimary)
        Text(after, style = DawnType.callout, color = Dawn.colors.textSecondary, modifier = Modifier.padding(bottom = 6.dp))
    }
}

@Composable
private fun InfoRow(icon: ImageVector, title: String, trailing: String?, onClick: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).let { if (onClick != null) it.pressable(onClick = onClick) else it }.padding(horizontal = Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = Dawn.colors.accent, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(Spacing.sm))
        Text(title, style = DawnType.body, color = Dawn.colors.textPrimary, maxLines = 2, modifier = Modifier.weight(1f))
        if (trailing != null) Text(trailing, style = DawnType.callout, color = Dawn.colors.textSecondary, modifier = Modifier.padding(start = Spacing.xs))
        if (onClick != null) Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = Dawn.colors.textTertiary)
    }
}

@Composable
private fun OfferRow(icon: ImageVector, text: String, action: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).padding(start = Spacing.s, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Dawn.colors.textTertiary, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(Spacing.sm))
        Text(text, style = DawnType.body, color = Dawn.colors.textSecondary, modifier = Modifier.weight(1f))
        TextButton(onClick = onClick) { Text(action, color = Dawn.colors.accent, fontWeight = FontWeight.Bold) }
    }
}

fun trickName(t: CatTrick) = when (t) {
    CatTrick.WAVE -> R.string.trick_wave
    CatTrick.SOMERSAULT -> R.string.trick_somersault
    CatTrick.LEAP -> R.string.trick_leap
    CatTrick.SPARKLE -> R.string.trick_sparkle
    CatTrick.COLLAR -> R.string.trick_collar
    CatTrick.MEDAL -> R.string.trick_medal
}

fun trickDetail(t: CatTrick, pet: uz.ata.dawnwick.companion.Pet = uz.ata.dawnwick.companion.Pet.CAT) = when (t) {
    CatTrick.WAVE -> if (pet == uz.ata.dawnwick.companion.Pet.CAT) R.string.trick_wave_detail else R.string.trick_wave_detail_pet
    CatTrick.SOMERSAULT -> R.string.trick_somersault_detail
    CatTrick.LEAP -> R.string.trick_leap_detail
    CatTrick.SPARKLE -> R.string.trick_sparkle_detail
    CatTrick.COLLAR -> if (pet == uz.ata.dawnwick.companion.Pet.CAT) R.string.trick_collar_detail else R.string.trick_collar_detail_pet
    CatTrick.MEDAL -> R.string.trick_medal_detail
}

