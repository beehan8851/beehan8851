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
import uz.ata.dawnwick.companion.Pet
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

        /** The cat icon picked last: the one the cat brings back when it is chosen again. */
        fun chosen(context: Context): AppIcon =
            context.graph.store.getString(CHOSEN)?.let { name -> entries.firstOrNull { it.name == name } } ?: CLASSIC

        /** Picks `icon` for the cat and puts it on the home screen. */
        fun set(context: Context, icon: AppIcon): Boolean {
            context.graph.store.putString(CHOSEN, icon.name)
            return LauncherIcon.show(context, icon.alias)
        }

        private const val CHOSEN = "app_icon.cat"
    }
}

/**
 * Which face is on the home screen. Each is an `activity-alias` and exactly one is
 * enabled: one of the cat's five, or the chosen companion's own.
 */
object LauncherIcon {
    fun petAlias(pet: Pet) = "Icon" + pet.name.lowercase().replaceFirstChar { it.uppercase() }

    /** A companion's icon as the picker shows it. */
    fun petPreview(pet: Pet) = when (pet) {
        Pet.CAT -> R.drawable.icon_preview_classic
        Pet.PUPPY -> R.drawable.icon_preview_puppy
        Pet.CHICK -> R.drawable.icon_preview_chick
        Pet.CANARY -> R.drawable.icon_preview_canary
        Pet.LAMB -> R.drawable.icon_preview_lamb
        Pet.OWL -> R.drawable.icon_preview_owl
        Pet.HAMSTER -> R.drawable.icon_preview_hamster
    }

    private val all get() = AppIcon.entries.map { it.alias } + Pet.entries.filter { it != Pet.CAT }.map(::petAlias)

    private fun component(context: Context, alias: String) = ComponentName(context.packageName, "${context.packageName}.$alias")

    private fun isOn(context: Context, alias: String) = when (context.packageManager.getComponentEnabledSetting(component(context, alias))) {
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
        // Never changed: the manifest's own setting, where only Classic is on.
        PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> alias == AppIcon.CLASSIC.alias
        else -> false
    }

    /** The companion on the home screen: its own face, or for the cat the icon picked for it. */
    fun follow(context: Context, pet: Pet) {
        val alias = if (pet == Pet.CAT) AppIcon.chosen(context).alias else petAlias(pet)
        if (!runCatching { isOn(context, alias) }.getOrDefault(true)) show(context, alias)
    }

    /** The companion whose face is on the home screen, or null when it is one of the cat's. */
    fun currentPet(context: Context): Pet? = Pet.entries.firstOrNull { it != Pet.CAT && runCatching { isOn(context, petAlias(it)) }.getOrDefault(false) }

    /** Turns `alias` on before the others off, so there is never a moment with no launcher entry. */
    fun show(context: Context, alias: String): Boolean = runCatching {
        val pm = context.packageManager
        pm.setComponentEnabledSetting(component(context, alias), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        all.filter { it != alias }.forEach {
            pm.setComponentEnabledSetting(component(context, it), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
        }
    }.isSuccess
}

@Composable
fun AppIconPicker(onClose: () -> Unit) {
    val context = LocalContext.current
    val premium = context.graph.isPremium
    // While a companion's face is on the home screen, none of the cat's is current.
    var current by remember { mutableStateOf<AppIcon?>(if (LauncherIcon.currentPet(context) != null) null else AppIcon.current(context)) }
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
