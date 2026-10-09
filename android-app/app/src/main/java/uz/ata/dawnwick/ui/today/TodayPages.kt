package uz.ata.dawnwick.ui.today

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Share
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import uz.ata.dawnwick.ui.cat.CatTricksProvider
import uz.ata.dawnwick.ui.cat.LocalCatDressing
import uz.ata.dawnwick.ui.cat.TappableCat
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AcUnit
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Dehaze
import androidx.compose.material.icons.rounded.FilterDrama
import androidx.compose.material.icons.rounded.Grain
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Thunderstorm
import androidx.compose.material.icons.rounded.Umbrella
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.text.util.LocalePreferences
import java.time.LocalDate
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.roundToInt
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.streak.CatTrick
import uz.ata.dawnwick.streak.DayCell
import uz.ata.dawnwick.streak.DayOutcome
import uz.ata.dawnwick.streak.StreakDays
import uz.ata.dawnwick.streak.StreakRecord
import uz.ata.dawnwick.today.WeatherConditions
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.Shapes
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnTheme
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/** The WMO weather codes as icons, words and the reader's units. */
object WeatherStyle {
    fun icon(code: Int, isDay: Boolean): ImageVector = when (code) {
        0, 1 -> if (isDay) Icons.Rounded.WbSunny else Icons.Rounded.NightsStay
        2 -> if (isDay) Icons.Rounded.FilterDrama else Icons.Rounded.NightsStay
        45, 48 -> Icons.Rounded.Dehaze
        51, 53, 55, 56, 57 -> Icons.Rounded.Grain
        61, 63, 65, 66, 67, 80, 81, 82 -> Icons.Rounded.Umbrella
        71, 73, 75, 77, 85, 86 -> Icons.Rounded.AcUnit
        95, 96, 99 -> Icons.Rounded.Thunderstorm
        else -> Icons.Rounded.Cloud
    }

    fun description(code: Int): Int = when (code) {
        0 -> R.string.wx_clear
        1 -> R.string.wx_mostly_clear
        2 -> R.string.wx_partly_cloudy
        3 -> R.string.wx_cloudy
        45, 48 -> R.string.wx_fog
        51, 53, 55 -> R.string.wx_drizzle
        56, 57 -> R.string.wx_freezing_drizzle
        61, 63 -> R.string.wx_rain
        65 -> R.string.wx_heavy_rain
        66, 67 -> R.string.wx_freezing_rain
        71, 73 -> R.string.wx_snow
        75 -> R.string.wx_heavy_snow
        77 -> R.string.wx_snow_grains
        80, 81 -> R.string.wx_showers
        82 -> R.string.wx_heavy_showers
        85, 86 -> R.string.wx_snow_showers
        95 -> R.string.wx_thunder
        96, 99 -> R.string.wx_thunder_hail
        else -> R.string.wx_unknown
    }

    private val fahrenheit get() = LocalePreferences.getTemperatureUnit() == LocalePreferences.TemperatureUnit.FAHRENHEIT

    /** A bare number for the degree sign: in a weather row there is no doubt which scale. */
    fun degrees(celsius: Double): Int = (if (fahrenheit) celsius * 9 / 5 + 32 else celsius).roundToInt()

    fun wind(context: android.content.Context, kmh: Double): String =
        if (Locale.getDefault().country in setOf("US", "LR", "MM", "GB")) context.getString(R.string.wind_mph, (kmh / 1.609).roundToInt())
        else context.getString(R.string.wind_kmh, kmh.roundToInt())
}

@Composable
internal fun FullPage(title: String, onClose: () -> Unit, action: (@Composable () -> Unit)? = null, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DawnTheme { CatTricksProvider {
            Column(Modifier.fillMaxSize().background(Dawn.colors.background).safeDrawingPadding()) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 4.dp)) {
                    IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.back), tint = Dawn.colors.textPrimary) }
                    Text(title, style = DawnType.headline, color = Dawn.colors.textPrimary, modifier = Modifier.weight(1f))
                    action?.invoke()
                }
                Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Spacing.s).padding(bottom = Spacing.l), verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
                    content()
                }
            }
        } }
    }
}

