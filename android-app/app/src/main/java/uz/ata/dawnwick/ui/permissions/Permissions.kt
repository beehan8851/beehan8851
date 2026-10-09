package uz.ata.dawnwick.ui.permissions

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.NotificationsOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import uz.ata.dawnwick.R
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/**
 * What an alarm needs from Android to ring reliably, and where to put each right.
 * Notifications carry the ring screen; exact alarms ring on the minute; the
 * full-screen permission puts the ring over a locked phone; and a phone maker's
 * battery saver must leave the app alone.
 */
enum class AlarmPermission(val title: Int, val detail: Int, val critical: Boolean) {
    NOTIFICATIONS(R.string.perm_notifications, R.string.perm_notifications_detail, true),
    EXACT_ALARMS(R.string.perm_exact, R.string.perm_exact_detail, true),
    FULL_SCREEN(R.string.perm_full_screen, R.string.perm_full_screen_detail, true),
    BATTERY(R.string.perm_battery, R.string.perm_battery_detail, false);

    fun isGranted(context: Context): Boolean = when (this) {
        NOTIFICATIONS -> NotificationManagerCompat.from(context).areNotificationsEnabled()
        EXACT_ALARMS -> Build.VERSION.SDK_INT < Build.VERSION_CODES.S || context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
        FULL_SCREEN -> Build.VERSION.SDK_INT < 34 || context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
        BATTERY -> context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)
    }

    fun settingsIntent(context: Context): Intent {
        val pkg = Uri.parse("package:${context.packageName}")
        return when (this) {
            NOTIFICATIONS -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            EXACT_ALARMS -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, pkg)
                else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
            FULL_SCREEN -> if (Build.VERSION.SDK_INT >= 34) Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg)
                else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
            BATTERY -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    fun open(context: Context) {
        runCatching { context.startActivity(settingsIntent(context)) }
            .onFailure { context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    companion object {
        fun missingCritical(context: Context) = entries.filter { it.critical && !it.isGranted(context) }
    }
}

/** Re-reads permissions every time the screen comes back, from Settings especially. */
@Composable
fun rememberPermissionTick(): Int {
    var tick by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { tick++ }
    return tick
}

/** Shown while something an alarm needs is missing: alarms will not ring reliably. */
@Composable
fun PermissionBanner(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val tick = rememberPermissionTick()
    val missing = remember(tick) { AlarmPermission.missingCritical(context) }.firstOrNull() ?: return
    Row(
        modifier.fillMaxWidth().padding(horizontal = Spacing.s, vertical = Spacing.xs)
            .clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary)
            .padding(start = Spacing.s, top = Spacing.sm, bottom = Spacing.sm, end = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.NotificationsOff, null, tint = Dawn.colors.warning, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(Spacing.sm))
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.alarms_wont_ring), style = DawnType.headline, color = Dawn.colors.textPrimary)
            Text(stringResource(missing.detail), style = DawnType.footnote, color = Dawn.colors.textSecondary)
        }
        TextButton(onClick = { missing.open(context) }) {
            Text(stringResource(R.string.fix), style = DawnType.headline, color = Dawn.colors.accent)
        }
    }
}
