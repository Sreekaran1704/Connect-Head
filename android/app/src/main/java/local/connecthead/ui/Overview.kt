package local.connecthead.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import local.connecthead.bt.HeadphoneController
import local.connecthead.bt.HeadphoneController.Status
import local.connecthead.media.ListeningLog
import local.connecthead.media.NowPlaying
import local.connecthead.media.RemoteNowPlaying
import local.connecthead.protocol.EqPreset
import local.connecthead.protocol.NoiseMode
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin


@Composable
fun ConnectHeadApp(hp: HeadphoneController, nowPlaying: NowPlaying, remote: RemoteNowPlaying, log: ListeningLog) {
    val ui by hp.ui.collectAsState()
    var page by rememberSaveable { mutableStateOf(Page.OVERVIEW) }
    // Kept outside the transition so a brief reconnect doesn't throw the reader back to the top;
    // choosing a section still opens it at the top.
    val scrolls = remember { mutableMapOf<Page, ScrollState>() }
    val go = { to: Page -> scrolls.remove(to); page = to }
    var moreOpen by remember { mutableStateOf(false) }
    PaperScreen {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).statusBarsPadding()) {
                AnimatedContent(ui.ready, transitionSpec = { fadeIn(tween(450)) togetherWith fadeOut(tween(300)) }, label = "ready") { ready ->
                    // The masthead scrolls away with the page, as on the site; the tab bar stays.
                    val scroll = scrolls.getOrPut(page) { ScrollState(0) }
                    Column(Modifier.fillMaxSize().verticalScroll(scroll)) {
                        Masthead(ui, hp)
                        if (!ready) ConnectingScreen(ui, hp)
                        else Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                            when (page) {
                                Page.OVERVIEW -> OverviewPage(ui, hp, nowPlaying, remote) { go(it) }
                                Page.SOUND -> SoundPage(ui, hp)
                                Page.EQUALIZER -> EqualizerPage(ui, hp)
                                Page.LISTENING -> ListeningPage(log)
                                Page.DEVICES -> DevicesPage(ui, hp)
                                Page.SETTINGS -> SettingsPage(ui, hp, nowPlaying, log)
                            }
                            Spacer(Modifier.height(12.dp))
                        }
                    }
                }
                MorePanel(moreOpen, page, onSelect = { go(it); moreOpen = false }, onDismiss = { moreOpen = false })
            }
            if (ui.ready) TabBar(page, moreOpen, onSelect = { go(it); moreOpen = false }, onMore = { moreOpen = !moreOpen })
        }
    }
}

// ---- Masthead & sections ----

