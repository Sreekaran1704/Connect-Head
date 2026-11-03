package local.connecthead.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import local.connecthead.bt.HeadphoneController
import local.connecthead.media.ListeningLog
import local.connecthead.media.ListeningStats
import local.connecthead.media.NowPlaying
import local.connecthead.media.durationText
import local.connecthead.protocol.EqPreset
import local.connecthead.protocol.NoiseMode
import local.connecthead.protocol.VoiceAssistant
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

// ---- Sound ----

@Composable
fun SoundPage(ui: HeadphoneController.Ui, hp: HeadphoneController) {
    val p = ink
    val s = ui.state
    PageHeader("Sound", "Noise cancelling and ambient sound")
    Card("Mode") { ModeButtons(s.noiseMode) { hp.setNoiseMode(it) } }
    if (s.noiseMode == NoiseMode.AMBIENT) Card("Ambient sound") {
        var draft by remember(s.ambientLevel) { mutableStateOf(s.ambientLevel.toFloat()) }
        SettingRow("Level", "How much of your surroundings you hear") { Text("${draft.roundToInt()}", style = serif(16), color = p.ink) }
        HorizontalFader(draft, 1f..20f, onChange = { draft = it }, onCommit = { hp.setAmbientLevel(draft.roundToInt()) })
        SettingRow("Focus on voice", "Lets voices through more than other sounds") {
            PrintToggle(s.focusOnVoice) { hp.setFocusOnVoice(it) }
        }
    }
}

// ---- Equalizer ----

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EqualizerPage(ui: HeadphoneController.Ui, hp: HeadphoneController) {
    val p = ink
    val s = ui.state
    PageHeader("Equalizer", "Presets and a 5-band EQ with Clear Bass")
    Card("Preset") {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            EqPreset.entries.forEach { preset -> PresetChip(preset, preset == s.eqPreset) { hp.setEqPreset(preset) } }
        }
    }
    Card("Custom") {
        EditableEqCurve(s.eqBands, Modifier.fillMaxWidth().height(110.dp)) { i, v -> hp.setEqBand(i + 1, v) }
        Text("Press and hold a point to drag it, or use the faders.", style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
        val drafts = remember { mutableStateMapOf<Int, Float>() }
        val labels = listOf("Clear bass", "400", "1k", "2.5k", "6.3k", "16k")
        val values = listOf(s.clearBass) + s.eqBands
        Row(Modifier.fillMaxWidth().height(200.dp)) {
            labels.forEachIndexed { i, label ->
                val shown = drafts[i] ?: values[i].toFloat()
                Column(Modifier.weight(1f).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("%+d".format(shown.roundToInt()), style = serif(14), color = p.ink)
                    VerticalFader(shown, Modifier.weight(1f).width(40.dp).padding(vertical = 6.dp),
                        onChange = { drafts[i] = it },
                        onCommit = { drafts.remove(i)?.let { hp.setEqBand(i, it.roundToInt()) } })
                    Text(label.uppercase(), style = labelStyle.copy(fontSize = 8.5.sp, letterSpacing = 0.8.sp), color = p.secondary,
                        textAlign = TextAlign.Center, maxLines = 1)
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Moving a fader switches the preset to Manual.", style = serif(12, FontWeight.Normal, italic = true),
                color = p.secondary, modifier = Modifier.weight(1f))
            PrintButton("Reset") { hp.resetEq() }
        }
    }
}

/** One EQ preset as an outlined tag; the current one is inked in. */
@Composable
fun PresetChip(preset: EqPreset, on: Boolean, onClick: () -> Unit) {
    val p = ink
    Text(preset.label, style = serif(13, if (on) FontWeight.SemiBold else FontWeight.Normal),
        color = if (on) p.sheet else p.ink,
        modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (on) p.ink else Color.Transparent)
            .border(1.dp, p.ink.copy(alpha = if (on) 1f else 0.3f), RoundedCornerShape(3.dp))
            .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 7.dp))
}

