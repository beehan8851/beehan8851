package uz.ata.dawnwick

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Alarm
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.SportsEsports
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.ring.RingActivity
import uz.ata.dawnwick.ui.alarms.AlarmsScreen
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.CatTricksProvider
import uz.ata.dawnwick.ui.editor.AlarmEditor
import uz.ata.dawnwick.ui.today.TodayScreen
import uz.ata.dawnwick.ui.ring.WakeCheckPrompt
import uz.ata.dawnwick.ui.settings.SettingsScreen
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnTheme

class MainActivity : ComponentActivity() {
    override fun attachBaseContext(base: android.content.Context) = super.attachBaseContext(uz.ata.dawnwick.core.AppLanguage.wrap(base))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The app crashed last time: say what happened before anything else.
        if (uz.ata.dawnwick.core.CrashReporter.pending(this) != null) {
            startActivity(Intent(this, uz.ata.dawnwick.core.CrashActivity::class.java))
            finish()
            return
        }
        enableEdgeToEdge()
        route(intent)
        setContent {
            val appearance by graph.preferences.appearanceFlow.collectAsState()
            val dark = when (appearance) {
                uz.ata.dawnwick.settings.Appearance.LIGHT -> false
                uz.ata.dawnwick.settings.Appearance.DARK -> true
                uz.ata.dawnwick.settings.Appearance.SYSTEM -> androidx.compose.foundation.isSystemInDarkTheme()
            }
            DawnTheme(dark) { AppRoot() }
        }
    }

    override fun onResume() {
        super.onResume()
        if (isFinishing) return
        // Reconcile on every return: Android forgets alarms more readily than iOS.
        val graph = graph
        Thread { graph.alarmService.reconcile(skipIds = graph.registry.allReArmIds) }.start()
        // A streak or a night may have earned a companion while the app was away.
        graph.refreshCompanion()
        // Something is ringing: its screen goes first.
        if (graph.ring.state.value != null) startActivity(Intent(this, RingActivity::class.java))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        route(intent)
    }

    /** A notification's way in: the Sleep tab from the night's notification, the wind-down from the reminder. */
    private fun route(intent: Intent?) {
        val tab = intent?.getIntExtra(EXTRA_TAB, -1) ?: -1
        if (tab >= 0) graph.navigation.value = tab to intent!!.getBooleanExtra(EXTRA_WIND_DOWN, false)
        // A locked Premium widget's way in.
        if (intent?.getBooleanExtra(EXTRA_PAYWALL, false) == true) graph.showPaywall(uz.ata.dawnwick.premium.PremiumFeature.HOME_WIDGET)
    }

    override fun onPause() {
        super.onPause()
        if (isFinishing && uz.ata.dawnwick.core.CrashReporter.pending(this) != null) return
        // Whatever changed while the app was open — alarms, streak, Premium — the widgets show it.
        uz.ata.dawnwick.widgets.DawnWidgets.refresh(this)
    }

    companion object {
        const val EXTRA_TAB = "tab"
        const val EXTRA_WIND_DOWN = "wind_down"
        const val EXTRA_WAKE_CHECK = "wake_check"
        const val EXTRA_PAYWALL = "paywall"
    }
}

private enum class Tab(val title: Int, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    TODAY(R.string.tab_today, Icons.Rounded.WbSunny),
    ALARMS(R.string.tab_alarms, Icons.Rounded.Alarm),
    SLEEP(R.string.tab_sleep, Icons.Rounded.Bedtime),
    PLAY(R.string.tab_play, Icons.Rounded.SportsEsports),
    SETTINGS(R.string.tab_settings, Icons.Rounded.Settings),
}

