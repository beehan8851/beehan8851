package uz.ata.dawnwick.ui.settings

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import uz.ata.dawnwick.R
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.premium.PremiumFeature
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Spacing

/**
 * The cat's five launcher icons, as on iOS. Android has no API to swap an app's icon,
 * so each is an `activity-alias` in the manifest and exactly one of them is enabled.
 * Classic is free; the others are Premium.
 */
enum class AppIcon(val alias: String, val title: Int, val preview: Int) {
    CLASSIC("IconClassic", R.string.app_icon_classic, R.drawable.icon_preview_classic),
    NIGHT("IconNight", R.string.app_icon_night, R.drawable.icon_preview_night),
    PROUD("IconProud", R.string.app_icon_proud, R.drawable.icon_preview_proud),
    STARTLED("IconStartled", R.string.app_icon_startled, R.drawable.icon_preview_startled),
    UNIMPRESSED("IconUnimpressed", R.string.app_icon_unimpressed, R.drawable.icon_preview_unimpressed);

    val isPremium get() = this != CLASSIC

    private fun component(context: Context) = ComponentName(context.packageName, "${context.packageName}.$alias")

    companion object {
        fun current(context: Context): AppIcon {
            val pm = context.packageManager
            return entries.firstOrNull { icon ->
                when (pm.getComponentEnabledSetting(icon.component(context))) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                    // Never changed: the manifest's own setting, where only Classic is on.
                    PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> icon == CLASSIC
                    else -> false
                }
            } ?: CLASSIC
        }

        /** Turns `icon` on before the old one off, so there is never a moment with no launcher entry. */
        fun set(context: Context, icon: AppIcon): Boolean = runCatching {
            val pm = context.packageManager
            pm.setComponentEnabledSetting(icon.component(context), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            entries.filter { it != icon }.forEach {
                pm.setComponentEnabledSetting(it.component(context), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            }
        }.isSuccess
    }
}

@Composable
fun AppIconPicker(onClose: () -> Unit) {
    val context = LocalContext.current
    val premium = context.graph.isPremium
    var current by remember { mutableStateOf(AppIcon.current(context)) }
    AlertDialog(
        onDismissRequest = onClose,
        confirmButton = { TextButton(onClick = onClose) { Text(stringResource(R.string.done), color = Dawn.colors.accent) } },
        title = { Text(stringResource(R.string.app_icon), style = DawnType.headline) },
        containerColor = Dawn.colors.surfacePrimary,
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(stringResource(R.string.app_icon_footer), style = DawnType.footnote, color = Dawn.colors.textSecondary)
                AppIcon.entries.chunked(3).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        row.forEach { icon ->
                            val locked = icon.isPremium && !premium
                            Column(
                                Modifier.weight(1f).pressable {
                                    when {
                                        locked -> { onClose(); context.graph.showPaywall(PremiumFeature.GENERAL) }
                                        icon == current -> Unit
                                        AppIcon.set(context, icon) -> {
                                            current = icon
                                            Toast.makeText(context, R.string.app_icon_note, Toast.LENGTH_SHORT).show()
                                        }
                                        else -> Toast.makeText(context, R.string.app_icon_failed, Toast.LENGTH_LONG).show()
                                    }
                                },
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                val shape = RoundedCornerShape(16.dp)
                                Box(contentAlignment = Alignment.Center) {
                                    Image(painterResource(icon.preview), null,
                                        Modifier.size(64.dp).clip(shape)
                                            .border(3.dp, if (icon == current) DawnColors.Yolk else Dawn.colors.separator, shape))
                                    if (locked) Icon(Icons.Rounded.Lock, null, tint = DawnColors.Ink,
                                        modifier = Modifier.size(26.dp).clip(RoundedCornerShape(13.dp)).background(DawnColors.Yolk).padding(4.dp))
                                }
                                Text(stringResource(icon.title), style = DawnType.footnote, color = Dawn.colors.textPrimary,
                                    modifier = Modifier.padding(top = Spacing.xxs), maxLines = 1)
                            }
                        }
                        repeat(3 - row.size) { Box(Modifier.weight(1f)) }
                    }
                }
            }
        },
    )
}