/** Vertical −10…+10 fader: hairline track with ticks, an inked bar from zero, square knob. */
@Composable
fun VerticalFader(value: Float, modifier: Modifier = Modifier, onChange: (Float) -> Unit, onCommit: () -> Unit) {
    val p = ink
    val current = androidx.compose.runtime.rememberUpdatedState(value)
    Canvas(modifier.pointerInput(Unit) {
        val knob = 16.dp.toPx()
        fun v(y: Float) = (10 - (y - knob / 2) / (size.height - knob) * 20).coerceIn(-10f, 10f).roundToInt().toFloat()
        fun knobY() = knob / 2 + (size.height - knob) * (10 - current.value) / 20
        dragHandle(grab = 24.dp.toPx(),
            handleAt = { pos -> if (kotlin.math.abs(pos.y - knobY()) < 24.dp.toPx()) 0 else null },
            onMove = { _, pos -> onChange(v(pos.y)) }, onEnd = { onCommit() })
    }) {
        val knob = 16.dp.toPx(); val travel = size.height - knob; val mid = size.width / 2
        fun y(v: Float) = knob / 2 + travel * (10 - v) / 20
        for (i in 0..10) {
            val tv = 10f - i * 2; val major = tv == 0f || kotlin.math.abs(tv) == 10f
            val half = (if (major) 8.dp else 4.dp).toPx()
            drawLine(p.ink.copy(alpha = if (major) 0.6f else 0.25f), Offset(mid - half, y(tv)), Offset(mid + half, y(tv)), density * 0.75f)
        }
        drawLine(p.ink.copy(alpha = 0.35f), Offset(mid, knob / 2), Offset(mid, size.height - knob / 2), density)
        drawLine(p.ink, Offset(mid, y(0f)), Offset(mid, y(value)), 3 * density)
        val kw = 22.dp.toPx()
        drawRoundRect(p.sheet, Offset(mid - kw / 2, y(value) - knob / 2), Size(kw, knob), CornerRadius(2 * density))
        drawRoundRect(p.ink, Offset(mid - kw / 2, y(value) - knob / 2), Size(kw, knob), CornerRadius(2 * density), style = Stroke(1.5f * density))
    }
}

@Composable
fun HorizontalFader(value: Float, range: ClosedFloatingPointRange<Float>, onChange: (Float) -> Unit, onCommit: () -> Unit) {
    val p = ink
    Canvas(Modifier.fillMaxWidth().height(30.dp).pointerInput(Unit) {
        val knob = 16.dp.toPx()
        fun v(x: Float) = (range.start + (x - knob / 2) / (size.width - knob) * (range.endInclusive - range.start))
            .coerceIn(range.start, range.endInclusive).roundToInt().toFloat()
        // Horizontal: a vertical page scroll rarely starts sideways, so any touch on the track works.
        dragHandle(grab = 0f, handleAt = { 0 }, onMove = { _, pos -> onChange(v(pos.x)) }, onEnd = { onCommit() })
    }) {
        val knob = 16.dp.toPx(); val travel = size.width - knob; val midY = size.height / 2
        val x = knob / 2 + travel * (value - range.start) / (range.endInclusive - range.start)
        drawLine(p.ink.copy(alpha = 0.3f), Offset(knob / 2, midY), Offset(size.width - knob / 2, midY), density)
        drawLine(p.ink, Offset(knob / 2, midY), Offset(x, midY), 3 * density)
        drawRoundRect(p.sheet, Offset(x - knob / 2, midY - 11.dp.toPx()), Size(knob, 22.dp.toPx()), CornerRadius(2 * density))
        drawRoundRect(p.ink, Offset(x - knob / 2, midY - 11.dp.toPx()), Size(knob, 22.dp.toPx()), CornerRadius(2 * density), style = Stroke(1.5f * density))
    }
}

// ---- Devices ----

@Composable
fun DevicesPage(ui: HeadphoneController.Ui, hp: HeadphoneController) {
    val p = ink
    val context = LocalContext.current
    PageHeader("Devices", "Phones and computers paired with your headphones")
    Card(null) {
        val devices = ui.state.devices ?: emptyList()
        if (devices.isEmpty()) Text("No paired devices reported yet.", style = serif(13, FontWeight.Normal, italic = true), color = p.secondary)
        devices.forEachIndexed { i, d ->
            val playing = d.address == ui.state.playbackDevice
            // Android hides its own Bluetooth address, so recognise this phone by its name.
            val thisPhone = d.name == Settings.Global.getString(context.contentResolver, "device_name")
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(d.name, style = serif(15), color = p.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(if (playing) "Connected · playing audio" else if (d.connected) "Connected" else "Not connected",
                            style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
                    }
                    if (playing) Row(verticalAlignment = Alignment.CenterVertically) { Dot(p.accent); Spacer(Modifier.width(6.dp)); Label("Playing") }
                }
                if (!playing) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (d.connected) {
                        PrintButton("Play here") { hp.playFrom(d) }
                        if (!thisPhone) PrintButton("Disconnect") { hp.disconnectDevice(d) }
                    } else PrintButton("Connect") { hp.connectDevice(d) }
                }
            }
            if (i < devices.size - 1) Rule()
        }
    }
    PrintButton("Refresh") { hp.refreshDevices() }
}

