package uz.ata.dawnwick.ui.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import uz.ata.dawnwick.alarm.model.AlarmTime
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.theme.DawnType

/** An alarm's time, set large, with a small AM/PM on a 12-hour clock. */
@Composable
fun AlarmTimeText(time: AlarmTime, size: Int, color: Color, modifier: Modifier = Modifier, periodColor: Color = color, weight: FontWeight = FontWeight.Black) {
    val (digits, period) = TimeFormat.timeParts(LocalContext.current, time)
    Row(modifier, verticalAlignment = Alignment.Bottom) {
        Text(digits, style = DawnType.display(size, weight).copy(fontFeatureSettings = "tnum"), color = color)
        if (period != null) {
            Spacer(Modifier.width(4.dp))
            Text(period, style = TextStyle(fontSize = (size * 0.32).sp, fontWeight = FontWeight.Bold), color = periodColor,
                modifier = Modifier.alignByBaseline())
        }
    }
}
