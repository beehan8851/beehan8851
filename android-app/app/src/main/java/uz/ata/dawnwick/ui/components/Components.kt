package uz.ata.dawnwick.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.composed
import androidx.compose.ui.focus.onFocusEvent
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/** Shrinks a little and dims under the finger, as every button in the app does. */
@Composable
fun Modifier.pressable(enabled: Boolean = true, role: Role = Role.Button, onClick: () -> Unit): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.96f else 1f, label = "press")
    return this
        .scale(scale)
        .alpha(if (enabled) 1f else 0.4f)
        .clickable(source, indication = null, enabled = enabled, role = role, onClick = onClick)
}

@Composable
private fun ButtonFace(background: Color, content: Color, modifier: Modifier, enabled: Boolean, onClick: () -> Unit, label: @Composable RowScope.() -> Unit) {
    Row(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 54.dp)
            .pressable(enabled, onClick = onClick)
            .clip(RoundedCornerShape(Radius.l))
            .background(background)
            .padding(horizontal = Spacing.s, vertical = Spacing.sm),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(LocalContentColor provides content, LocalTextStyle provides DawnType.button.copy(color = content, textAlign = TextAlign.Center)) {
            label()
        }
    }
}

/** The main button: ink with yolk type. */
@Composable
fun InkButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, label: @Composable RowScope.() -> Unit) =
    ButtonFace(DawnColors.Ink, DawnColors.Yolk, modifier, enabled, onClick, label)

/** Yolk with ink type: the one thing to press on a paper page. */
@Composable
fun YolkButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, label: @Composable RowScope.() -> Unit) =
    ButtonFace(DawnColors.Yolk, DawnColors.Ink, modifier, enabled, onClick, label)

/** The quieter one: ink on a faint wash. */
@Composable
fun SoftButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, label: @Composable RowScope.() -> Unit) =
    ButtonFace(Dawn.colors.surfaceSecondary, Dawn.colors.textPrimary, modifier, enabled, onClick, label)

@Composable
fun ButtonLabel(text: String, icon: ImageVector? = null) {
    if (icon != null) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
    }
    Text(text)
}

/** A round ink button with a yolk glyph: close, undo. */
@Composable
fun CircleIconButton(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Box(
        modifier
            .size(44.dp)
            .semantics { contentDescription = label }
            .pressable(enabled, onClick = onClick)
            .clip(CircleShape)
            .background(DawnColors.Ink),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = DawnColors.Yolk, modifier = Modifier.size(20.dp))
    }
}

/** A section of a settings-like page: a small heading over a rounded card. */
@Composable
fun Section(title: String?, modifier: Modifier = Modifier, footer: String? = null, content: @Composable () -> Unit) {
    Column(modifier.fillMaxWidth().padding(horizontal = Spacing.s)) {
        if (title != null) {
            Text(title.uppercase(), style = DawnType.section, color = Dawn.colors.textSecondary,
                modifier = Modifier.padding(start = Spacing.s, bottom = Spacing.xs, top = Spacing.s))
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary)) { content() }
        if (footer != null) {
            Text(footer, style = DawnType.footnote, color = Dawn.colors.textSecondary,
                modifier = Modifier.padding(start = Spacing.s, end = Spacing.s, top = Spacing.xs))
        }
    }
}

/** A row in a section: a title and something on the right. */
@Composable
fun SectionRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    onClick: (() -> Unit)? = null,
    titleStyle: TextStyle = DawnType.body,
    titleColor: Color = Dawn.colors.textPrimary,
    trailing: @Composable (() -> Unit)? = null,
) {
    Row(
        modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .defaultMinSize(minHeight = 52.dp)
            .padding(horizontal = Spacing.s, vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = titleStyle, color = titleColor)
            if (subtitle != null) Text(subtitle, style = DawnType.footnote, color = Dawn.colors.textSecondary)
        }
        if (trailing != null) {
            Spacer(Modifier.width(Spacing.s))
            trailing()
        }
    }
}

@Composable
fun RowDivider() = Box(Modifier.fillMaxWidth().padding(start = Spacing.s).height(0.5.dp).background(Dawn.colors.separator))

/** A small fact in a capsule. */
@Composable
fun FactChip(text: String, modifier: Modifier = Modifier) {
    Box(
        modifier.clip(RoundedCornerShape(18.dp)).background(DawnColors.Ink.copy(alpha = 0.08f))
            .defaultMinSize(minHeight = 36.dp).padding(horizontal = Spacing.s),
        contentAlignment = Alignment.Center,
    ) { Text(text, style = DawnType.callout.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = Dawn.colors.textPrimary) }
}

/**
 * Keeps a text field in sight above the keyboard: when it is focused, and again as
 * the keyboard slides up, it asks its scrolling parent to bring it into view.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
fun Modifier.keepAboveKeyboard(): Modifier = composed {
    val requester = remember { androidx.compose.foundation.relocation.BringIntoViewRequester() }
    var focused by remember { androidx.compose.runtime.mutableStateOf(false) }
    val imeBottom = androidx.compose.foundation.layout.WindowInsets.ime.getBottom(androidx.compose.ui.platform.LocalDensity.current)
    androidx.compose.runtime.LaunchedEffect(focused, imeBottom) {
        if (focused) requester.bringIntoView()
    }
    this.bringIntoViewRequester(requester).onFocusEvent { focused = it.isFocused }
}
