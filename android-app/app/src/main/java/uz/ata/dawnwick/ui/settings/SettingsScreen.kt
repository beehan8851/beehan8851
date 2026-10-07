package uz.ata.dawnwick.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Box
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.model.AlarmSound
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.components.RowDivider
import uz.ata.dawnwick.ui.components.Section
import uz.ata.dawnwick.ui.components.SectionRow
import uz.ata.dawnwick.ui.editor.soundName
import uz.ata.dawnwick.ui.permissions.AlarmPermission
import uz.ata.dawnwick.ui.permissions.rememberPermissionTick
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.Email
import androidx.compose.material.icons.rounded.PanTool
import androidx.compose.material.icons.rounded.StarRate
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontWeight
import uz.ata.dawnwick.settings.Appearance
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Spacing

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val prefs = context.graph.preferences
    val tick = rememberPermissionTick()
    var haptics by remember { mutableStateOf(prefs.hapticsEnabled) }
    var sound by remember { mutableStateOf(prefs.defaultSound) }
    var soundMenu by remember { mutableStateOf(false) }
    val colors = Dawn.colors
    Column(Modifier.fillMaxSize().background(colors.background).verticalScroll(rememberScrollState())) {
        Text(stringResource(R.string.tab_settings), style = DawnType.display(34), color = colors.textPrimary,
            modifier = Modifier.padding(start = Spacing.s, top = Spacing.s, bottom = Spacing.xs))

        Section(stringResource(R.string.reliability), footer = stringResource(R.string.reliability_footer)) {
            AlarmPermission.entries.forEachIndexed { i, p ->
                if (i > 0) RowDivider()
                val granted = remember(tick) { p.isGranted(context) }
                SectionRow(stringResource(p.title), subtitle = if (granted) null else stringResource(p.detail), onClick = { p.open(context) }) {
                    Icon(if (granted) Icons.Rounded.CheckCircle else Icons.Rounded.ErrorOutline, null,
                        tint = if (granted) colors.success else colors.warning, modifier = Modifier.size(22.dp))
                }
            }
        }

        Section(stringResource(R.string.alarms_section)) {
            Box {
                SectionRow(stringResource(R.string.default_sound), onClick = { soundMenu = true }) {
                    Text(soundName(sound), style = DawnType.body, color = colors.accent)
                }
                DropdownMenu(expanded = soundMenu, onDismissRequest = { soundMenu = false }) {
                    AlarmSound.entries.forEach { s ->
                        DropdownMenuItem(text = { Text(soundName(s)) }, onClick = { sound = s; prefs.defaultSound = s; soundMenu = false })
                    }
                }
            }
            RowDivider()
            SectionRow(stringResource(R.string.haptics), onClick = { haptics = !haptics; prefs.hapticsEnabled = haptics }) {
                Switch(haptics, { haptics = it; prefs.hapticsEnabled = it },
                    colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.background))
            }
        }

        Section(stringResource(R.string.appearance)) {
            Column(Modifier.padding(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(stringResource(R.string.theme), style = DawnType.body, color = colors.textPrimary)
                var appearance by remember { mutableStateOf(prefs.appearance) }
                val labels = listOf(R.string.appearance_system, R.string.appearance_light, R.string.appearance_dark)
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    Appearance.entries.forEachIndexed { i, a ->
                        SegmentedButton(selected = appearance == a, onClick = { appearance = a; prefs.appearance = a },
                            shape = SegmentedButtonDefaults.itemShape(i, Appearance.entries.size)) { Text(stringResource(labels[i])) }
                    }
                }
            }
        }

        // About: where to get help and how the data is handled. The version lives in
        // the colophon below, not in a row.
        Section(stringResource(R.string.about)) {
            if (LegalLinks.PUBLISHED) {
                LinkRow(Icons.Rounded.StarRate, stringResource(R.string.rate_app)) {
                    openUrl(context, "market://details?id=${context.packageName}")
                }
                RowDivider()
            }
            LinkRow(Icons.Rounded.Email, stringResource(R.string.help_contact)) { openUrl(context, LegalLinks.SUPPORT) }
            RowDivider()
            LinkRow(Icons.Rounded.PanTool, stringResource(R.string.privacy_policy)) { openUrl(context, LegalLinks.PRIVACY) }
        }

        // The version, at the end of the list, under the cat asleep on its moon.
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val build = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
        Column(Modifier.fillMaxWidth().padding(vertical = Spacing.l), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            CatMascot(CatMood.SLEEPING, Modifier.width(96.dp).alpha(0.9f), ground = if (colors.isDark) CatGround.DARK else CatGround.LIGHT)
            Text("Dawnwick ${info.versionName} ($build)", style = DawnType.footnote.copy(fontWeight = FontWeight.Medium), color = colors.textTertiary)
        }
    }
}

/** Where the app's pages live: the same as the iOS app's. */
object LegalLinks {
    const val PRIVACY = "https://numonov.github.io/dawnwick-site/privacy.html"
    const val SUPPORT = "https://numonov.github.io/dawnwick-site/support.html"
    /** The rating row appears once the app is on Google Play. */
    const val PUBLISHED = false
}

private fun openUrl(context: android.content.Context, url: String) {
    runCatching { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url)).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

@Composable
private fun LinkRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = Spacing.sm, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Dawn.colors.accent, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.sm))
        Text(title, style = DawnType.body, color = Dawn.colors.textPrimary, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Rounded.OpenInNew, null, tint = Dawn.colors.textTertiary, modifier = Modifier.size(18.dp))
    }
}