/**
 * The weather in full, from the reading already taken — never fetched again here,
 * and the "Updated" line keeps that honest.
 */
@Composable
fun WeatherDetail(weather: WeatherConditions, onClose: () -> Unit) {
    val context = LocalContext.current
    val colors = Dawn.colors
    FullPage(weather.placeName ?: stringResource(R.string.weather_title), onClose) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(weather.placeName ?: stringResource(R.string.your_location), style = DawnType.title, color = colors.textPrimary)
            Text(stringResource(R.string.weather_updated, TimeFormat.clock(context, weather.capturedAt)), style = DawnType.footnote, color = colors.textTertiary)
            Spacer(Modifier.height(Spacing.s))
            Icon(WeatherStyle.icon(weather.code, weather.isDay), null, tint = colors.accent, modifier = Modifier.size(64.dp))
            Text("${WeatherStyle.degrees(weather.temperature)}°", style = DawnType.display(72), color = colors.textPrimary)
            Text(stringResource(WeatherStyle.description(weather.code)), style = DawnType.headline, color = colors.textSecondary)
            Text(stringResource(R.string.high_low, WeatherStyle.degrees(weather.high), WeatherStyle.degrees(weather.low)), style = DawnType.callout, color = colors.textSecondary)
        }
        if (weather.hourly.isNotEmpty()) {
            LazyRow(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(colors.surfacePrimary).padding(vertical = Spacing.s),
                horizontalArrangement = Arrangement.spacedBy(Spacing.s),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = Spacing.s),
            ) {
                items(weather.hourly) { h ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        val hour = java.time.Instant.ofEpochSecond(h.epochSeconds).atZone(java.time.ZoneId.systemDefault())
                        Text(hour.format(java.time.format.DateTimeFormatter.ofPattern(if (TimeFormat.is24h(context)) "HH" else "h a", Locale.getDefault())),
                            style = DawnType.footnote, color = colors.textSecondary)
                        Icon(WeatherStyle.icon(h.code, h.isDay), null, tint = colors.accent, modifier = Modifier.size(22.dp))
                        Text("${WeatherStyle.degrees(h.temperature)}°", style = DawnType.callout.copy(fontWeight = FontWeight.Bold), color = colors.textPrimary)
                        Text(if (h.precipitationChance >= 0.1) "${(h.precipitationChance * 100).roundToInt()}%" else " ", style = DawnType.footnote, color = colors.accent)
                    }
                }
            }
        }
        // One row each, label and value apart: three cells side by side broke words
        // ("Yog'ingarc-hilik", "6 km/ soat") on a phone's width.
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(colors.surfacePrimary)) {
            val stats = listOfNotNull(
                weather.windSpeed?.let { Triple(Icons.Rounded.Air, stringResource(R.string.wind), WeatherStyle.wind(context, it)) },
                weather.humidity?.let { Triple(Icons.Rounded.WaterDrop, stringResource(R.string.humidity), "${(it * 100).roundToInt()}%") },
                Triple(Icons.Rounded.Umbrella, stringResource(R.string.precipitation), "${(weather.precipitationChance * 100).roundToInt()}%"),
            )
            stats.forEachIndexed { i, (icon, title, value) ->
                if (i > 0) Box(Modifier.padding(start = 48.dp).fillMaxWidth().height(0.5.dp).background(colors.separator))
                Stat(icon, title, value)
            }
        }
        // Open-Meteo's licence asks for a credit line wherever its data is shown.
        Text(stringResource(R.string.open_meteo_credit), style = DawnType.footnote, color = colors.textTertiary,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun Stat(icon: ImageVector, title: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.s, vertical = Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Dawn.colors.textSecondary, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.sm))
        Text(title, style = DawnType.body, color = Dawn.colors.textSecondary, modifier = Modifier.weight(1f))
        Text(value, style = DawnType.body.copy(fontWeight = FontWeight.Bold), color = Dawn.colors.textPrimary)
    }
}

