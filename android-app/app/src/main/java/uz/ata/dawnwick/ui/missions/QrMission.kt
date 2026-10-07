package uz.ata.dawnwick.ui.missions

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CameraAlt
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uz.ata.dawnwick.BuildConfig
import uz.ata.dawnwick.R
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.MissionKind
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.components.SoftButton
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnTheme
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

object Camera {
    fun present(context: Context) = context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    fun allowed(context: Context) = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    fun openAppSettings(context: Context) {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}

/**
 * The back camera, reading QR codes and the common barcodes as it goes. Each code
 * seen is handed on; what to make of it is the caller's business.
 */
@OptIn(ExperimentalGetImage::class)
@Composable
fun CodeScanner(onCode: (String) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val latest by rememberUpdatedState(onCode)
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }
    DisposableEffect(lifecycleOwner) {
        val executor = Executors.newSingleThreadExecutor()
        val scanner = BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder().setBarcodeFormats(
                Barcode.FORMAT_QR_CODE, Barcode.FORMAT_EAN_13, Barcode.FORMAT_EAN_8,
                Barcode.FORMAT_CODE_128, Barcode.FORMAT_CODE_39, Barcode.FORMAT_UPC_E, Barcode.FORMAT_UPC_A,
            ).build(),
        )
        val main = ContextCompat.getMainExecutor(context)
        val future = ProcessCameraProvider.getInstance(context)
        var provider: ProcessCameraProvider? = null
        future.addListener({
            val p = runCatching { future.get() }.getOrNull() ?: return@addListener
            provider = p
            val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
            val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
            analysis.setAnalyzer(executor) { proxy ->
                val media = proxy.image
                if (media == null) { proxy.close(); return@setAnalyzer }
                scanner.process(InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees))
                    .addOnSuccessListener(main) { codes -> codes.firstNotNullOfOrNull { it.rawValue }?.let { latest(it) } }
                    .addOnCompleteListener { proxy.close() }
            }
            runCatching {
                p.unbindAll()
                p.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            }
        }, main)
        onDispose {
            provider?.unbindAll()
            scanner.close()
            executor.shutdown()
        }
    }
    AndroidView(factory = { previewView }, modifier = modifier)
}

@Composable
private fun CameraDenied(context: Context) {
    val colors = Dawn.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.l), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Rounded.CameraAlt, null, tint = colors.textTertiary, modifier = Modifier.size(48.dp))
        Spacer(Modifier.height(Spacing.s))
        Text(stringResource(R.string.camera_needed), style = DawnType.callout, color = colors.textSecondary, textAlign = TextAlign.Center)
        Spacer(Modifier.height(Spacing.s))
        InkButton(onClick = { Camera.openAppSettings(context) }) { ButtonLabel(stringResource(R.string.open_settings)) }
    }
}

/**
 * Scan the code registered for this alarm — the one left in the kitchen. Anything
 * else turns the frame red for a moment. Camera access was given when the code was
 * registered; if it has since been taken away, the host has already swapped this
 * mission for Math.
 */
