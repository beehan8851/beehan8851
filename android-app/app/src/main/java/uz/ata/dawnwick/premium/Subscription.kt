package uz.ata.dawnwick.premium

import android.app.Activity
import android.content.Context
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.getCustomerInfoWith
import com.revenuecat.purchases.getOfferingsWith
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.purchaseWith
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.restorePurchasesWith
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import uz.ata.dawnwick.BuildConfig
import uz.ata.dawnwick.core.KeyValueStore

/** Why a paywall is being shown: its one line says which tap led there. */
enum class PremiumFeature { GENERAL, UNLIMITED_ALARMS, ADVANCED_MISSIONS, SLEEP_HISTORY, HOME_WIDGET, CAT_NAPS, CAT_NAPS_UNLIMITED }

enum class PlanKind { ANNUAL, MONTHLY }

/** A store plan ready to show. Every price string comes from the store, never from the source. */
data class SubscriptionPlan(
    val kind: PlanKind,
    val pack: Package,
    val price: String,
    /** The same price over a month; null when it adds nothing (the monthly plan). */
    val monthlyEquivalent: String?,
    /** Days of free trial this account is eligible for; null when there is none. */
    val trialDays: Int?,
)

sealed interface PurchaseOutcome {
    data object Purchased : PurchaseOutcome
    data object Cancelled : PurchaseOutcome
    /** The store answered but there was nothing to restore. */
    data object NothingToRestore : PurchaseOutcome
    data class Failed(val message: String) : PurchaseOutcome
}

sealed interface PlansState {
    data object Loading : PlansState
    data class Ready(val plans: List<SubscriptionPlan>) : PlansState
    data class Error(val message: String) : PlansState
}

/**
 * Premium, as RevenueCat tells it. The last answer is kept on the phone, so being
 * offline never turns a subscriber into a free account.
 *
 * Without a RevenueCat key (see android-app/README) the store is not set up: a debug
 * build then runs with Premium open so everything can be tried, a release build runs free.
 */
class SubscriptionService(private val context: Context, private val store: KeyValueStore) {
    private val configured = BuildConfig.REVENUECAT_API_KEY.isNotBlank()
    private val _premium = MutableStateFlow(store.getBoolean(KEY_PREMIUM, false))
    val premiumFlow: StateFlow<Boolean> = _premium
    val isPremium: Boolean get() = if (!configured) BuildConfig.DEBUG else _premium.value

    private val _plans = MutableStateFlow<PlansState>(PlansState.Loading)
    val plans: StateFlow<PlansState> = _plans

    val storeAvailable: Boolean get() = configured

    /** When the active subscription ends or renews, in epoch millis; 0 when unknown. */
    val expiresAt: Long get() = store.getString(KEY_EXPIRES)?.toLongOrNull() ?: 0L

    fun start() {
        if (!configured) return
        Purchases.configure(PurchasesConfiguration.Builder(context, BuildConfig.REVENUECAT_API_KEY).build())
        Purchases.sharedInstance.updatedCustomerInfoListener = com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener { apply(it) }
        Purchases.sharedInstance.getCustomerInfoWith(onError = {}, onSuccess = ::apply)
    }

    fun loadPlans() {
        if (!configured) { _plans.value = PlansState.Error("not configured"); return }
        _plans.value = PlansState.Loading
        Purchases.sharedInstance.getOfferingsWith(
            onError = { _plans.value = PlansState.Error(it.message) },
            onSuccess = { offerings ->
                val offering = offerings[OFFERING_ID] ?: offerings.current
                val plans = listOfNotNull(
                    offering?.annual?.let { plan(PlanKind.ANNUAL, it) },
                    offering?.monthly?.let { plan(PlanKind.MONTHLY, it) },
                )
                _plans.value = if (plans.isEmpty()) PlansState.Error("no plans") else PlansState.Ready(plans)
            },
        )
    }

    fun purchase(activity: Activity, plan: SubscriptionPlan, done: (PurchaseOutcome) -> Unit) {
        if (!configured) { done(PurchaseOutcome.Failed("not configured")); return }
        Purchases.sharedInstance.purchaseWith(
            PurchaseParams.Builder(activity, plan.pack).build(),
            onError = { error, cancelled -> done(if (cancelled) PurchaseOutcome.Cancelled else PurchaseOutcome.Failed(error.message)) },
            onSuccess = { _, info -> apply(info); done(if (_premium.value) PurchaseOutcome.Purchased else PurchaseOutcome.Failed("not active")) },
        )
    }

    fun restore(done: (PurchaseOutcome) -> Unit) {
        if (!configured) { done(PurchaseOutcome.Failed("not configured")); return }
        Purchases.sharedInstance.restorePurchasesWith(
            onError = { done(PurchaseOutcome.Failed(it.message)) },
            onSuccess = { apply(it); done(if (_premium.value) PurchaseOutcome.Purchased else PurchaseOutcome.NothingToRestore) },
        )
    }

    private fun apply(info: CustomerInfo) {
        val entitlement = info.entitlements[ENTITLEMENT_ID]
        val active = entitlement?.isActive == true
        store.putBoolean(KEY_PREMIUM, active)
        store.putString(KEY_EXPIRES, (entitlement?.expirationDate?.time ?: 0L).toString())
        _premium.value = active
    }

    private fun plan(kind: PlanKind, pack: Package): SubscriptionPlan {
        val product = pack.product
        val trial = product.defaultOption?.freePhase?.billingPeriod?.let(::days)?.takeIf { it > 0 }
        return SubscriptionPlan(
            kind = kind, pack = pack, price = product.price.formatted,
            monthlyEquivalent = if (kind == PlanKind.ANNUAL) product.pricePerMonth()?.formatted else null,
            trialDays = trial,
        )
    }

    private fun days(period: Period): Int = when (period.unit) {
        Period.Unit.DAY -> period.value
        Period.Unit.WEEK -> period.value * 7
        Period.Unit.MONTH -> period.value * 30
        Period.Unit.YEAR -> period.value * 365
        else -> 0
    }

    companion object {
        /** The entitlement and offering names set up in RevenueCat. */
        const val ENTITLEMENT_ID = "premium"
        const val OFFERING_ID = "default"
        private const val KEY_PREMIUM = "sub.premium"
        private const val KEY_EXPIRES = "sub.expires"

        const val TERMS_URL = "https://play.google.com/intl/en_us/about/play-terms/"
        const val PRIVACY_URL = "https://numonov.github.io/dawnwick-site/privacy.html"
    }
}