/**
 * The streak page: the number on an ink card with the cat, the tricks long
 * streaks teach it, the covers it holds, and this month as paw prints. A share
 * button makes a card of it for anyone else.
 */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun StreakPage(record: StreakRecord, live: Int, alarms: List<Alarm>, since: LocalDate, onClose: () -> Unit) {
    val context = LocalContext.current
    val colors = Dawn.colors
    val today = LocalDate.now()
    val month = StreakDays.month(today, record, alarms, since)
    val week = StreakDays.week(today, record, alarms, since)
    val won = month.count { it.outcome == DayOutcome.WON }
    val scheduledToday = StreakRecord.scheduledBy(alarms, since)
    val scheduled = month.count { it.outcome in setOf(DayOutcome.WON, DayOutcome.MISSED, DayOutcome.COVERED) || (it.outcome == DayOutcome.TODAY && scheduledToday(it.date)) }
    val dressing = LocalCatDressing.current
    FullPage(stringResource(R.string.streak_title), onClose, action = if (live > 0) ({
        IconButton(onClick = { StreakShare.share(context, live, week, dressing) }) {
            Icon(Icons.Rounded.Share, stringResource(R.string.share_streak), tint = colors.textPrimary)
        }
    }) else null) {
        // The number, on ink. Pleased while it lasts, sad once it is lost, curious before the first.
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.xl)).background(DawnColors.Ink).padding(start = 20.dp, end = Spacing.s, top = Spacing.sm, bottom = Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                if (record.bestStreak == 0) {
                    Text(stringResource(R.string.streak_none), style = DawnType.title, color = DawnColors.Paper)
                    Text(stringResource(R.string.streak_empty), style = DawnType.footnote, color = DawnColors.NightTextSecondary)
                } else {
                    val words = context.resources.getQuantityString(R.plurals.days_in_a_row, live, live)
                    val (before, after) = words.split("$live", limit = 2).let { it[0].trim() to it.getOrElse(1) { "" }.trim() }
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        if (before.isNotEmpty()) Text(before, style = DawnType.callout.copy(fontWeight = FontWeight.SemiBold), color = DawnColors.NightTextSecondary, modifier = Modifier.padding(bottom = 10.dp))
                        Text("$live", style = DawnType.display(64), color = DawnColors.Yolk)
                        Text(after, style = DawnType.callout.copy(fontWeight = FontWeight.SemiBold), color = DawnColors.NightTextSecondary, modifier = Modifier.padding(bottom = 10.dp))
                    }
                    Text(stringResource(R.string.best_streak, record.bestStreak) + " · " + stringResource(R.string.mornings_this_month, won),
                        style = DawnType.footnote, color = DawnColors.NightTextSecondary)
                }
            }
            TappableCat(if (record.bestStreak == 0) CatMood.AWAKE else if (live > 0) CatMood.PROUD else CatMood.SAD, 104.dp, ground = CatGround.DARK)
        }

        // Tricks.
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(stringResource(if (uz.ata.dawnwick.ui.cat.currentCompanion() == uz.ata.dawnwick.companion.Pet.CAT) R.string.tricks_title else R.string.tricks_title_pet), style = DawnType.headline, color = colors.textPrimary)
            Text(stringResource(if (uz.ata.dawnwick.ui.cat.currentCompanion() == uz.ata.dawnwick.companion.Pet.CAT) R.string.tricks_detail else R.string.tricks_detail_pet), style = DawnType.footnote, color = colors.textSecondary)
            Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(colors.surfacePrimary).padding(Spacing.s)) {
                TricksPanel(record.bestStreak, live)
            }
        }

        // Covers.
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(stringResource(R.string.covers_title), style = DawnType.headline, color = colors.textPrimary)
            Text(stringResource(R.string.covers_detail), style = DawnType.footnote, color = colors.textSecondary)
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(colors.surfacePrimary).padding(Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                repeat(StreakRecord.MAX_COVERS) { i ->
                    val ready = i < record.covers
                    val flame = if (colors.isDark) DawnColors.Yolk else DawnColors.Ink
                    val empty = colors.textTertiary
                    Canvas(Modifier.padding(end = Spacing.xs).size(30.dp)) {
                        val path = Shapes.pawPrint(Rect(Offset.Zero, size))
                        if (ready) drawPath(path, flame) else drawPath(path, empty, style = Stroke(1.5.dp.toPx()))
                    }
                }
                Spacer(Modifier.width(Spacing.xs))
                Column {
                    Text(stringResource(if (record.covers > 0) (if (uz.ata.dawnwick.ui.cat.currentCompanion() == uz.ata.dawnwick.companion.Pet.CAT) R.string.covers_ready_title else R.string.covers_ready_title_pet) else R.string.covers_none), style = DawnType.headline, color = colors.textPrimary)
                    Text(stringResource(R.string.covers_ready, record.covers, StreakRecord.MAX_COVERS), style = DawnType.footnote, color = colors.textSecondary)
                    if (record.covers < StreakRecord.MAX_COVERS) {
                        val nextAt = (live / StreakRecord.COVER_EVERY + 1) * StreakRecord.COVER_EVERY
                        Text(stringResource(R.string.next_cover_at, nextAt), style = DawnType.footnote, color = colors.textSecondary)
                    }
                }
            }
        }

        // This month.
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(today.month.getDisplayName(TextStyle.FULL_STANDALONE, Locale.getDefault()).replaceFirstChar { it.uppercase() },
                    style = DawnType.headline, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Text(stringResource(R.string.won_of_scheduled, won, scheduled), style = DawnType.footnote, color = colors.textSecondary)
            }
            MonthGrid(month)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.s), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                listOf(DayOutcome.WON to R.string.legend_won, DayOutcome.COVERED to R.string.legend_covered, DayOutcome.MISSED to R.string.legend_missed, DayOutcome.REST to R.string.legend_rest).forEach { (o, label) ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        DayGlyph(o, Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(stringResource(label), style = DawnType.footnote, color = colors.textSecondary)
                    }
                }
            }
            Text(stringResource(R.string.rest_days_note), style = DawnType.footnote, color = colors.textTertiary)
        }
    }
}

