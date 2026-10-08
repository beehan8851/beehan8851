package uz.ata.dawnwick.widgets

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import uz.ata.dawnwick.MainActivity
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.NextAlarmCalculator
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.sleep.SleepHistory
import uz.ata.dawnwick.streak.DayOutcome
import uz.ata.dawnwick.streak.StreakDays
import uz.ata.dawnwick.ui.format.TimeFormat
import java.time.LocalDate
import java.time.LocalTime

/*
 * The four home-screen widgets of the iOS app: Next Alarm and Cat for everyone,
 * Streak and Sleep for Premium (a free account sees a locked face that opens the
 * paywall). Each reads the app's own store when Android asks it to draw.
 */

private val Yolk = Color(0xFFFFC629)
private val Ink = Color(0xFF1B1A17)
private val OnYolkSecondary = Color(0xFF5F4E1C)
private val NightSecondary = Color(0xFFA8A39A)
private val Paper = Color(0xFFF4F2ED)

private fun c(color: Color) = ColorProvider(color)

private fun openApp(context: Context, tab: Int = -1, paywall: Boolean = false) =
    actionStartActivity(
        Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(MainActivity.EXTRA_TAB, tab)
            .putExtra(MainActivity.EXTRA_PAYWALL, paywall),
    )

/** Redraws every widget: after an alarm is saved, a morning won, a night tracked, Premium changed. */
object DawnWidgets {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    fun refresh(context: Context) {
        val app = context.applicationContext
        scope.launch {
            runCatching {
                NextAlarmWidget().updateAll(app)
                CatWidget().updateAll(app)
                StreakWidget().updateAll(app)
                SleepWidget().updateAll(app)
            }
        }
    }
}

private fun nextAlarm(alarms: List<Alarm>): Pair<Alarm, Long>? =
    alarms.filter { it.isEnabled }
        .mapNotNull { a -> NextAlarmCalculator.nextFireTime(a)?.let { a to it.toEpochMilli() } }
        .minByOrNull { it.second }

// MARK: - Next Alarm

class NextAlarmWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val next = nextAlarm(context.graph.alarmService.fetchAll())
        val time = next?.let { TimeFormat.clock(context, it.second) }
        val label = next?.first?.label?.takeIf { it.isNotBlank() }
        val missions = next?.first?.missions?.size ?: 0
        provideContent {
            Column(
                GlanceModifier.fillMaxSize().background(c(Yolk)).cornerRadius(22.dp).padding(14.dp)
                    .clickable(openApp(context, tab = 1)),
            ) {
                Text(context.getString(R.string.widget_next_alarm).uppercase(), style = TextStyle(c(OnYolkSecondary), 11.sp, FontWeight.Bold))
                Spacer(GlanceModifier.height(4.dp))
                if (time == null) {
                    Text(context.getString(R.string.no_alarm_set), style = TextStyle(c(Ink), 20.sp, FontWeight.Bold))
                    Text(context.getString(R.string.widget_tap_to_set), style = TextStyle(c(OnYolkSecondary), 13.sp))
                } else {
                    Text(time, style = TextStyle(c(Ink), 34.sp, FontWeight.Bold))
                    label?.let { Text(it, style = TextStyle(c(Ink), 14.sp, FontWeight.Medium), maxLines = 1) }
                    if (missions > 0) Text("🐾".repeat(missions), style = TextStyle(c(Ink), 13.sp))
                }
            }
        }
    }
}

class NextAlarmWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = NextAlarmWidget() }

// MARK: - Cat

class CatWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val graph = context.graph
        val alarms = graph.alarmService.fetchAll()
        val next = nextAlarm(alarms)
        val record = graph.streak.load()
        val today = LocalDate.now()
        val streak = record.liveStreak(today, graph.streak.scheduled(alarms))
        val hour = LocalTime.now().hour
        val night = hour >= 21 || hour < 5
        val wonToday = record.isCompleted(today)
        val missedLast = !wonToday && record.lastCompletion != null && streak == 0 && record.currentStreak > 0
        val line = when {
            night && next != null -> context.getString(R.string.widget_cat_asleep_until, TimeFormat.clock(context, next.second))
            night -> context.getString(R.string.widget_cat_asleep)
            wonToday && streak > 1 -> context.getString(R.string.widget_cat_won_day, streak)
            wonToday -> context.getString(R.string.widget_cat_won)
            missedLast -> context.getString(R.string.widget_cat_missed)
            next != null -> context.getString(R.string.widget_cat_ready)
            else -> context.getString(R.string.widget_cat_no_alarm)
        }
        // The cat's face from the app icons: asleep at night, proud on a won morning, unimpressed after a missed one.
        val face = when {
            night -> R.drawable.icon_preview_night
            wonToday -> R.drawable.icon_preview_proud
            missedLast -> R.drawable.icon_preview_unimpressed
            else -> R.drawable.icon_preview_classic
        }
        provideContent {
            Column(
                GlanceModifier.fillMaxSize().background(c(if (night) Ink else Yolk)).cornerRadius(22.dp).padding(12.dp)
                    .clickable(openApp(context, tab = 0)),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Image(ImageProvider(face), null, GlanceModifier.size(84.dp).cornerRadius(18.dp))
                Text(line, style = TextStyle(c(if (night) Paper else Ink), 14.sp, FontWeight.Bold), maxLines = 2)
            }
        }
    }
}

class CatWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = CatWidget() }

// MARK: - Premium faces

@Composable
private fun LockedFace(context: Context, title: Int) {
    Column(
        GlanceModifier.fillMaxSize().background(c(Ink)).cornerRadius(22.dp).padding(14.dp)
            .clickable(openApp(context, paywall = true)),
    ) {
        Text(context.getString(title).uppercase(), style = TextStyle(c(Yolk), 11.sp, FontWeight.Bold))
        Spacer(GlanceModifier.height(6.dp))
        Text(context.getString(R.string.widget_locked), style = TextStyle(c(Paper), 14.sp, FontWeight.Medium))
    }
}

// MARK: - Streak

class StreakWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val graph = context.graph
        val premium = graph.isPremium
        val alarms = graph.alarmService.fetchAll()
        val record = graph.streak.load()
        val today = LocalDate.now()
        val streak = record.liveStreak(today, graph.streak.scheduled(alarms))
        val week = StreakDays.week(today, record, alarms, graph.streak.since())
        provideContent {
            if (!premium) { LockedFace(context, R.string.widget_streak); return@provideContent }
            Column(
                GlanceModifier.fillMaxSize().background(c(Yolk)).cornerRadius(22.dp).padding(14.dp)
                    .clickable(openApp(context, tab = 0)),
            ) {
                Text(context.getString(R.string.widget_streak).uppercase(), style = TextStyle(c(OnYolkSecondary), 11.sp, FontWeight.Bold))
                Text("$streak", style = TextStyle(c(Ink), 40.sp, FontWeight.Bold))
                Text(context.getString(R.string.widget_days_in_row, streak), style = TextStyle(c(Ink), 13.sp, FontWeight.Medium))
                Spacer(GlanceModifier.height(6.dp))
                Row {
                    week.forEach { day ->
                        val mark = when (day.outcome) {
                            DayOutcome.WON -> "🐾"
                            DayOutcome.COVERED -> "🐱"
                            DayOutcome.MISSED -> "·"
                            DayOutcome.TODAY -> "○"
                            else -> "·"
                        }
                        Text(mark, style = TextStyle(c(Ink), 13.sp), modifier = GlanceModifier.width(20.dp))
                    }
                }
                if (record.bestStreak > 0) Text(context.getString(R.string.widget_best, record.bestStreak), style = TextStyle(c(OnYolkSecondary), 12.sp))
            }
        }
    }
}

class StreakWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = StreakWidget() }

// MARK: - Sleep

class SleepWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val graph = context.graph
        val premium = graph.isPremium
        // The phone's own nights; Health Connect needs the app in front to be read.
        val nights = SleepHistory.merge(graph.sleep.repository.loadCompleted(), emptyList())
        val last = nights.firstOrNull { it.date == LocalDate.now() }?.durationMillis
        val week = nights.filter { it.date.isAfter(LocalDate.now().minusDays(7)) }.mapNotNull { it.durationMillis }
        val average = week.takeIf { it.isNotEmpty() }?.average()?.toLong()
        fun hm(millis: Long): String {
            val minutes = (millis / 60_000).toInt()
            return context.getString(R.string.widget_hours_minutes, minutes / 60, minutes % 60)
        }
        provideContent {
            if (!premium) { LockedFace(context, R.string.widget_sleep); return@provideContent }
            Column(
                GlanceModifier.fillMaxSize().background(c(Ink)).cornerRadius(22.dp).padding(14.dp)
                    .clickable(openApp(context, tab = 2)),
            ) {
                Text(context.getString(R.string.widget_last_night).uppercase(), style = TextStyle(c(Yolk), 11.sp, FontWeight.Bold))
                Spacer(GlanceModifier.height(4.dp))
                if (last == null && average == null) {
                    Text(context.getString(R.string.widget_no_nights), style = TextStyle(c(Paper), 16.sp, FontWeight.Bold))
                } else {
                    Text(last?.let(::hm) ?: "—", style = TextStyle(c(Paper), 30.sp, FontWeight.Bold))
                    average?.let { Text(context.getString(R.string.widget_average, hm(it)), style = TextStyle(c(NightSecondary), 13.sp)) }
                }
            }
        }
    }
}

class SleepWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = SleepWidget() }
