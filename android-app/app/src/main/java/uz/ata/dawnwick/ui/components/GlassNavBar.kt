package uz.ata.dawnwick.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType

/** How much room the floating bar takes at the bottom: a screen leaves this much space after its last row. */
val LocalNavBarSpace = compositionLocalOf { 0.dp }

/** The bar's own height, without the system's gesture area below it. */
val GlassNavBarHeight = 64.dp
private val BarMargin = 12.dp

/** The space a screen keeps clear below its content so the last row can scroll up out from under the bar. */
@Composable
fun glassNavBarSpace(): Dp {
    val bottom = WindowInsets.navigationBars.let { with(androidx.compose.ui.platform.LocalDensity.current) { it.getBottom(this).toDp() } }
    return GlassNavBarHeight + BarMargin * 2 + bottom
}

data class GlassTab(val title: String, val icon: ImageVector)

/**
 * The tab bar as a pane of frosted glass floating over the screen: what scrolls
 * beneath shows through, blurred. One yolk pill sits behind the chosen tab and
 * slides to the next — a single shape moving, so there is never a second one
 * fading out behind it, and it casts no shadow to leave behind.
 */
@Composable
fun GlassNavBar(tabs: List<GlassTab>, selected: Int, haze: HazeState, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val colors = Dawn.colors
    val shape = RoundedCornerShape(GlassNavBarHeight / 2)
    val glass = HazeStyle(
        backgroundColor = colors.background,
        tint = HazeTint(colors.surfacePrimary.copy(alpha = if (colors.isDark) 0.62f else 0.68f)),
        blurRadius = 26.dp,
        noiseFactor = 0.04f,
        // Without the blur (before Android 12), a nearly solid pane, so the words beneath don't show through.
        fallbackTint = HazeTint(colors.surfacePrimary.copy(alpha = 0.96f)),
    )
    // A thin bright rim along the top edge, as light catches the edge of glass.
    val rim = Brush.verticalGradient(
        listOf(Color.White.copy(alpha = if (colors.isDark) 0.22f else 0.9f), Color.White.copy(alpha = if (colors.isDark) 0.04f else 0.25f)),
    )
    Box(
        modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(horizontal = BarMargin + 4.dp, vertical = BarMargin),
    ) {
        BoxWithConstraints(
            Modifier
                .fillMaxWidth()
                .height(GlassNavBarHeight)
                // The bar's shadow is the bar's: it never moves, so nothing trails after a tap.
                .shadow(18.dp, shape, ambientColor = Color.Black.copy(alpha = 0.18f), spotColor = Color.Black.copy(alpha = 0.22f))
                .clip(shape)
                // Blurred only where Android blurs on the GPU (12 and later); before that Haze falls
                // back to RenderScript, which can fail, so the pane is frosted with a plain tint instead.
                .hazeEffect(haze, glass) { blurEnabled = android.os.Build.VERSION.SDK_INT >= 31 }
                .border(1.dp, rim, shape),
        ) {
            val itemWidth = maxWidth / tabs.size
            val pillInset = 6.dp
            val x by animateDpAsState(
                itemWidth * selected,
                spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMediumLow),
                label = "tab pill",
            )
            Box(
                Modifier
                    .offset(x = x + pillInset)
                    .padding(vertical = pillInset)
                    .width(itemWidth - pillInset * 2)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(GlassNavBarHeight / 2 - pillInset))
                    .background(Brush.verticalGradient(listOf(DawnColors.Yolk, DawnColors.Yolk.copy(alpha = 0.88f)))),
            )
            Row(Modifier.fillMaxSize()) {
                tabs.forEachIndexed { i, tab ->
                    val on = i == selected
                    val tint by animateColorAsState(if (on) DawnColors.Ink else colors.textSecondary, label = "tab tint")
                    Column(
                        Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(GlassNavBarHeight / 2))
                            .pressable { onSelect(i) }
                            .semantics { role = Role.Tab; this.selected = on },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(tab.icon, null, tint = tint, modifier = Modifier.size(24.dp))
                        Text(
                            tab.title, style = DawnType.footnote.copy(fontSize = 11.sp), color = tint,
                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 2.dp, start = 2.dp, end = 2.dp),
                        )
                    }
                }
            }
        }
    }
}
