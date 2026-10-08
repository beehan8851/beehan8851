package uz.ata.dawnwick.ring

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import uz.ata.dawnwick.R
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.ring.MissionHost
import uz.ata.dawnwick.ui.ring.MissionSuccess
import uz.ata.dawnwick.ui.ring.RingScreen
import uz.ata.dawnwick.ui.theme.DaylightTheme
import uz.ata.dawnwick.ui.cat.CatTricksProvider
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics

/**
 * The ring screen, over the lock screen and with the screen switched on. Back does
 * nothing: the only ways out are the mission and the snooze. Leaving by Home does
 * not stop the alarm either — the sound belongs to the service.
 */
class RingActivity : ComponentActivity() {

    private enum class Stage { RING, MISSION, SUCCESS }

    override fun attachBaseContext(base: android.content.Context) = super.attachBaseContext(uz.ata.dawnwick.core.AppLanguage.wrap(base))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        enableEdgeToEdge()
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = Unit
        })
        val ring = graph.ring
        setContent {
            DaylightTheme { CatTricksProvider {
                val ringing by ring.state.collectAsState()
                var stage by remember { mutableStateOf(Stage.RING) }
                var finishedAlarm by remember { mutableStateOf(ringing?.alarm) }
                var missionStartedAt by remember { mutableStateOf(0L) }
                var streakDays by remember { mutableStateOf(0) }
                val haptics = rememberHaptics()
                LaunchedEffect(stage) { RingService.setVibration(this@RingActivity, stage == Stage.RING) }
                val alarm = ringing?.alarm ?: finishedAlarm

                LaunchedEffect(ringing) {
                    // Nothing ringing and nothing just finished: there is no screen to show.
                    if (ringing == null && stage != Stage.SUCCESS) finish()
                    ringing?.alarm?.let { finishedAlarm = it }
                }
                if (alarm == null) return@CatTricksProvider

                AnimatedContent(stage, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "ring") { s ->
                    when (s) {
                        Stage.RING -> RingScreen(
                            alarm = alarm,
                            snoozeCount = ring.snoozeCount(alarm.id),
                            onStartMission = {
                                haptics.perform(Haptic.WARNING)
                                missionStartedAt = System.currentTimeMillis()
                                stage = Stage.MISSION
                            },
                            onSnooze = {
                                haptics.perform(Haptic.MEDIUM)
                                if (ring.snooze(alarm)) finish()
                                else Toast.makeText(this@RingActivity, R.string.snooze_failed, Toast.LENGTH_LONG).show()
                            },
                        )
                        Stage.MISSION -> MissionHost(
                            alarm = alarm,
                            onAllDone = {
                                ring.complete(alarm)
                                streakDays = graph.streak.let { it.load().liveStreak(java.time.LocalDate.now(), it.scheduled(graph.repository.fetchAll())) }
                                stage = Stage.SUCCESS
                            },
                            onTimeout = { stage = Stage.RING },
                        )
                        Stage.SUCCESS -> MissionSuccess(
                            elapsedSeconds = ((System.currentTimeMillis() - missionStartedAt) / 1000).toInt(),
                            streakDays = streakDays,
                            onComplete = {
                                ring.scheduleWakeCheck(alarm)
                                finish()
                            },
                        )
                    }
                }
            } }
        }
    }

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