// ---- Settings ----

@Composable
fun SettingsPage(ui: HeadphoneController.Ui, hp: HeadphoneController, nowPlaying: NowPlaying, log: ListeningLog) {
    val p = ink
    val s = ui.state
    val context = LocalContext.current
    var confirmClear by remember { mutableStateOf(false) }
    PageHeader("Settings", "Headphone and app preferences")
    Card("Audio") {
        s.dseeUpsampling?.let { SettingRow("DSEE upsampling", "Restores detail lost in compressed music") { PrintToggle(it) { v -> hp.setDsee(v) } } }
        s.preferSoundQuality?.let { SettingRow("Prioritize sound quality", "Prefer LDAC over a more stable connection") { PrintToggle(it) { v -> hp.setPreferSoundQuality(v) } } }
    }
    Card("Connection") {
        s.multipoint?.let { SettingRow("Connect to 2 devices", "Stay connected to a phone and a computer at once") { PrintToggle(it) { v -> hp.setMultipoint(v) } } }
        s.captureVoiceDuringCall?.let { SettingRow("Capture voice during calls", "Picks up your voice more clearly") { PrintToggle(it) { v -> hp.setCaptureVoice(v) } } }
    }
    Card("Headphones") {
        s.voiceAssistant?.let { current ->
            Text("Voice assistant", style = serif(15), color = p.ink)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                VoiceAssistant.entries.forEach { va ->
                    val on = va == current
                    Text(va.label.substringBefore(" "), style = serif(12), color = if (on) p.sheet else p.ink,
                        modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(if (on) p.ink else Color.Transparent)
                            .border(1.dp, p.ink.copy(alpha = if (on) 1f else 0.3f), RoundedCornerShape(3.dp))
                            .clickable { hp.setVoiceAssistant(va) }.padding(horizontal = 9.dp, vertical = 6.dp))
                }
            }
        }
        s.pauseWhenTakenOff?.let { SettingRow("Pause when taken off") { PrintToggle(it) { v -> hp.setPauseWhenTakenOff(v) } } }
        s.voiceGuidance?.let { SettingRow("Voice guidance", "Spoken prompts for power, modes and battery") { PrintToggle(it) { v -> hp.setVoiceGuidance(v) } } }
        val vol = s.voiceGuidanceVolume
        if (vol != null && s.voiceGuidance == true) SettingRow("Guidance volume") {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                PrintButton("−", enabled = vol > -2) { hp.setVoiceGuidanceVolume(vol - 1) }
                Text("%+d".format(vol), style = serif(15), color = p.ink)
                PrintButton("+", enabled = vol < 2) { hp.setVoiceGuidanceVolume(vol + 1) }
            }
        }
    }
    Card("App") {
        SettingRow("Now playing access", if (nowPlaying.accessGranted()) "On: track details and listening history" else "Off") {
            PrintButton("Open") { context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) }
        }
        SettingRow("Listening history", "Kept on this phone for 120 days") { PrintButton("Clear") { confirmClear = true } }
    }
    if (confirmClear) ConfirmDialog("Clear your listening history?", "This can't be undone.", "Clear",
        onConfirm = { log.clear() }, onDismiss = { confirmClear = false })
}

// ---- Listening ----

