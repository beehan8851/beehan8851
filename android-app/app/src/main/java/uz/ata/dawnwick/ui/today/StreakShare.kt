package uz.ata.dawnwick.ui.today

import uz.ata.dawnwick.graph
import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.core.content.FileProvider
import java.io.File
import uz.ata.dawnwick.R
import uz.ata.dawnwick.streak.DayCell
import uz.ata.dawnwick.streak.DayOutcome
import uz.ata.dawnwick.ui.cat.CatArt
import uz.ata.dawnwick.ui.cat.CatArt.drawCat
import uz.ata.dawnwick.ui.cat.CatDressing
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.Shapes
import uz.ata.dawnwick.ui.theme.DawnColors

/**
 * The streak as a picture to send someone: yolk, the number set huge in ink, the
 * week's paw prints, and the cat — proud, and wearing whatever it has earned. 4 : 5,
 * the shape a feed shows whole, and always light: it is the app's morning colour.
 */
object StreakShare {
    private const val W = 360f
    private const val H = 450f
    private const val SCALE = 3f

    fun image(context: Context, streak: Int, week: List<DayCell>, dressing: CatDressing): ImageBitmap {
        val bitmap = ImageBitmap((W * SCALE).toInt(), (H * SCALE).toInt())
        val canvas = Canvas(bitmap)
        val words = context.resources.getQuantityString(R.plurals.days_in_a_row, streak, streak)
        val (before, after) = words.split("$streak", limit = 2).let { it[0].trim() to it.getOrElse(1) { "" }.trim() }
        CanvasDrawScope().draw(Density(SCALE), LayoutDirection.Ltr, canvas, Size(W * SCALE, H * SCALE)) {
            drawRect(DawnColors.Yolk)
            val k = SCALE
            val native = drawContext.canvas.nativeCanvas
            fun paint(size: Float, alpha: Float = 1f, weight: Int = Typeface.BOLD) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = DawnColors.Ink.copy(alpha = alpha).toArgb()
                textSize = size * k
                typeface = Typeface.create(Typeface.DEFAULT, weight)
            }
            native.drawText("Dawnwick", 28 * k, 46 * k, paint(15f, 0.75f))
            var y = 180f
            if (before.isNotEmpty()) { native.drawText(before, 28 * k, y * k, paint(22f)); y += 8 }
            val numberPaint = paint(140f)
            val maxWidth = (W - 56) * k
            while (numberPaint.measureText("$streak") > maxWidth && numberPaint.textSize > 60 * k) numberPaint.textSize -= 4 * k
            y += numberPaint.textSize / k * 0.78f
            native.drawText("$streak", 24 * k, y * k, numberPaint)
            y += 34
            // The words after the number, wrapped to 200 points.
            val afterPaint = paint(24f)
            var line = ""
            for (word in after.split(" ").filter { it.isNotEmpty() }) {
                val tryLine = if (line.isEmpty()) word else "$line $word"
                if (afterPaint.measureText(tryLine) > 200 * k && line.isNotEmpty()) {
                    native.drawText(line, 28 * k, y * k, afterPaint); y += 30; line = word
                } else line = tryLine
            }
            if (line.isNotEmpty()) native.drawText(line, 28 * k, y * k, afterPaint)

            // The week, clear of the cat in the corner.
            val cell = 180f / 7
            week.forEachIndexed { i, day ->
                val c = Offset((28 + cell * i + cell / 2) * k, (H - 40) * k)
                val d = 22 * k
                fun box(f: Float) = Rect(Offset(c.x - d * f / 2, c.y - d * f / 2), Size(d * f, d * f))
                when (day.outcome) {
                    DayOutcome.WON -> drawPath(Shapes.pawPrint(box(0.9f)), DawnColors.Ink)
                    DayOutcome.COVERED -> drawPath(Shapes.pawPrint(box(0.84f)), DawnColors.Ink, style = Stroke(1.5f * k))
                    DayOutcome.MISSED -> {
                        val r = d * 0.18f
                        drawLine(DawnColors.Ink, Offset(c.x - r, c.y - r), Offset(c.x + r, c.y + r), d * 0.09f)
                        drawLine(DawnColors.Ink, Offset(c.x - r, c.y + r), Offset(c.x + r, c.y - r), d * 0.09f)
                    }
                    DayOutcome.TODAY -> drawCircle(DawnColors.Ink, d * 0.39f, c, style = Stroke(2 * k, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.2f * k, 3.2f * k))))
                    else -> drawCircle(DawnColors.Ink.copy(alpha = 0.3f), d * 0.1f, c)
                }
            }

            // The companion in the corner.
            val sp = context.graph.companion.value
            val catW = 150 * k
            val catH = catW / uz.ata.dawnwick.ui.cat.companionAspectRatio(sp, CatMood.PROUD)
            translate(W * k - catW - 20 * k, H * k - catH - 22 * k) {
                // drawCat fits the cat to the scope's size: lend it the corner's.
                val whole = drawContext.size
                drawContext.size = Size(catW, catH)
                if (sp == uz.ata.dawnwick.companion.Pet.CAT) drawCat(CatMood.PROUD, CatGround.LIGHT, 0.6, dressing = dressing)
                else with(uz.ata.dawnwick.ui.cat.CompanionArt) { drawCompanion(sp, CatMood.PROUD, CatGround.LIGHT, 0.6, dressing = dressing) }
                drawContext.size = whole
            }
        }
        return bitmap
    }

    fun share(context: Context, streak: Int, week: List<DayCell>, dressing: CatDressing) {
        val bitmap = image(context, streak, week, dressing).asAndroidBitmap()
        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        val file = File(dir, "streak.png")
        file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TITLE, context.getString(R.string.share_streak_title))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, context.getString(R.string.share_streak_title)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