@Composable
private fun AppRoot() {
    val context = LocalContext.current
    val graph = context.graph
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var alarms by androidx.compose.runtime.remember { mutableStateOf(graph.alarmService.fetchAll()) }
    var editing by androidx.compose.runtime.remember { mutableStateOf<Pair<Boolean, Alarm?>?>(null) }
    val wakeCheck by graph.ring.wakeCheck.collectAsState()
    var now by androidx.compose.runtime.remember { mutableStateOf(System.currentTimeMillis()) }

    var best by androidx.compose.runtime.remember { mutableIntStateOf(graph.streak.load().bestStreak) }
    fun reload() { alarms = graph.alarmService.fetchAll(); best = graph.streak.load().bestStreak }
    // A notification's way in: the night's opens Sleep, the bedtime reminder opens the wind-down.
    var windDownRequested by androidx.compose.runtime.remember { mutableStateOf(false) }
    val navigation by graph.navigation.collectAsState()
    LaunchedEffect(navigation) {
        val (to, windDown) = navigation ?: return@LaunchedEffect
        tab = to
        if (windDown) windDownRequested = true
        graph.navigation.value = null
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        reload()
        now = System.currentTimeMillis()
        // Back from a won morning: Today, where the cat celebrates.
        if (graph.ring.returnToToday) { graph.ring.returnToToday = false; tab = 0 }
    }
    LaunchedEffect(wakeCheck) {
        while (wakeCheck != null) { kotlinx.coroutines.delay(5_000); now = System.currentTimeMillis() }
    }

    // First launch: onboarding explains and asks for what an alarm needs, then sets the first alarm.
    var onboarding by androidx.compose.runtime.remember { mutableStateOf(!graph.preferences.onboardingCompleted) }
    if (onboarding) {
        uz.ata.dawnwick.ui.onboarding.OnboardingScreen {
            graph.preferences.onboardingCompleted = true
            onboarding = false
            reload()
        }
        return
    }

    val paywall by graph.paywall.collectAsState()
    paywall?.let { reason ->
        androidx.compose.ui.window.Dialog(
            onDismissRequest = { graph.paywall.value = null },
            properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            uz.ata.dawnwick.ui.premium.PaywallScreen(reason) { graph.paywall.value = null; reload() }
        }
    }

    // A free account at its limit meets the paywall before the editor, not after filling it in.
    fun newAlarm() {
        if (!graph.isPremium && alarms.size >= uz.ata.dawnwick.alarm.FreeTier.ENABLED_ALARM_LIMIT) {
            graph.showPaywall(uz.ata.dawnwick.premium.PremiumFeature.UNLIMITED_ALARMS)
        } else {
            editing = true to null
        }
    }

    val promptAt = graph.ring.wakeCheckPromptAt()
    if (wakeCheck != null && promptAt != null && now >= promptAt) {
        CatTricksProvider(best) { WakeCheckPrompt(onAwake = { graph.ring.acknowledgeWakeCheck() }, onFellAsleep = { graph.ring.failWakeCheck() }) }
        return
    }

    editing?.let { (_, alarm) ->
        AlarmEditor(existing = alarm, onClose = { editing = null; reload() })
        return
    }

    CatTricksProvider(best) { Scaffold(
        containerColor = Dawn.colors.background,
        bottomBar = {
            NavigationBar(containerColor = Dawn.colors.surfacePrimary) {
                Tab.entries.forEachIndexed { i, t ->
                    NavigationBarItem(
                        selected = tab == i, onClick = { tab = i },
                        icon = { Icon(t.icon, null) }, label = { Text(stringResource(t.title)) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = DawnColors.Ink, indicatorColor = DawnColors.Yolk,
                            selectedTextColor = Dawn.colors.textPrimary, unselectedIconColor = Dawn.colors.textTertiary,
                            unselectedTextColor = Dawn.colors.textTertiary,
                        ),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
            when (Tab.entries[tab]) {
                Tab.TODAY -> TodayScreen(alarms, onAddAlarm = ::newAlarm, onAllGames = { tab = Tab.PLAY.ordinal })
                Tab.ALARMS -> AlarmsScreen(alarms, onOpen = { if (it == null) newAlarm() else { editing = true to it } }, onChanged = ::reload)
                Tab.SLEEP -> uz.ata.dawnwick.ui.sleep.SleepScreen(alarms, windDownRequested, onWindDownHandled = { windDownRequested = false })
                Tab.PLAY -> uz.ata.dawnwick.ui.games.PlayScreen()
                Tab.SETTINGS -> SettingsScreen()
            }
        }
    } }
}