@Composable
fun ListeningPage(log: ListeningLog) {
    val p = ink
    val sessions by log.sessions.collectAsState()
    val volume by log.volume.collectAsState()
    var days by remember { mutableIntStateOf(7) }
    val stats = remember(sessions, volume, days) { ListeningStats(sessions, volume, days) }
    val dayShort = SimpleDateFormat(if (days <= 7) "EEEEE" else "d", Locale.getDefault())
    val dayLong = SimpleDateFormat("EEEE d MMM", Locale.getDefault())

    PageHeader("Listening", "What you played and how loud, over the last $days days")
    Row(horizontalArrangement = Arrangement.spacedBy(0.dp), modifier = Modifier.border(1.dp, p.ink, RoundedCornerShape(3.dp)).clip(RoundedCornerShape(3.dp))) {
        listOf(7, 30).forEach { d ->
            Label("$d days", color = if (d == days) p.sheet else p.ink,
                modifier = Modifier.background(if (d == days) p.ink else Color.Transparent).clickable { days = d }.padding(horizontal = 12.dp, vertical = 6.dp))
        }
    }

    if (stats.totalSeconds < 1) {
        Card("Nothing recorded yet") {
            Text("With notification access on, Connect Head notes what plays in YouTube, Spotify and other apps, and the media volume while it plays through your headphones.",
                style = serif(14, FontWeight.Normal, italic = true), color = p.secondary)
        }
        return
    }

    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        StatPanel("Listening", durationText(stats.totalSeconds), "${durationText(stats.totalSeconds / days)} a day", Modifier.weight(1f))
        StatPanel("Avg volume", stats.averageVolume?.let { "${(it * 100).roundToInt()}%" } ?: "—",
            if (stats.averageVolume == null) "On headphones only" else "${durationText(stats.loudSeconds)} above 75%", Modifier.weight(1f))
    }
    stats.topArtists.firstOrNull()?.let { StatPanel("Most played", it.name, durationText(it.seconds), Modifier.fillMaxWidth()) }

    Card("Listening time by day") {
        InkBars(stats.perDay.map { it.second }, stats.perDay.map { dayShort.format(Date(it.first)) },
            { i, v -> "${dayLong.format(Date(stats.perDay[i].first))}: ${durationText(v)}" }, Modifier.fillMaxWidth().height(150.dp))
    }
    Card("When you listen") {
        fun hour(h: Int) = if (h == 0) "12a" else if (h < 12) "${h}a" else if (h == 12) "12p" else "${h - 12}p"
        InkBars(stats.perHour, (0 until 24).map { if (it % 6 == 0) hour(it) else "" },
            { i, v -> "${hour(i)}–${hour((i + 1) % 24)}: ${durationText(v)}" }, Modifier.fillMaxWidth().height(110.dp))
    }
    Card("Top artists") { Ranked(stats.topArtists.take(5)) }
    Card("Top tracks") { Ranked(stats.topTracks.take(5)) }
    Card("Where it played") { Ranked(stats.apps, share = true) }
    Card("Volume while listening") {
        if (stats.perDayVolume.all { it == null }) Text("Recorded while your phone plays through the headphones. Nothing yet in this period.",
            style = serif(13, FontWeight.Normal, italic = true), color = p.secondary)
        else {
            InkLine(stats.perDayVolume, stats.perDay.map { dayShort.format(Date(it.first)) }, 0.75f,
                { i, v -> "${dayLong.format(Date(stats.perDay[i].first))}: ${(v * 100).roundToInt()}% average" }, Modifier.fillMaxWidth().height(140.dp))
            Text("A common guideline for long sessions is the 60/60 rule: under 60% volume, for about 60 minutes at a time.",
                style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
        }
    }
}