@Composable
private fun Masthead(ui: HeadphoneController.Ui, hp: HeadphoneController) {
    val p = ink
    var menu by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column {
                Wordmark(Modifier.width(196.dp).padding(bottom = 5.dp))
                Text("The ${ui.deviceName ?: "Headphones"} Edition".uppercase(), style = labelStyle.copy(letterSpacing = 1.8.sp), color = p.secondary)
            }
            Spacer(Modifier.weight(1f))
            Box {
                Row(Modifier.clip(RoundedCornerShape(3.dp)).clickable { menu = true }.padding(horizontal = 6.dp, vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Dot(if (ui.status == Status.CONNECTED) p.accent else p.ink.copy(alpha = 0.3f))
                    Label(statusText(ui.status))
                    Text("▾", style = serif(10), color = p.ink)
                }
                DropdownMenu(menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Reconnect") }, onClick = { menu = false; hp.disconnect(); hp.connect() })
                    if (ui.status == Status.CONNECTED) DropdownMenuItem(text = { Text("Disconnect") }, onClick = { menu = false; hp.disconnect() })
                    hp.pairedDevices().filter { it.address != ui.deviceAddress }.forEach { d ->
                        @Suppress("MissingPermission")
                        DropdownMenuItem(text = { Text("Switch to ${d.name}") }, onClick = { menu = false; hp.select(d) })
                    }
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Rule(double = true)
    }
}

private fun statusText(s: Status) = when (s) {
    Status.CONNECTED -> "Connected"; Status.CONNECTING -> "Connecting"; Status.DISCONNECTED -> "Off"
    Status.ELSEWHERE -> "On your Mac"
    Status.NO_DEVICE -> "Not paired"; Status.NO_PERMISSION -> "No access"; Status.FAILED -> "Not connected"
}

// ---- Not connected ----

@Composable
private fun ConnectingScreen(ui: HeadphoneController.Ui, hp: HeadphoneController) {
    val p = ink
    val context = LocalContext.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 72.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        HeadphoneIllustration(Modifier.size(150.dp, 160.dp))
        Spacer(Modifier.height(18.dp))
        val (title, body) = when (ui.status) {
            Status.CONNECTING, Status.CONNECTED -> "Connecting…" to "Talking to ${ui.deviceName ?: "your headphones"}."
            Status.ELSEWHERE -> "In use on your Mac" to "Connect Head on your Mac has the headphone controls. Take them here, or they come back when you open this app."
            Status.NO_DEVICE -> "No Sony headphones paired" to "Pair them in Bluetooth settings, then come back."
            Status.NO_PERMISSION -> "Bluetooth access needed" to "Allow Nearby devices so Connect Head can talk to your headphones."
            Status.FAILED -> "Couldn't connect" to (ui.message ?: "Try again.")
            else -> "Headphones are off" to "Press and hold the power button for about 2 seconds. Connect Head reconnects as soon as they're on."
        }
        Text(title, style = serif(24), color = p.ink, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text(body, style = serif(14, FontWeight.Normal, italic = true), color = p.secondary, textAlign = TextAlign.Center)
        Spacer(Modifier.height(18.dp))
        if (ui.status != Status.CONNECTING && ui.status != Status.CONNECTED) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PrintButton(if (ui.status == Status.ELSEWHERE) "Use here" else "Connect", filled = true) { hp.connect() }
            if (ui.status == Status.NO_DEVICE || ui.status == Status.NO_PERMISSION)
                PrintButton("Bluetooth settings") { context.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)) }
        }
    }
}

// ---- Overview ----

@Composable
private fun OverviewPage(ui: HeadphoneController.Ui, hp: HeadphoneController, nowPlaying: NowPlaying, remote: RemoteNowPlaying, go: (Page) -> Unit) {
    BatteryPanel(ui, hp)
    NowPlayingPanel(ui, nowPlaying, remote)
    Card("Sound mode") { ModeButtons(ui.state.noiseMode) { hp.setNoiseMode(it) } }
    Card("Devices") { DeviceRows(ui, compact = true); PrintButton("Manage devices") { go(Page.DEVICES) } }
    Card("Equalizer") {
        var picking by remember { mutableStateOf(false) }
        Row(Modifier.clip(RoundedCornerShape(3.dp)).clickable { picking = !picking }.padding(vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(ui.state.eqPreset?.label ?: "Unknown", style = serif(19), color = ink.ink)
            Text(if (picking) "  ▴" else "  ▾", style = serif(14), color = ink.secondary)
        }
        AnimatedVisibility(picking) {
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                EqPreset.entries.forEach { preset ->
                    PresetChip(preset, preset == ui.state.eqPreset) { hp.setEqPreset(preset); picking = false }
                }
            }
        }
        EditableEqCurve(ui.state.eqBands, Modifier.fillMaxWidth().height(110.dp)) { i, v -> hp.setEqBand(i + 1, v) }
        Text("Press and hold a point, then drag to shape the sound.", style = serif(12, FontWeight.Normal, italic = true), color = ink.secondary)
    }
}