/**
 * The six tricks as a row of badges — learned ones in yolk, the next one ringed, the
 * rest grey — and under them the one chosen: the next to learn, until another is tapped.
 */
@Composable
private fun TricksPanel(best: Int, current: Int) {
    val haptics = rememberHaptics()
    val next = CatTrick.next(best)
    var chosen by remember { mutableStateOf<CatTrick?>(null) }
    val shown = chosen ?: next ?: CatTrick.MEDAL
    val colors = Dawn.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
        Row(Modifier.fillMaxWidth()) {
            CatTrick.entries.forEach { trick ->
                val learned = best >= trick.days
                val isNext = trick == next
                val trickLabel = stringResource(trickName(trick))
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Box(
                        Modifier.size(50.dp).clip(CircleShape)
                            .border(2.dp, if (trick == shown) colors.textPrimary else Color.Transparent, CircleShape)
                            .clickable { haptics.perform(Haptic.SELECTION); chosen = trick }
                            .semantics { contentDescription = trickLabel; selected = trick == shown }
                            .padding(3.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        val accent = colors.accent
                        val grey = colors.surfaceSecondary
                        Canvas(Modifier.fillMaxSize()) {
                            when {
                                learned -> drawCircle(DawnColors.Yolk)
                                isNext -> drawCircle(accent, radius = size.minDimension / 2 - 1.dp.toPx(),
                                    style = Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))))
                                else -> drawCircle(grey)
                            }
                        }
                        Text("${trick.days}", style = DawnType.display(if (trick.days >= 100) 13 else 16),
                            color = if (learned) DawnColors.Ink else if (isNext) colors.textPrimary else colors.textTertiary)
                    }
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(trickName(shown)), style = DawnType.headline, color = colors.textPrimary, modifier = Modifier.weight(1f))
                if (best >= shown.days) {
                    Icon(Icons.Rounded.Check, null, tint = colors.accent, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(stringResource(R.string.learned), style = DawnType.footnote.copy(fontWeight = FontWeight.Bold), color = colors.accent)
                }
            }
            Text(stringResource(trickDetail(shown, uz.ata.dawnwick.ui.cat.currentCompanion())), style = DawnType.footnote, color = colors.textSecondary)
            if (best < shown.days) {
                Box(Modifier.padding(top = 4.dp).fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)).background(colors.textPrimary.copy(alpha = 0.1f))) {
                    Box(Modifier.fillMaxWidth((current / shown.days.toFloat()).coerceIn(0f, 1f)).height(8.dp).background(colors.accent))
                }
                Text(stringResource(R.string.trick_progress, current, shown.days), style = DawnType.footnote.copy(fontWeight = FontWeight.SemiBold), color = colors.textSecondary)
            }
        }
    }
}