@Composable
private fun StatPanel(label: String, value: String, detail: String, modifier: Modifier) {
    val p = ink
    Column(modifier.printPanel().padding(14.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Label(label)
        Text(value, style = serif(26, FontWeight.Normal), color = p.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(detail, style = serif(12, FontWeight.Normal, italic = true), color = p.secondary, maxLines = 1)
    }
}

@Composable
private fun Ranked(rows: List<ListeningStats.Row>, share: Boolean = false) {
    val p = ink
    val top = rows.firstOrNull()?.seconds ?: 1.0
    val total = rows.sumOf { it.seconds }.coerceAtLeast(1.0)
    rows.forEach { row ->
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(row.name, style = serif(14), color = p.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (row.detail.isNotEmpty()) Text("  ${row.detail}", style = serif(12, FontWeight.Normal, italic = true), color = p.secondary, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Spacer(Modifier.weight(0.01f))
                Text(if (share) "${(row.seconds / total * 100).roundToInt()}%  ·  ${durationText(row.seconds)}" else durationText(row.seconds),
                    style = serif(12, FontWeight.Normal), color = p.ink)
            }
            Canvas(Modifier.fillMaxWidth().height(4.dp)) {
                val y = size.height / 2
                drawLine(p.ink.copy(alpha = 0.12f), Offset(0f, y), Offset(size.width, y), density)
                drawLine(p.ink, Offset(0f, y), Offset(size.width * (row.seconds / top).toFloat(), y), 3 * density)
            }
        }
    }
}

/** Single-series bar chart in ink; tap a bar for its value. */
@Composable
private fun InkBars(values: List<Double>, labels: List<String>, readout: (Int, Double) -> String, modifier: Modifier) {
    val p = ink
    var selected by remember(values) { mutableIntStateOf(-1) }
    val top = (values.maxOrNull() ?: 0.0).coerceAtLeast(1.0)
    Column(modifier) {
        Text(if (selected >= 0) readout(selected, values[selected]) else "Tap a bar for details", style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
        Spacer(Modifier.height(6.dp))
        Canvas(Modifier.weight(1f).fillMaxWidth().pointerInput(values) {
            detectTapGestures { pos -> selected = (pos.x / size.width * values.size).toInt().coerceIn(0, values.size - 1) }
        }) {
            val slot = size.width / values.size
            val bar = minOf(slot * 0.7f, 30.dp.toPx())
            drawLine(p.ink.copy(alpha = 0.5f), Offset(0f, size.height), Offset(size.width, size.height), 0.75f * density)
            values.forEachIndexed { i, v ->
                if (v <= 0) return@forEachIndexed
                val h = maxOf(size.height * (v / top).toFloat(), 2 * density)
                drawRoundRect(p.ink.copy(alpha = if (selected < 0 || selected == i) 1f else 0.35f),
                    Offset(i * slot + (slot - bar) / 2, size.height - h), Size(bar, h), CornerRadius(2 * density))
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
            labels.forEach { Text(it, style = labelStyle.copy(fontSize = 9.sp, letterSpacing = 0.sp), color = p.secondary, textAlign = TextAlign.Center, modifier = Modifier.weight(1f), maxLines = 1) }
        }
    }
}

/** Single-series line over 0…1 with a dashed reference line; tap a point for its value. */
@Composable
private fun InkLine(values: List<Double?>, labels: List<String>, reference: Float, readout: (Int, Double) -> String, modifier: Modifier) {
    val p = ink
    var selected by remember(values) { mutableIntStateOf(-1) }
    Column(modifier) {
        Text(if (selected >= 0 && values[selected] != null) readout(selected, values[selected]!!) else "Tap a day for details",
            style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
        Spacer(Modifier.height(6.dp))
        Canvas(Modifier.weight(1f).fillMaxWidth().pointerInput(values) {
            detectTapGestures { pos ->
                val step = if (values.size > 1) size.width / (values.size - 1f) else 1f
                selected = (pos.x / step).roundToInt().coerceIn(0, values.size - 1)
            }
        }) {
            val w = size.width; val h = size.height
            val step = if (values.size > 1) w / (values.size - 1) else 0f
            fun pt(i: Int, v: Double) = Offset(i * step, h - v.toFloat() * h)
            drawLine(p.ink.copy(alpha = 0.5f), Offset(0f, h), Offset(w, h), 0.75f * density)
            drawLine(p.accent.copy(alpha = 0.8f), Offset(0f, h - reference * h), Offset(w, h - reference * h), density,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f)))
            val path = Path(); var drawing = false
            values.forEachIndexed { i, v ->
                if (v == null) { drawing = false; return@forEachIndexed }
                val o = pt(i, v); if (drawing) path.lineTo(o.x, o.y) else path.moveTo(o.x, o.y); drawing = true
            }
            drawPath(path, p.ink, style = Stroke(2 * density, cap = StrokeCap.Round))
            values.forEachIndexed { i, v ->
                if (v == null) return@forEachIndexed
                val r = (if (i == selected) 5.5f else 4f) * density
                drawCircle(p.sheet, r, pt(i, v)); drawCircle(p.ink, r, pt(i, v), style = Stroke(2 * density))
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
            labels.forEach { Text(it, style = labelStyle.copy(fontSize = 9.sp, letterSpacing = 0.sp), color = p.secondary, textAlign = TextAlign.Center, modifier = Modifier.weight(1f), maxLines = 1) }
        }
    }
}