@Composable
private fun BatteryPanel(ui: HeadphoneController.Ui, hp: HeadphoneController) {
    val p = ink
    val level = ui.state.battery ?: 0
    val low = level <= 20 && !ui.state.charging
    var shown by remember { mutableStateOf(0f) }
    LaunchedEffect(level) { shown = level.toFloat() }
    val animated by animateFloatAsState(shown, tween(900), label = "battery")
    var confirm by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth().printPanel().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(132.dp), contentAlignment = Alignment.Center) {
                TickDial(animated, if (low) p.accent else p.ink, Modifier.fillMaxSize())
                HeadphoneIllustration(Modifier.size(74.dp, 78.dp))
            }
            Spacer(Modifier.width(18.dp))
            Column(Modifier.weight(1f)) {
                Label(if (ui.state.charging) "Charging" else "Battery")
                Text("$level%", style = serif(46, FontWeight.Normal), color = if (low) p.accent else p.ink)
                Rule(Modifier.padding(vertical = 6.dp))
                Text(ui.deviceName ?: "Headphones", style = serif(17), color = p.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(listOfNotNull(ui.state.codec?.label, ui.state.firmware?.let { "FW $it" }, ui.state.noiseMode?.label).joinToString("  ·  "),
                    style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
            }
        }
        Spacer(Modifier.height(12.dp))
        Row { Spacer(Modifier.weight(1f)); PrintButton("Power off") { confirm = true } }
    }
    if (confirm) ConfirmDialog("Turn off ${ui.deviceName ?: "the headphones"}?",
        "To turn them back on, press the power button on the headphones. Connect Head reconnects on its own.",
        "Power off", onConfirm = { hp.powerOff() }, onDismiss = { confirm = false })
}

/** Sixty ticks round a hairline circle, like a watch bezel; ticks up to the level are inked. */
@Composable
fun TickDial(level: Float, fill: Color, modifier: Modifier = Modifier) {
    val p = ink
    Canvas(modifier) {
        val c = center
        val r = size.minDimension / 2
        val lit = (level.coerceIn(0f, 100f) / 100f * 60).roundToInt()
        for (i in 0 until 60) {
            val a = i / 60.0 * 2 * Math.PI - Math.PI / 2
            val major = i % 5 == 0
            val outer = r - 1; val inner = r - (if (major) 13.dp.toPx() else 7.dp.toPx())
            drawLine(if (i < lit) fill else p.ink.copy(alpha = 0.16f),
                Offset(c.x + cos(a).toFloat() * inner, c.y + sin(a).toFloat() * inner),
                Offset(c.x + cos(a).toFloat() * outer, c.y + sin(a).toFloat() * outer),
                (if (major) 2.4f else 1.6f) * density)
        }
        drawCircle(p.ink.copy(alpha = 0.25f), r - 18.dp.toPx(), c, style = Stroke(0.75f * density))
    }
}

/** One thing to show in the Now Playing panel, from this phone or from the Mac. */
private class Shown(
    val title: String, val subtitle: String, val source: String, val playing: Boolean,
    val positionMs: Long, val durationMs: Long, val art: android.graphics.Bitmap?, val controllable: Boolean,
    val playPause: () -> Unit, val next: () -> Unit, val previous: () -> Unit,
)

