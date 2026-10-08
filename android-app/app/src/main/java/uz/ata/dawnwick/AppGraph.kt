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

    val subscription = uz.ata.dawnwick.premium.SubscriptionService(context, store)
    val alarmService = AlarmService(repository, engine, registry, entitlements = { isPremium })
    val isPremium get() = subscription.isPremium

    val companions = uz.ata.dawnwick.companion.CompanionStore(store)

    /** Everything that decides which companions are open, read now. Earned ones are kept for good. */
    fun companionProgress(): uz.ata.dawnwick.companion.CompanionProgress {
        val nights = sleep.repository.loadCompleted().count { (it.durationMillis ?: 0) >= 60 * 60_000L }
        var p = uz.ata.dawnwick.companion.CompanionProgress(
            premium = isPremium, bestStreak = streak.load().bestStreak, nightsTracked = nights,
            purchased = subscription.purchased.value, earned = companions.earned,
        )
        val fresh = p.newlyEarned()
        if (fresh.isNotEmpty()) { companions.earned = p.earned + fresh; p = p.copy(earned = p.earned + fresh) }
        return p
    }

    /** The companion on screen everywhere but the games. */
    val companion = kotlinx.coroutines.flow.MutableStateFlow(uz.ata.dawnwick.companion.Pet.CAT)
    fun refreshCompanion() { companion.value = companions.shown(companionProgress()) }

    /** A paywall someone asked for, with the reason; the app's root shows it over everything. */
    val paywall = kotlinx.coroutines.flow.MutableStateFlow<uz.ata.dawnwick.premium.PremiumFeature?>(null)
    fun showPaywall(reason: uz.ata.dawnwick.premium.PremiumFeature = uz.ata.dawnwick.premium.PremiumFeature.GENERAL) { paywall.value = reason }
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
        uz.ata.dawnwick.core.CrashReporter.install(this)
        // The last start crashed: starting again would crash again, so only the report is shown.
        if (uz.ata.dawnwick.core.CrashReporter.startupCrashPending(this)) return
        uz.ata.dawnwick.core.CrashReporter.startupBegins()
        graph = AppGraph(this)
        graph.subscription.onEntitlementsChanged = { graph.refreshCompanion() }
        graph.subscription.start()
        graph.refreshCompanion()
        RingNotifications.createChannels(this)
        uz.ata.dawnwick.ui.cat.CatSounds.init(this)
        uz.ata.dawnwick.core.CrashReporter.startupEnds()
    }
}

val Context.graph: AppGraph get() = (applicationContext as DawnwickApp).graph
