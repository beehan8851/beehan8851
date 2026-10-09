package uz.ata.dawnwick.ui.settings

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import uz.ata.dawnwick.R
import uz.ata.dawnwick.companion.Pet
import uz.ata.dawnwick.companion.Unlock
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.premium.PremiumFeature
import uz.ata.dawnwick.premium.PurchaseOutcome
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.CatSounds
import uz.ata.dawnwick.ui.cat.LocalForcedCompanion
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.SoftButton
import uz.ata.dawnwick.ui.components.YolkButton
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.premium.findActivity
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing
import uz.ata.dawnwick.ui.today.FullPage

fun petName(pet: Pet) = when (pet) {
    Pet.CAT -> R.string.pet_cat
    Pet.PUPPY -> R.string.pet_puppy
    Pet.CHICK -> R.string.pet_chick
    Pet.CANARY -> R.string.pet_canary
    Pet.LAMB -> R.string.pet_lamb
    Pet.OWL -> R.string.pet_owl
    Pet.HAMSTER -> R.string.pet_hamster
}

/** One companion, drawn as itself whichever is chosen. */
@Composable
fun PetPortrait(pet: Pet, mood: CatMood, modifier: Modifier = Modifier, animated: Boolean = true) {
    CompositionLocalProvider(LocalForcedCompanion provides pet) {
        CatMascot(mood, modifier, ground = if (Dawn.colors.isDark) CatGround.DARK else CatGround.LIGHT, animated = animated)
    }
}

/**
 * Every companion: tap one to see it and hear it, choose an open one, and see how to
 * open the rest — a streak, tracked nights, a purchase, or Premium for them all.
 */
@Composable
fun PetPicker(onClose: () -> Unit) {
    FullPage(stringResource(R.string.pets_title), onClose) { PetPickerContent() }
}

/** The picker's page, without its frame. `start`: the companion shown large at first; the chosen one by default. */
@Composable
fun PetPickerContent(start: Pet? = null) {
    val context = LocalContext.current
    val graph = context.graph
    val chosen by graph.companions.chosen.collectAsState()
    val products by graph.subscription.companionProducts.collectAsState()
    val purchased by graph.subscription.purchased.collectAsState()
    val premium by graph.subscription.premiumFlow.collectAsState()
    var progress by remember { mutableStateOf(graph.companionProgress()) }
    var focus by remember { mutableStateOf(start ?: chosen) }
    var busy by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { graph.subscription.loadCompanionProducts(Pet.productIds) }
    LaunchedEffect(purchased, premium) { progress = graph.companionProgress() }

    fun choose(pet: Pet) {
        graph.companions.choose(pet)
        graph.refreshCompanion()
        uz.ata.dawnwick.widgets.DawnWidgets.refresh(context)
    }

    Column(verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
        Text(stringResource(R.string.pets_footer), style = DawnType.footnote, color = Dawn.colors.textSecondary)

        Pet.entries.chunked(3).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                row.forEach { pet ->
                    val open = progress.isUnlocked(pet)
                    val shape = RoundedCornerShape(Radius.m)
                    Column(
                        Modifier.weight(1f).clip(shape).background(Dawn.colors.surfacePrimary)
                            .border(2.dp, if (pet == focus) DawnColors.Yolk else Dawn.colors.separator, shape)
                            .pressable { focus = pet; CatSounds.preview(pet) }
                            .padding(Spacing.xs),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Box(contentAlignment = Alignment.TopEnd) {
                            PetPortrait(pet, CatMood.AWAKE, Modifier.height(78.dp).alpha(if (open) 1f else 0.55f), animated = false)
                            when {
                                pet == chosen && open -> Icon(Icons.Rounded.CheckCircle, null, tint = Dawn.colors.success, modifier = Modifier.size(20.dp))
                                !open -> Icon(Icons.Rounded.Lock, null, tint = DawnColors.Ink,
                                    modifier = Modifier.size(22.dp).clip(RoundedCornerShape(11.dp)).background(DawnColors.Yolk).padding(4.dp))
                            }
                        }
                        Text(stringResource(petName(pet)), style = DawnType.footnote, color = Dawn.colors.textPrimary, maxLines = 1)
                    }
                }
                repeat(3 - row.size) { Box(Modifier.weight(1f)) }
            }
        }

        // The one in focus, larger, with what it takes.
        val pet = focus
        val open = progress.isUnlocked(pet)
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary).padding(Spacing.s),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xs),
        ) {
            PetPortrait(pet, if (open) CatMood.PROUD else CatMood.AWAKE, Modifier.height(150.dp))
            Text(stringResource(petName(pet)), style = DawnType.display(26), color = Dawn.colors.textPrimary)
            TextButton(onClick = { CatSounds.preview(pet) }) {
                Text(stringResource(R.string.pet_tap_to_hear), style = DawnType.footnote, color = Dawn.colors.accent)
            }
            when {
                open && pet == chosen -> SoftButton({}, Modifier.fillMaxWidth(), enabled = false) { ButtonLabel(stringResource(R.string.pet_chosen)) }
                open -> YolkButton({ choose(pet) }, Modifier.fillMaxWidth()) { ButtonLabel(stringResource(R.string.pet_choose)) }
                else -> {
                    when (val u = pet.unlock) {
                        is Unlock.Streak, is Unlock.SleepNights -> {
                            val (done, needed) = progress.progress(pet) ?: (0 to 1)
                            Text(
                                if (u is Unlock.Streak) stringResource(R.string.pet_unlock_streak, u.days) else stringResource(R.string.pet_unlock_nights, (u as Unlock.SleepNights).nights),
                                style = DawnType.body, color = Dawn.colors.textPrimary,
                            )
                            LinearProgressIndicator(
                                progress = { done.toFloat() / needed }, modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)),
                                color = DawnColors.Yolk, trackColor = Dawn.colors.surfaceSecondary,
                            )
                            Text(
                                if (u is Unlock.Streak) pluralStringResource(R.plurals.pet_mornings_progress, needed, done, needed)
                                else pluralStringResource(R.plurals.pet_nights_progress, needed, done, needed),
                                style = DawnType.footnote, color = Dawn.colors.textSecondary,
                            )
                        }
                        is Unlock.Paid -> {
                            val product = products[u.productId]
                            if (product != null) {
                                YolkButton(
                                    {
                                        val activity = context.findActivity() ?: return@YolkButton
                                        busy = true
                                        graph.subscription.buyCompanion(activity, u.productId) { outcome ->
                                            busy = false
                                            if (outcome == PurchaseOutcome.Purchased) {
                                                choose(pet)
                                                Toast.makeText(context, context.getString(R.string.pet_unlocked, context.getString(petName(pet))), Toast.LENGTH_LONG).show()
                                            } else if (outcome is PurchaseOutcome.Failed) {
                                                Toast.makeText(context, context.getString(R.string.pw_failed, outcome.message), Toast.LENGTH_LONG).show()
                                            }
                                        }
                                    },
                                    Modifier.fillMaxWidth(), enabled = !busy,
                                ) { ButtonLabel(stringResource(R.string.pet_buy, product.price.formatted)) }
                            } else {
                                Text(stringResource(R.string.pet_store_unavailable), style = DawnType.footnote, color = Dawn.colors.textSecondary)
                            }
                        }
                        Unlock.Free -> Unit
                    }
                    TextButton(onClick = { graph.showPaywall(PremiumFeature.COMPANIONS) }) {
                        Text(stringResource(R.string.pet_or_premium), style = DawnType.headline, color = Dawn.colors.accent)
                    }
                }
            }
        }
    }
}