@Composable
private fun NowPlayingPanel(ui: HeadphoneController.Ui, nowPlaying: NowPlaying, remote: RemoteNowPlaying) {
    val p = ink
    val local by nowPlaying.track.collectAsState()
    val mac by remote.track.collectAsState()
    val access by nowPlaying.hasAccess.collectAsState()
    val context = LocalContext.current

    val fromPhone = local?.let { t ->
        Shown(t.title, listOf(t.artist, t.album).filter { it.isNotEmpty() }.joinToString(" — "), "${t.app} · this phone",
            t.playing, t.position, t.duration, t.art, true, nowPlaying::playPause, nowPlaying::next, nowPlaying::previous)
    }
    val fromMac = mac?.let { t ->
        Shown(t.title, listOf(t.artist, t.album).filter { it.isNotEmpty() }.joinToString(" — "), "${t.service} · ${t.device}",
            t.playing, (t.position * 1000).toLong(), (t.duration * 1000).toLong(), t.art, t.controllable,
            { remote.control("playpause") }, { remote.control("next") }, { remote.control("previous") })
    }
    // Whatever is actually playing wins; otherwise a paused player that can be resumed.
    val shown = listOfNotNull(fromPhone, fromMac).let { all -> all.firstOrNull { it.playing } ?: all.firstOrNull() }
    // The headphones say audio is coming from another device we can't read (no Connect Head there).
    val elsewhere = ui.state.devices?.firstOrNull { it.address == ui.state.playbackDevice }
        ?.takeIf { shown == null && it.name != android.provider.Settings.Global.getString(context.contentResolver, "device_name") }

    Card("Now playing") {
        when {
            shown != null -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ArtBox(shown.art)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(shown.title, style = serif(17), color = p.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (shown.subtitle.isNotEmpty()) Text(shown.subtitle, style = serif(12, FontWeight.Normal, italic = true),
                            color = p.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Label(shown.source, color = p.secondary, modifier = Modifier.padding(top = 2.dp))
                    }
                }
                if (shown.controllable) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(clock(shown.positionMs), style = serif(11, FontWeight.Normal), color = p.secondary)
                        val frac = if (shown.durationMs > 0) (shown.positionMs.toFloat() / shown.durationMs).coerceIn(0f, 1f) else 0f
                        Box(Modifier.weight(1f).height(8.dp)) {
                            Canvas(Modifier.fillMaxSize()) {
                                val y = size.height / 2
                                drawLine(p.ink.copy(alpha = 0.2f), Offset(0f, y), Offset(size.width, y), 1f * density)
                                drawLine(p.ink, Offset(0f, y), Offset(size.width * frac, y), 2f * density)
                            }
                        }
                        Text(if (shown.durationMs > 0) clock(shown.durationMs) else "—", style = serif(11, FontWeight.Normal), color = p.secondary)
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                        PrintButton("⏮") { shown.previous() }
                        Spacer(Modifier.width(10.dp))
                        PrintButton(if (shown.playing) "Pause" else "Play", filled = true) { shown.playPause() }
                        Spacer(Modifier.width(10.dp))
                        PrintButton("⏭") { shown.next() }
                    }
                } else Text("Turn on “Allow JavaScript from Apple Events” in the Mac’s browser to see progress and control it from here.",
                    style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
            }
            elsewhere != null -> Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(56.dp).border(1.dp, p.ink.copy(alpha = 0.35f), RoundedCornerShape(3.dp)), contentAlignment = Alignment.Center) {
                    DeviceIcon(elsewhere.isPhone, Modifier.size(28.dp))
                }
                Spacer(Modifier.width(14.dp))
                Column {
                    Text("Playing on ${elsewhere.name}", style = serif(17), color = p.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text("Open Connect Head there to see the track here.", style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
                }
            }
            !access -> {
                Text("See what's playing", style = serif(17), color = p.ink)
                Text("Give Connect Head notification access so it can show the song playing in YouTube, Spotify or any app, and keep your listening history.",
                    style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
                PrintButton("Allow access", filled = true) { context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) }
            }
            else -> Row(verticalAlignment = Alignment.CenterVertically) {
                ArtBox(null)
                Spacer(Modifier.width(14.dp))
                Column {
                    Text("Nothing playing", style = serif(17), color = p.ink)
                    Text("Start something on this phone or your Mac and it will appear here.", style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
                }
            }
        }
    }
}

