package uz.ata.dawnwick.ui.premium

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import uz.ata.dawnwick.R
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.premium.PlanKind
import uz.ata.dawnwick.premium.PlansState
import uz.ata.dawnwick.premium.PremiumFeature
import uz.ata.dawnwick.premium.PurchaseOutcome
import uz.ata.dawnwick.premium.SubscriptionPlan
import uz.ata.dawnwick.premium.SubscriptionService
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.YolkButton
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

private fun PremiumFeature.prompt(): Int = when (this) {
    PremiumFeature.GENERAL -> R.string.pw_subtitle
    PremiumFeature.UNLIMITED_ALARMS -> R.string.pw_reason_alarms
    PremiumFeature.ADVANCED_MISSIONS -> R.string.pw_reason_missions
    PremiumFeature.SLEEP_HISTORY -> R.string.pw_reason_sleep
    PremiumFeature.HOME_WIDGET -> R.string.pw_reason_widget
    PremiumFeature.CAT_NAPS -> R.string.pw_reason_naps
    PremiumFeature.CAT_NAPS_UNLIMITED -> R.string.pw_reason_naps_unlimited
}

tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/**
 * The Premium screen: the promise on a yolk band with the cat, what you get, the plans,
 * then the small print. Price, length and auto-renewal sit next to the button, and
 * "Continue with Free" is always there, as on iOS.
 */
@Composable
fun PaywallScreen(reason: PremiumFeature, onClose: () -> Unit) {
    val context = LocalContext.current
    val service = context.graph.subscription
    val plansState by service.plans.collectAsState()
    val premium by service.premiumFlow.collectAsState()
    var selected by remember { mutableStateOf<PlanKind?>(null) }
    var busy by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { service.loadPlans() }
    // Nothing left to sell: out of the way.
    LaunchedEffect(premium) { if (premium && service.storeAvailable) onClose() }
    BackHandler(onBack = onClose)

    val plans = (plansState as? PlansState.Ready)?.plans.orEmpty()
    val plan = plans.firstOrNull { it.kind == selected } ?: plans.firstOrNull { it.kind == PlanKind.ANNUAL } ?: plans.firstOrNull()

    fun handle(outcome: PurchaseOutcome) {
        busy = false
        val message = when (outcome) {
            PurchaseOutcome.Purchased -> context.getString(R.string.pw_welcome)
            PurchaseOutcome.Cancelled -> null
            PurchaseOutcome.NothingToRestore -> context.getString(R.string.pw_nothing_to_restore)
            is PurchaseOutcome.Failed -> context.getString(R.string.pw_failed, outcome.message)
        }
        message?.let { Toast.makeText(context, it, Toast.LENGTH_LONG).show() }
        if (outcome == PurchaseOutcome.Purchased) onClose()
    }

    Column(Modifier.fillMaxSize().background(Dawn.colors.background).safeDrawingPadding()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Box(Modifier.fillMaxWidth().background(DawnColors.Yolk).padding(Spacing.s)) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(stringResource(R.string.pw_title), style = DawnType.display(32), color = DawnColors.Ink, modifier = Modifier.weight(1f))
                        CatMascot(CatMood.PROUD, Modifier.size(112.dp), ground = CatGround.LIGHT)
                    }
                    Text(stringResource(reason.prompt()), style = DawnType.callout, color = DawnColors.OnYolkSecondary)
                }
                IconButton(onClick = onClose, modifier = Modifier.align(Alignment.TopEnd)) {
                    Icon(Icons.Rounded.Close, stringResource(R.string.cancel), tint = DawnColors.Ink)
                }
            }
            Column(Modifier.padding(Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    listOf(R.string.pw_benefit_alarms, R.string.pw_benefit_sleep, R.string.pw_benefit_widgets,
                        R.string.pw_benefit_naps, R.string.pw_benefit_wake_check).forEach { Benefit(it) }
                }
                when (val s = plansState) {
                    PlansState.Loading -> Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(20.dp), color = Dawn.colors.accent, strokeWidth = 2.dp)
                        Spacer(Modifier.width(Spacing.sm))
                        Text(stringResource(R.string.pw_loading), style = DawnType.callout, color = Dawn.colors.textSecondary)
                    }
                    is PlansState.Error -> Column(verticalArrangement = Arrangement.spacedBy(Spacing.xxs)) {
                        Text(stringResource(R.string.pw_unavailable), style = DawnType.headline, color = Dawn.colors.textPrimary)
                        Text(stringResource(if (service.storeAvailable) R.string.pw_unavailable_detail else R.string.pw_store_missing),
                            style = DawnType.footnote, color = Dawn.colors.textSecondary)
                        if (service.storeAvailable) TextButton(onClick = { service.loadPlans() }) {
                            Text(stringResource(R.string.pw_try_again), style = DawnType.headline, color = Dawn.colors.accent)
                        }
                    }
                    is PlansState.Ready -> Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        s.plans.forEach { p -> PlanCard(p, selected = p == plan) { selected = p.kind } }
                    }
                }
                plan?.let { Text(terms(context, it), style = DawnType.footnote, color = Dawn.colors.textTertiary) }
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    TextButton(onClick = { busy = true; service.restore(::handle) }, enabled = !busy && service.storeAvailable) {
                        Text(stringResource(R.string.pw_restore), style = DawnType.footnote, color = Dawn.colors.textSecondary)
                    }
                    TextButton(onClick = { open(context, SubscriptionService.TERMS_URL) }) {
                        Text(stringResource(R.string.pw_terms_link), style = DawnType.footnote, color = Dawn.colors.textSecondary)
                    }
                    TextButton(onClick = { open(context, SubscriptionService.PRIVACY_URL) }) {
                        Text(stringResource(R.string.pw_privacy_link), style = DawnType.footnote, color = Dawn.colors.textSecondary)
                    }
                }
            }
        }
        Column(Modifier.fillMaxWidth().padding(Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.xxs)) {
            YolkButton(
                onClick = {
                    val activity = context.findActivity() ?: return@YolkButton
                    plan?.let { busy = true; service.purchase(activity, it, ::handle) }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = plan != null && !busy,
            ) {
                ButtonLabel(plan?.trialDays?.let { stringResource(R.string.pw_start_trial, it) } ?: stringResource(R.string.pw_subscribe))
            }
            TextButton(onClick = onClose, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.pw_continue_free), style = DawnType.headline, color = Dawn.colors.textSecondary)
            }
        }
    }
}

