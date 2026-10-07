package uz.ata.dawnwick.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Yolk, ink and paper. Yolk is the morning — the ring screen, the primary button,
 * the one thing to look at. Ink is the night and the type. Paper carries the rest.
 * Solid colours, no glow.
 */
@Immutable
data class DawnColors(
    val background: Color,
    val surfacePrimary: Color,
    val surfaceSecondary: Color,
    val tile: Color,
    val onTile: Color,
    val separator: Color,
    val heroBand: Color,
    val onHero: Color,
    val onHeroSecondary: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    /** The accent as type and control tint: ink by day, yolk by night. */
    val accent: Color,
    val success: Color,
    val destructive: Color,
    val warning: Color,
    val isDark: Boolean,
) {
    val yolk get() = Yolk
    val ink get() = Ink

    companion object {
        val Yolk = Color(0xFFFFC629)
        val Ink = Color(0xFF1B1A17)
        val OnYolkSecondary = Color(0xFF5F4E1C)
        val NightTextSecondary = Color(0xFFA8A39A)
        val Paper = Color(0xFFF4F2ED)

        val Light = DawnColors(
            background = Paper,
            surfacePrimary = Color.White,
            surfaceSecondary = Color(0xFFECE9E2),
            tile = Color(0xFF1E1C19),
            onTile = Paper,
            separator = Color(0xFFE3DFD6),
            heroBand = Yolk,
            onHero = Ink,
            onHeroSecondary = OnYolkSecondary,
            textPrimary = Ink,
            textSecondary = Color(0xFF6B665E),
            textTertiary = Color(0xFFA29D94),
            accent = Ink,
            success = Color(0xFF2F8F5B),
            destructive = Color(0xFFC8362B),
            warning = Color(0xFF9A6A00),
            isDark = false,
        )

        val Dark = DawnColors(
            background = Color(0xFF131210),
            surfacePrimary = Color(0xFF1E1D1A),
            surfaceSecondary = Color(0xFF2A2825),
            tile = Color(0xFF262421),
            onTile = Paper,
            separator = Color(0xFF2E2C28),
            heroBand = Color(0xFF22201D),
            onHero = Paper,
            onHeroSecondary = NightTextSecondary,
            textPrimary = Paper,
            textSecondary = NightTextSecondary,
            textTertiary = Color(0xFF6E6A63),
            accent = Yolk,
            success = Color(0xFF5FC28A),
            destructive = Color(0xFFFF6B5E),
            warning = Yolk,
            isDark = true,
        )
    }
}

object Spacing {
    val xxs = 4.dp
    val xs = 8.dp
    val sm = 12.dp
    val s = 16.dp
    val m = 24.dp
    val l = 32.dp
    val xl = 48.dp
}

object Radius {
    val s = 10.dp
    val m = 14.dp
    val l = 14.dp
    val xl = 28.dp
}

/** Heavy, tight type for the voice — times, numbers, titles. */
object DawnType {
    fun display(size: Int, weight: FontWeight = FontWeight.Black) =
        TextStyle(fontSize = size.sp, fontWeight = weight, letterSpacing = if (size > 40) (-1).sp else (-0.3).sp, lineHeight = (size * 1.08).sp)

    val eyebrow = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Black, letterSpacing = 1.1.sp)
    val title = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.3).sp)
    val section = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp)
    val headline = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold)
    val body = TextStyle(fontSize = 17.sp)
    val callout = TextStyle(fontSize = 15.sp, lineHeight = 20.sp)
    val footnote = TextStyle(fontSize = 13.sp, lineHeight = 17.sp)
    val button = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold)
}

val LocalDawnColors = staticCompositionLocalOf { DawnColors.Light }

object Dawn {
    val colors: DawnColors @Composable get() = LocalDawnColors.current
}

/** The appearance chosen at the root, so a dialog's own theme follows it too. */
private val LocalChosenDark = staticCompositionLocalOf<Boolean?> { null }

@Composable
fun DawnTheme(dark: Boolean = LocalChosenDark.current ?: isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (dark) DawnColors.Dark else DawnColors.Light
    val scheme = if (dark) {
        darkColorScheme(
            primary = DawnColors.Yolk, onPrimary = DawnColors.Ink,
            background = colors.background, surface = colors.background,
            surfaceContainer = colors.surfacePrimary, surfaceContainerHigh = colors.surfacePrimary,
            onSurface = colors.textPrimary, onSurfaceVariant = colors.textSecondary,
            secondaryContainer = colors.surfaceSecondary, outline = colors.textTertiary,
        )
    } else {
        lightColorScheme(
            primary = DawnColors.Ink, onPrimary = DawnColors.Yolk,
            background = colors.background, surface = colors.background,
            surfaceContainer = colors.surfacePrimary, surfaceContainerHigh = colors.surfacePrimary,
            onSurface = colors.textPrimary, onSurfaceVariant = colors.textSecondary,
            secondaryContainer = DawnColors.Yolk, outline = colors.textTertiary,
        )
    }
    CompositionLocalProvider(LocalDawnColors provides colors, LocalChosenDark provides dark) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** The daylight appearance whatever the system says: the ring screen and missions. */
@Composable
fun DaylightTheme(content: @Composable () -> Unit) = DawnTheme(dark = false, content = content)