@Composable
private fun ArtBox(art: android.graphics.Bitmap?) {
    val p = ink
    Box(Modifier.size(56.dp).clip(RoundedCornerShape(3.dp)).border(1.dp, p.ink, RoundedCornerShape(3.dp)), contentAlignment = Alignment.Center) {
        if (art != null) Image(art.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else Text("♪", style = serif(20), color = p.secondary)
    }
}

private fun clock(ms: Long): String { val s = (ms / 1000).toInt(); return "%d:%02d".format(s / 60, s % 60) }

@Composable
fun ModeButtons(selected: NoiseMode?, onSelect: (NoiseMode) -> Unit) {
    val p = ink
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NoiseMode.entries.forEach { mode ->
            val on = mode == selected
            Column(Modifier.weight(1f).height(82.dp)
                .background(if (on) p.ink else Color.Transparent, RoundedCornerShape(3.dp))
                .border(1.dp, p.ink.copy(alpha = if (on) 1f else 0.35f), RoundedCornerShape(3.dp))
                .clickable { onSelect(mode) }.padding(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Canvas(Modifier.size(20.dp)) { modeIcon(mode, if (on) p.sheet else p.ink) }
                Spacer(Modifier.height(6.dp))
                Text(mode.label, style = serif(13), color = if (on) p.sheet else p.ink, textAlign = TextAlign.Center, maxLines = 2)
            }
        }
    }
}

/** Small line icons for the sound modes: closed ear cup, open sound waves, plain speaker. */
private fun androidx.compose.ui.graphics.drawscope.DrawScope.modeIcon(mode: NoiseMode, c: Color) {
    val u = size.minDimension / 24f
    val stroke = Stroke(2 * u, cap = androidx.compose.ui.graphics.StrokeCap.Round)
    when (mode) {
        NoiseMode.NOISE_CANCELLING -> {
            drawArc(c, 180f, 180f, false, Offset(3 * u, 4 * u), androidx.compose.ui.geometry.Size(18 * u, 18 * u), style = stroke)
            drawRoundRect(c, Offset(3 * u, 13 * u), androidx.compose.ui.geometry.Size(5 * u, 8 * u), androidx.compose.ui.geometry.CornerRadius(2 * u))
            drawRoundRect(c, Offset(16 * u, 13 * u), androidx.compose.ui.geometry.Size(5 * u, 8 * u), androidx.compose.ui.geometry.CornerRadius(2 * u))
        }
        NoiseMode.AMBIENT -> {
            drawCircle(c, 2 * u, Offset(12 * u, 12 * u))
            for (r in listOf(5f, 9f)) {
                drawArc(c, -50f, 100f, false, Offset((12 - r) * u, (12 - r) * u), androidx.compose.ui.geometry.Size(2 * r * u, 2 * r * u), style = stroke)
                drawArc(c, 130f, 100f, false, Offset((12 - r) * u, (12 - r) * u), androidx.compose.ui.geometry.Size(2 * r * u, 2 * r * u), style = stroke)
            }
        }
        NoiseMode.OFF -> {
            val speaker = Path().apply { moveTo(4 * u, 9 * u); lineTo(8 * u, 9 * u); lineTo(13 * u, 5 * u); lineTo(13 * u, 19 * u); lineTo(8 * u, 15 * u); lineTo(4 * u, 15 * u); close() }
            drawPath(speaker, c, style = Stroke(2 * u, join = androidx.compose.ui.graphics.StrokeJoin.Round))
            drawArc(c, -45f, 90f, false, Offset(11 * u, 8 * u), androidx.compose.ui.geometry.Size(8 * u, 8 * u), style = stroke)
        }
    }
}

@Composable
fun DeviceRows(ui: HeadphoneController.Ui, compact: Boolean) {
    val p = ink
    val devices = ui.state.devices?.filter { !compact || it.connected } ?: emptyList()
    if (devices.isEmpty()) Text("No devices connected", style = serif(13, FontWeight.Normal, italic = true), color = p.secondary)
    devices.forEachIndexed { i, d ->
        val playing = d.address == ui.state.playbackDevice
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(34.dp).border(1.dp, p.ink.copy(alpha = 0.35f), RoundedCornerShape(3.dp)), contentAlignment = Alignment.Center) {
                DeviceIcon(d.isPhone, Modifier.size(22.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(d.name, style = serif(15), color = p.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(if (playing) "Now playing" else if (d.connected) "Connected" else "Not connected",
                    style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
            }
            if (playing) Dot(p.accent)
        }
        if (i < devices.size - 1) Rule(Modifier.padding(vertical = 2.dp))
    }
}

/** The EQ curve with its five band points draggable up and down; sends on release. */
@Composable
fun EditableEqCurve(bands: List<Int>, modifier: Modifier = Modifier, onCommit: (Int, Int) -> Unit) {
    val p = ink
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
    val drafts = remember { mutableStateMapOf<Int, Int>() }
    var active by remember { mutableIntStateOf(-1) }
    val shown = bands.mapIndexed { i, v -> drafts[i] ?: v }
    Column(modifier) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            Canvas(Modifier.fillMaxSize().pointerInput(bands) {
                val w = size.width.toFloat(); val h = size.height.toFloat()
                fun point(i: Int) = Offset(w * (i + 0.5f) / bands.size, h / 2 - (drafts[i] ?: bands[i]) / 10f * (h / 2 - 6))
                // Press and hold anywhere over a band, then drag; a quick swipe just scrolls the page.
                dragHandle(
                    grab = 0f,
                    holdMillis = 220,
                    onGrab = { haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress) },
                    handleAt = { pos -> bands.indices.minByOrNull { kotlin.math.abs(point(it).x - pos.x) } },
                    onMove = { i, pos ->
                        active = i
                        drafts[i] = ((h / 2 - pos.y) / (h / 2 - 6) * 10).roundToInt().coerceIn(-10, 10)
                    },
                    onEnd = { i -> drafts.remove(i)?.let { onCommit(i, it) }; active = -1 },
                )
            }) {
                val w = size.width; val h = size.height
                listOf(0f, 0.5f, 1f).forEach { f ->
                    drawLine(p.ink.copy(alpha = 0.1f), Offset(0f, h * f), Offset(w, h * f), 1f,
                        pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(8f, 8f)))
                }
                val pts = shown.mapIndexed { i, v -> Offset(w * (i + 0.5f) / shown.size, h / 2 - v / 10f * (h / 2 - 6)) }
                val curve = Path().apply {
                    moveTo(0f, pts.first().y); lineTo(pts.first().x, pts.first().y)
                    for (i in 0 until pts.size - 1) {
                        val a = pts[i]; val b = pts[i + 1]; val mx = (a.x + b.x) / 2
                        cubicTo(mx, a.y, mx, b.y, b.x, b.y)
                    }
                    lineTo(w, pts.last().y)
                }
                val fill = Path().apply { addPath(curve); lineTo(w, h); lineTo(0f, h); close() }
                drawPath(fill, p.ink.copy(alpha = 0.06f))
                drawPath(curve, p.ink, style = Stroke(1.5f * density))
                pts.forEachIndexed { i, pt ->
                    drawCircle(if (i == active) p.ink else p.sheet, 4.5f * density, pt)
                    drawCircle(p.ink, 4.5f * density, pt, style = Stroke(1.5f * density))
                }
            }
            if (active >= 0) androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
                // The value rides above the band being dragged.
                val x = maxWidth * ((active + 0.5f) / shown.size) - 16.dp
                Text("%+d".format(shown[active]), style = serif(12), color = p.sheet, textAlign = TextAlign.Center,
                    modifier = Modifier.padding(start = x.coerceIn(0.dp, maxWidth - 32.dp)).width(32.dp)
                        .background(p.ink, RoundedCornerShape(2.dp)).padding(vertical = 1.dp))
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
            listOf("400", "1k", "2.5k", "6.3k", "16k").forEach {
                Text(it, style = labelStyle.copy(fontSize = 9.sp), color = p.secondary, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun ConfirmDialog(title: String, message: String, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val p = ink
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        Column(Modifier.printPanel().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = serif(19), color = p.ink)
            Text(message, style = serif(13, FontWeight.Normal, italic = true), color = p.secondary)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Spacer(Modifier.weight(1f))
                PrintButton("Cancel") { onDismiss() }
                PrintButton(action, filled = true) { onConfirm(); onDismiss() }
            }
        }
    }
}