@Composable
fun QrMission(config: MissionConfig.QrCode, onSuccess: () -> Unit) {
    val context = LocalContext.current
    val registered = config.registeredCode
    var wrong by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptic = rememberHaptics()
    val colors = Dawn.colors
    val frame by animateColorAsState(if (wrong) colors.destructive else colors.accent, label = "frame")
    val allowed = remember { Camera.allowed(context) }

    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        MissionHeader(MissionKind.QR_CODE)
        when {
            !allowed -> { Spacer(Modifier.weight(1f)); CameraDenied(context); Spacer(Modifier.weight(1f)) }
            registered == null -> {
                Spacer(Modifier.weight(1f))
                Icon(Icons.Rounded.QrCodeScanner, null, tint = colors.textTertiary, modifier = Modifier.size(48.dp))
                Text(stringResource(R.string.qr_not_configured), style = DawnType.callout, color = colors.textSecondary,
                    textAlign = TextAlign.Center, modifier = Modifier.padding(Spacing.l))
                Spacer(Modifier.weight(1f))
            }
            else -> {
                Box(Modifier.padding(horizontal = Spacing.l).fillMaxWidth().height(320.dp).clip(RoundedCornerShape(Radius.m)).border(2.dp, frame, RoundedCornerShape(Radius.m))) {
                    CodeScanner(onCode = { code ->
                        if (done) return@CodeScanner
                        if (code == registered) {
                            done = true
                            haptic.perform(Haptic.SUCCESS)
                            onSuccess()
                        } else if (!wrong) {
                            haptic.perform(Haptic.ERROR)
                            wrong = true
                            scope.launch { delay(1500); wrong = false }
                        }
                    }, modifier = Modifier.fillMaxSize())
                }
                Spacer(Modifier.height(Spacing.m))
                Text(stringResource(if (wrong) R.string.qr_wrong else R.string.qr_instruction), style = DawnType.callout,
                    color = if (wrong) colors.destructive else colors.textSecondary, textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = Spacing.l))
                Spacer(Modifier.weight(1f))
                // Debug builds only: the registered code, as if the camera had read it.
                if (BuildConfig.DEBUG) {
                    TextButton(onClick = { if (!done) { done = true; onSuccess() } }, modifier = Modifier.padding(bottom = Spacing.l)) {
                        Text(stringResource(R.string.simulate_scan), style = DawnType.callout, color = colors.textSecondary)
                    }
                }
            }
        }
    }
}

/** Registering the code in the editor: ask for the camera, scan, look, keep. */
@Composable
fun QrSetupDialog(onSave: (String) -> Unit, onCancel: () -> Unit) {
    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DawnTheme {
            val context = LocalContext.current
            var status by remember { mutableStateOf(if (Camera.allowed(context)) "granted" else "asking") }
            var code by remember { mutableStateOf<String?>(null) }
            val haptic = rememberHaptics()
            val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
                status = if (granted) "granted" else "denied"
            }
            LaunchedEffect(Unit) { if (status == "asking") launcher.launch(Manifest.permission.CAMERA) }
            val colors = Dawn.colors
            Column(Modifier.fillMaxSize().background(colors.background).safeDrawingPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.textSecondary) }
                    Text(stringResource(R.string.qr_setup_title), style = DawnType.headline, color = colors.textPrimary,
                        textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                    Spacer(Modifier.size(72.dp, 1.dp))
                }
                Spacer(Modifier.height(Spacing.m))
                when (status) {
                    "denied" -> { Spacer(Modifier.weight(1f)); CameraDenied(context); Spacer(Modifier.weight(1f)) }
                    "asking" -> Spacer(Modifier.weight(1f))
                    else -> {
                        val found = code
                        if (found == null) {
                            Text(stringResource(R.string.qr_setup_instruction), style = DawnType.callout, color = colors.textSecondary,
                                textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = Spacing.l))
                            Spacer(Modifier.height(Spacing.m))
                            Box(Modifier.padding(horizontal = Spacing.l).fillMaxWidth().height(320.dp).clip(RoundedCornerShape(Radius.m))) {
                                CodeScanner(onCode = { if (code == null) { code = it; haptic.perform(Haptic.SUCCESS) } }, modifier = Modifier.fillMaxSize())
                            }
                        } else {
                            Spacer(Modifier.height(Spacing.l))
                            Icon(Icons.Rounded.CheckCircle, null, tint = colors.success, modifier = Modifier.size(48.dp))
                            Spacer(Modifier.height(Spacing.s))
                            Text(stringResource(R.string.qr_registered), style = DawnType.headline, color = colors.textPrimary)
                            Spacer(Modifier.height(Spacing.xs))
                            Text(if (found.length > 40) found.take(40) + "…" else found, fontFamily = FontFamily.Monospace, fontSize = 13.sp,
                                color = colors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = Spacing.l))
                            Spacer(Modifier.height(Spacing.m))
                            Row(Modifier.padding(horizontal = Spacing.l), horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                                SoftButton(onClick = { code = null }, modifier = Modifier.weight(1f)) { ButtonLabel(stringResource(R.string.rescan)) }
                                InkButton(onClick = { onSave(found) }, modifier = Modifier.weight(1f)) { ButtonLabel(stringResource(R.string.save)) }
                            }
                        }
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}