@Composable
private fun Benefit(text: Int) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.Check, null, tint = Dawn.colors.success, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.sm))
        Text(stringResource(text), style = DawnType.body, color = Dawn.colors.textPrimary)
    }
}

@Composable
private fun PlanCard(plan: SubscriptionPlan, selected: Boolean, onSelect: () -> Unit) {
    val shape = RoundedCornerShape(Radius.m)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Dawn.colors.surfacePrimary)
            .border(2.dp, if (selected) DawnColors.Yolk else Dawn.colors.separator, shape)
            .pressable(onClick = onSelect).padding(Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(if (selected) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null,
            tint = if (selected) Dawn.colors.accent else Dawn.colors.textTertiary, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(Spacing.sm))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(if (plan.kind == PlanKind.ANNUAL) R.string.pw_annual else R.string.pw_monthly),
                    style = DawnType.headline, color = Dawn.colors.textPrimary)
                plan.trialDays?.let {
                    Spacer(Modifier.width(Spacing.xs))
                    Text(stringResource(R.string.pw_trial_badge, it), style = DawnType.eyebrow, color = DawnColors.Ink,
                        modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(DawnColors.Yolk).padding(horizontal = 6.dp, vertical = 2.dp))
                }
            }
            Text(
                when {
                    plan.kind == PlanKind.MONTHLY -> stringResource(R.string.pw_monthly_detail, plan.price)
                    plan.monthlyEquivalent != null -> stringResource(R.string.pw_annual_detail, plan.price, plan.monthlyEquivalent)
                    else -> stringResource(R.string.pw_annual_detail_plain, plan.price)
                },
                style = DawnType.footnote, color = Dawn.colors.textSecondary,
            )
        }
    }
}

private fun terms(context: Context, plan: SubscriptionPlan): String {
    val period = context.getString(if (plan.kind == PlanKind.ANNUAL) R.string.pw_year else R.string.pw_month)
    return plan.trialDays?.let { context.getString(R.string.pw_terms_trial, it, plan.price, period) }
        ?: context.getString(R.string.pw_terms, plan.price, period)
}

private fun open(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** Google Play's own subscription page for this app. */
fun openManageSubscriptions(context: Context) = open(
    context, "https://play.google.com/store/account/subscriptions?package=${context.packageName}",
)
