package uz.ata.dawnwick.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import java.text.DateFormatSymbols
import java.util.Locale
import kotlin.math.abs
import kotlinx.coroutines.flow.distinctUntilChanged
import uz.ata.dawnwick.R
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.theme.DawnType

private val RowHeight = 64.dp

/**
 * The alarm time as drums of large numerals — hour and minute, and AM/PM on a
 * 12-hour clock. Each snaps to a row, ticks under the finger, and is one adjustable
 * element for TalkBack.
 */
@Composable
fun TimeDrum(hour: Int, minute: Int, color: Color, onChange: (hour: Int, minute: Int) -> Unit) {
    val context = LocalContext.current
    val twelve = !TimeFormat.is24h(context)
    Box(Modifier.fillMaxWidth().height(RowHeight * 3), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxWidth().height(RowHeight).background(color.copy(alpha = 0.1f), RoundedCornerShape(18.dp)))
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (twelve) {
                Drum((1..12).toList(), if (hour % 12 == 0) 12 else hour % 12, color, context.getString(R.string.hour), 104.dp, { "$it" }) {
                    onChange((it % 12) + if (hour >= 12) 12 else 0, minute)
                }
            } else {
                Drum((0..23).toList(), hour, color, context.getString(R.string.hour), 104.dp, { "%02d".format(it) }) { onChange(it, minute) }
            }
            Text(":", style = DawnType.display(46, FontWeight.Bold), color = color, modifier = Modifier.offset(y = (-4).dp))
            Drum((0..59).toList(), minute, color, context.getString(R.string.minute), 104.dp, { "%02d".format(it) }) { onChange(hour, it) }
            if (twelve) {
                val symbols = DateFormatSymbols.getInstance(Locale.getDefault()).amPmStrings
                Drum(listOf(0, 1), if (hour >= 12) 1 else 0, color, context.getString(R.string.am_pm), 70.dp, { symbols[it] }, fontSize = 22, wraps = false) {
                    onChange(hour % 12 + it * 12, minute)
                }
            }
        }
    }
}

@Composable
private fun Drum(
    values: List<Int>,
    selected: Int,
    color: Color,
    label: String,
    width: Dp,
    text: (Int) -> String,
    fontSize: Int = 46,
    wraps: Boolean = true,
    onSelect: (Int) -> Unit,
) {
    // A long strip of the values over and over, started in the middle, so the drum
    // turns as far as anyone likes in either direction.
    val repeats = if (wraps) 200 else 1
    val count = values.size * repeats
    val base = if (wraps) values.size * (repeats / 2) else 0
    val start = base + values.indexOf(selected).coerceAtLeast(0)
    val state = rememberLazyListState(initialFirstVisibleItemIndex = start)
    val haptic = rememberHaptics()
    val fling = rememberSnapFlingBehavior(state)
    // The collector below outlives compositions; it must call the latest handler,
    // which knows the other drum's current value — not the one from the first frame.
    val select by rememberUpdatedState(onSelect)
    val half = with(androidx.compose.ui.platform.LocalDensity.current) { RowHeight.toPx() / 2 }
    fun centre() = state.firstVisibleItemIndex + if (state.firstVisibleItemScrollOffset > half) 1 else 0

    // Outside changes (12h switch) move the drum.
    LaunchedEffect(selected) {
        val current = values[state.firstVisibleItemIndex % values.size]
        if (current != selected && !state.isScrollInProgress) {
            state.scrollToItem(state.firstVisibleItemIndex - values.indexOf(current) + values.indexOf(selected))
        }
    }
    LaunchedEffect(state) {
        snapshotFlow { centre() }
            .distinctUntilChanged()
            .collect { i ->
                val value = values[i.coerceIn(0, count - 1) % values.size]
                haptic.perform(Haptic.SELECTION)
                select(value)
            }
    }
    val idx = values.indexOf(selected)
    LazyColumn(
        state = state,
        flingBehavior = fling,
        modifier = Modifier.width(width).height(RowHeight * 3).semantics(mergeDescendants = true) {
            contentDescription = label
            stateDescription = text(selected)
            progressBarRangeInfo = ProgressBarRangeInfo(idx.toFloat(), 0f..(values.size - 1).toFloat(), values.size - 2)
            setProgress { target ->
                val i = target.toInt().coerceIn(0, values.size - 1)
                onSelect(values[i]); true
            }
        },
        // The first and last rows sit in the middle of the drum.
        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = RowHeight),
    ) {
        items(count) { i ->
            val value = values[i % values.size]
            val distance = abs(i - centre())
            Box(Modifier.width(width).height(RowHeight).graphicsLayer { alpha = if (distance == 0) 1f else 0.35f }, contentAlignment = Alignment.Center) {
                Text(text(value), style = DawnType.display(fontSize, FontWeight.Bold).copy(fontFeatureSettings = "tnum"), color = color)
            }
        }
    }
}