@Composable
private fun MonthGrid(days: List<DayCell>) {
    val first = WeekFields.of(Locale.getDefault()).firstDayOfWeek
    val lead = ((days.first().date.dayOfWeek.value - first.value) + 7) % 7
    val cells: List<DayCell?> = List(lead) { null } + days
    val names = (0 until 7).map { first.plus(it.toLong()).getDisplayName(TextStyle.NARROW_STANDALONE, Locale.getDefault()) }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary).padding(Spacing.s), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row { names.forEach { Text(it, style = DawnType.footnote.copy(fontWeight = FontWeight.Bold), color = Dawn.colors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.weight(1f)) } }
        cells.chunked(7).forEach { week ->
            Row {
                (0 until 7).forEach { i ->
                    val cell = week.getOrNull(i)
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        if (cell != null) {
                            DayGlyph(cell.outcome, Modifier.size(24.dp))
                            Text("${cell.date.dayOfMonth}", style = DawnType.footnote, color = Dawn.colors.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

/** Seven days, each a glyph under its weekday. */
@Composable
fun WeekStrip(days: List<DayCell>) {
    Row(Modifier.fillMaxWidth()) {
        days.forEach { day ->
            val isToday = day.date == LocalDate.now()
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(day.date.dayOfWeek.getDisplayName(TextStyle.SHORT_STANDALONE, Locale.getDefault()).take(3),
                    style = DawnType.footnote.copy(fontWeight = if (isToday) FontWeight.Black else FontWeight.SemiBold),
                    color = if (isToday) Dawn.colors.accent else Dawn.colors.textSecondary, maxLines = 1)
                DayGlyph(day.outcome, Modifier.size(26.dp))
            }
        }
    }
}

/**
 * Each state its own shape, so it reads without colour: a paw for a morning won,
 * a cross for one missed, the paw in outline for one the cat covered, a dot for
 * rest, a dashed ring for today.
 */
@Composable
fun DayGlyph(outcome: DayOutcome, modifier: Modifier = Modifier) {
    val accent = Dawn.colors.accent
    val flame = if (Dawn.colors.isDark) DawnColors.Yolk else DawnColors.Ink
    val missed = Dawn.colors.destructive
    val quiet = Dawn.colors.textTertiary
    Canvas(modifier.aspectRatio(1f)) {
        val d = size.minDimension
        val c = center
        fun box(f: Float) = Rect(Offset(c.x - d * f / 2, c.y - d * f / 2), androidx.compose.ui.geometry.Size(d * f, d * f))
        when (outcome) {
            DayOutcome.WON -> drawPath(Shapes.pawPrint(box(0.9f)), flame)
            DayOutcome.COVERED -> drawPath(Shapes.pawPrint(box(0.84f)), flame, style = Stroke(maxOf(1.2f, d * 0.06f)))
            DayOutcome.MISSED -> {
                val r = d * 0.18f
                drawLine(missed, Offset(c.x - r, c.y - r), Offset(c.x + r, c.y + r), d * 0.09f)
                drawLine(missed, Offset(c.x - r, c.y + r), Offset(c.x + r, c.y - r), d * 0.09f)
            }
            DayOutcome.REST -> drawCircle(quiet, d * 0.12f)
            DayOutcome.TODAY -> drawCircle(accent, d * 0.39f, style = Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.2f * density, 3.2f * density))))
            DayOutcome.UPCOMING -> drawCircle(quiet.copy(alpha = 0.5f), d * 0.09f)
        }
    }
}
