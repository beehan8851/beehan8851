package uz.ata.dawnwick.ui.missions

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uz.ata.dawnwick.R
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.MissionKind
import uz.ata.dawnwick.alarm.model.StrokePoint
import uz.ata.dawnwick.missions.DrawSimilarity
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.components.SoftButton
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnTheme
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

private val CanvasHeight = 280.dp

/**
 * A surface to draw on with a finger. Strokes are kept in dp, so a shape drawn on
 * one screen is the same size when shown as a hint on another.
 */
@Composable
fun DrawingCanvas(
    strokes: SnapshotStateList<List<StrokePoint>>,
    modifier: Modifier = Modifier,
    border: Color = Dawn.colors.surfaceSecondary,
    hint: List<List<StrokePoint>>? = null,
    onStroke: () -> Unit = {},
) {
    val density = LocalDensity.current.density
    val ink = Dawn.colors.textPrimary
    val hintColor = Dawn.colors.textPrimary.copy(alpha = 0.3f)
    var current by remember { mutableStateOf<List<StrokePoint>>(emptyList()) }
    Canvas(
        modifier.fillMaxWidth().height(CanvasHeight)
            .clip(RoundedCornerShape(Radius.m))
            .background(Dawn.colors.surfacePrimary)
            .border(2.dp, border, RoundedCornerShape(Radius.m))
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    fun point(o: Offset) = StrokePoint((o.x / density).toDouble(), (o.y / density).toDouble())
                    current = listOf(point(down.position))
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        current = current + point(change.position)
                        change.consume()
                    }
                    if (current.size > 1) {
                        strokes.add(current)
                        onStroke()
                    }
                    current = emptyList()
                }
            },
    ) {
        fun path(list: List<List<StrokePoint>>) = Path().apply {
            for (s in list) {
                val first = s.firstOrNull() ?: continue
                moveTo(first.x.toFloat() * density, first.y.toFloat() * density)
                s.drop(1).forEach { lineTo(it.x.toFloat() * density, it.y.toFloat() * density) }
            }
        }
        if (hint != null) drawPath(path(hint), hintColor, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawPath(path(strokes + listOf(current)), ink, style = Stroke(3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/**
 * Draw the shape saved the night before. A shape can take several strokes, so
 * nothing is judged until Done. A miss shows the saved shape faintly for a moment,
 * then clears the canvas for another go.
 */
@Composable
fun DrawMission(config: MissionConfig.Draw, onSuccess: () -> Unit) {
    val reference = config.referenceStrokes
    val strokes = remember { mutableStateListOf<List<StrokePoint>>() }
    var state by remember { mutableStateOf(if (reference == null) "notConfigured" else "idle") }
    var showHint by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptic = rememberHaptics()
    val colors = Dawn.colors

    fun evaluate() {
        if (done || reference == null || strokes.isEmpty()) return
        state = "checking"
        scope.launch {
            delay(300)
            if (DrawSimilarity.score(reference, strokes.toList()) >= DrawSimilarity.THRESHOLD) {
                done = true
                haptic.perform(Haptic.SUCCESS)
                onSuccess()
            } else {
                haptic.perform(Haptic.ERROR)
                state = "wrong"
                showHint = true
                delay(1800)
                showHint = false
                delay(300)
                strokes.clear()
                state = "idle"
            }
        }
    }

    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        MissionHeader(MissionKind.DRAW)
        Spacer(Modifier.weight(1f))
        Text(stringResource(R.string.draw_instruction), style = DawnType.callout, color = colors.textSecondary)
        Spacer(Modifier.height(Spacing.s))
        DrawingCanvas(
            strokes = strokes,
            modifier = Modifier.padding(horizontal = Spacing.l),
            border = when (state) {
                "wrong" -> colors.destructive
                "checking" -> colors.accent.copy(alpha = 0.5f)
                "notConfigured" -> colors.warning.copy(alpha = 0.6f)
                else -> colors.surfaceSecondary
            },
            hint = if (showHint) reference else null,
            onStroke = { if (state == "wrong") state = "idle" },
        )
        Spacer(Modifier.height(Spacing.s))
        Text(
            when (state) {
                "checking" -> stringResource(R.string.draw_checking)
                "wrong" -> stringResource(R.string.draw_wrong)
                "notConfigured" -> stringResource(R.string.draw_not_calibrated)
                else -> " "
            },
            style = DawnType.footnote,
            color = when (state) { "wrong" -> colors.destructive; "notConfigured" -> colors.warning; else -> colors.textSecondary },
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = Spacing.l),
        )
        Spacer(Modifier.weight(1f))
        Column(Modifier.padding(horizontal = Spacing.l).padding(bottom = Spacing.m), horizontalAlignment = Alignment.CenterHorizontally) {
            InkButton(onClick = ::evaluate, enabled = strokes.isNotEmpty() && state != "checking") { ButtonLabel(stringResource(R.string.done)) }
            TextButton(onClick = { strokes.clear(); if (state == "wrong") state = "idle" }, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(R.string.clear), style = DawnType.callout, color = colors.textSecondary)
            }
        }
    }
}

/**
 * Setting up Draw in the editor: the shape twice, so the second — drawn the way it
 * will be in the morning, from memory — is what is kept.
 */
@Composable
fun DrawSetupDialog(onSave: (List<List<StrokePoint>>) -> Unit, onCancel: () -> Unit) {
    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DawnTheme {
            val strokes = remember { mutableStateListOf<List<StrokePoint>>() }
            var phase by remember { mutableStateOf(0) }
            val haptic = rememberHaptics()
            val colors = Dawn.colors
            Column(Modifier.fillMaxSize().background(colors.background).safeDrawingPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.textSecondary) }
                    Text(stringResource(R.string.draw_setup_title), style = DawnType.headline, color = colors.textPrimary,
                        textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                    Spacer(Modifier.size(72.dp, 1.dp))
                }
                Spacer(Modifier.height(Spacing.m))
                Text(
                    stringResource(when (phase) { 0 -> R.string.draw_setup_first; 1 -> R.string.draw_setup_second; else -> R.string.draw_setup_done }),
                    style = DawnType.callout,
                    color = if (phase == 2) colors.success else colors.textSecondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = Spacing.l),
                )
                Spacer(Modifier.height(Spacing.m))
                Box(Modifier.padding(horizontal = Spacing.l)) {
                    DrawingCanvas(strokes, hint = null)
                    if (phase == 2) {
                        Icon(Icons.Rounded.CheckCircle, null, tint = colors.success, modifier = Modifier.align(Alignment.TopEnd).padding(Spacing.xs).size(28.dp))
                    }
                }
                Spacer(Modifier.height(Spacing.m))
                Row(Modifier.padding(horizontal = Spacing.l), horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    SoftButton(onClick = { strokes.clear(); if (phase == 2) phase = 1 }, modifier = Modifier.weight(1f)) {
                        ButtonLabel(stringResource(R.string.clear))
                    }
                    InkButton(
                        onClick = {
                            when (phase) {
                                0 -> { strokes.clear(); phase = 1 }
                                1 -> { phase = 2; haptic.perform(Haptic.SUCCESS) }
                                else -> onSave(strokes.toList())
                            }
                        },
                        enabled = strokes.isNotEmpty(),
                        modifier = Modifier.weight(1f),
                    ) { ButtonLabel(stringResource(if (phase == 2) R.string.save else R.string.next)) }
                }
            }
        }
    }
}
