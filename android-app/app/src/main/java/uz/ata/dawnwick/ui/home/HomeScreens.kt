package uz.ata.dawnwick.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import java.time.LocalTime
import kotlinx.coroutines.delay
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.NextAlarmCalculator
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.components.AlarmTimeText
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.permissions.PermissionBanner
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/** A tab whose stage is still to come: the cat, and what will be here. */
@Composable
fun ComingNext(text: String, title: String? = null, mood: CatMood = CatMood.YAWNING) {
    Column(Modifier.fillMaxWidth().padding(Spacing.l), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
        if (title != null) {
            CatMascot(mood, Modifier.width(150.dp), ground = if (Dawn.colors.isDark) CatGround.DARK else CatGround.LIGHT)
            Text(title, style = DawnType.title, color = Dawn.colors.textPrimary)
        }
        Text(text, style = DawnType.callout, color = Dawn.colors.textSecondary, textAlign = TextAlign.Center)
    }
}

@Composable
fun StageScreen(title: String, body: String, mood: CatMood) {
    Column(Modifier.fillMaxSize().background(Dawn.colors.background)) {
        Text(title, style = DawnType.display(34), color = Dawn.colors.textPrimary, modifier = Modifier.padding(start = Spacing.s, top = Spacing.s))
        Spacer(Modifier.height(Spacing.xl))
        ComingNext(body, title = stringResource(R.string.coming_soon), mood = mood)
    }
}
