package uz.ata.dawnwick

import android.app.Application
import android.content.Context
import uz.ata.dawnwick.alarm.AlarmRepository
import uz.ata.dawnwick.alarm.AlarmService
import uz.ata.dawnwick.alarm.ReArmRegistry
import uz.ata.dawnwick.alarm.SystemAlarmEngine
import uz.ata.dawnwick.core.PrefsStore
import uz.ata.dawnwick.ring.RingController
import uz.ata.dawnwick.ring.RingNotifications
import uz.ata.dawnwick.settings.AppPreferences

/** Everything the app is made of, built once. */
class AppGraph(context: Context) {
    val store = PrefsStore(context)
    val preferences = AppPreferences(store)
    val repository = AlarmRepository(store)
    val registry = ReArmRegistry(store)
    val engine = SystemAlarmEngine(context, store)

    /**
     * Premium is not wired yet (RevenueCat comes with the paywall): until it is,
     * everything is open, so nobody meets a limit there is no way past.
     */
    val alarmService = AlarmService(repository, engine, registry, entitlements = { isPremium })
    val isPremium get() = true
    val ring = RingController(context, this)
    val streak = uz.ata.dawnwick.streak.StreakStore(store)
    val brief = uz.ata.dawnwick.today.MorningBriefRepository(context, store)
    val sleep = uz.ata.dawnwick.sleep.SleepTracker(context, store)
    val bedtime = uz.ata.dawnwick.sleep.BedtimeScheduler(context, store)
    val health = uz.ata.dawnwick.sleep.HealthSleep(context)

    /** Where a notification asked the app to open: a tab, and the wind-down. */
    val navigation = kotlinx.coroutines.flow.MutableStateFlow<Pair<Int, Boolean>?>(null)
}

class DawnwickApp : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
        RingNotifications.createChannels(this)
        uz.ata.dawnwick.ui.cat.CatSounds.init(this)
    }
}

val Context.graph: AppGraph get() = (applicationContext as DawnwickApp).graph
