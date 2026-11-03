package local.connecthead.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * "Printed edition" look, shared with the Mac app: warm paper, ink, hairline and double rules,
 * panels with a hard offset ink shadow (never a blur), one vermilion accent, serif headlines.
 */
data class Palette(val paper: Color, val sheet: Color, val ink: Color, val shade: Color, val accent: Color, val secondary: Color)

private val Light = Palette(
    paper = Color(0xFFF4F0E8), sheet = Color(0xFFFBF9F4), ink = Color(0xFF1A1917),
    shade = Color(0xFF1A1917), accent = Color(0xFFC83F28), secondary = Color(0xFF77736B),
)
private val Dark = Palette(
    paper = Color(0xFF11100F), sheet = Color(0xFF1A1917), ink = Color(0xFFE7E2D7),
    shade = Color(0xFF66635D), accent = Color(0xFFE86248), secondary = Color(0xFF9A958B),
)

val LocalPalette = staticCompositionLocalOf { Light }
val ink @Composable get() = LocalPalette.current

@Composable
fun ConnectHeadTheme(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalPalette provides if (isSystemInDarkTheme()) Dark else Light, content = content)
}

// ---- Type ----

/**
 * Noto Serif, loaded straight from the system font files: some phones (OnePlus) restyle the
 * generic "serif" family with their own sans, which would lose the newspaper look.
 */
private val Serif: FontFamily = run {
    val dir = java.io.File("/system/fonts")
    val faces = listOf(
        "NotoSerif-Regular.ttf" to (FontWeight.Normal to FontStyle.Normal),
        "NotoSerif-Italic.ttf" to (FontWeight.Normal to FontStyle.Italic),
        "NotoSerif-Bold.ttf" to (FontWeight.Bold to FontStyle.Normal),
        "NotoSerif-BoldItalic.ttf" to (FontWeight.Bold to FontStyle.Italic),
    ).filter { java.io.File(dir, it.first).canRead() }
    if (faces.isEmpty()) FontFamily.Serif
    else FontFamily(faces.map { (file, ws) -> androidx.compose.ui.text.font.Font(java.io.File(dir, file), ws.first, ws.second) })
}

fun serif(size: Int, weight: FontWeight = FontWeight.Medium, italic: Boolean = false) =
    TextStyle(fontFamily = Serif, fontSize = size.sp,
              // Only regular and bold faces exist; keep medium as regular, semibold as bold.
              fontWeight = if (weight >= FontWeight.SemiBold) FontWeight.Bold else FontWeight.Normal,
              fontStyle = if (italic) FontStyle.Italic else FontStyle.Normal)

val labelStyle = TextStyle(fontFamily = FontFamily.SansSerif, fontSize = 10.5.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.6.sp)

@Composable
fun Label(text: String, modifier: Modifier = Modifier, color: Color = ink.ink) =
    Text(text.uppercase(), style = labelStyle, color = color, modifier = modifier)

// ---- Paper, rules and panels ----

/** Paper colour with a faint fibre grain (black paper in dark mode). */
@Composable
fun Modifier.paper(): Modifier {
    val p = ink
    val dark = isSystemInDarkTheme()
    val grain = remember { grainTile() }
    return this.background(p.paper).drawBehind {
        drawRect(ShaderBrush(ImageShader(grain, TileMode.Repeated, TileMode.Repeated)), alpha = if (dark) 0.08f else 0.05f)
    }
}

private fun grainTile(): ImageBitmap {
    val size = 160
    val bmp = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
    var seed = 0x9E3779B97F4A7C15uL
    for (y in 0 until size) for (x in 0 until size) {
        seed = seed * 6364136223846793005uL + 1442695040888963407uL
        val r = ((seed shr 40) and 0xFFFFuL).toInt() / 65535f
        val v = if (r < 0.04f) 40 else (110 + r * 100).toInt()
        bmp.setPixel(x, y, android.graphics.Color.argb(255, v, v, v))
    }
    return bmp.asImageBitmap()
}

@Composable
fun Rule(modifier: Modifier = Modifier, double: Boolean = false) {
    val p = ink
    if (double) Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Box(Modifier.fillMaxWidth().height(2.dp).background(p.ink))
        Box(Modifier.fillMaxWidth().height(0.75.dp).background(p.ink))
    } else Box(modifier.fillMaxWidth().height(0.75.dp).background(p.ink.copy(alpha = 0.85f)))
}

/** Ink border plus a solid offset shadow, the print-panel look. */
@Composable
fun Modifier.printPanel(fill: Color = ink.sheet, offset: Dp = 3.dp): Modifier {
    val p = ink
    return this
        .drawBehind {
            val o = offset.toPx()
            drawRoundRect(p.shade, topLeft = Offset(o, o), size = size, cornerRadius = CornerRadius(3.dp.toPx()))
        }
        .background(fill, RoundedCornerShape(3.dp))
        .border(1.dp, p.ink, RoundedCornerShape(3.dp))
}

/** Titled panel: a small tracked kicker over a hairline rule, then the content. */
@Composable
fun Card(title: String?, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(modifier.fillMaxWidth().printPanel().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (title != null) {
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) { Label(title); Rule() }
        }
        content()
    }
}

@Composable
fun PageHeader(title: String, subtitle: String) {
    val p = ink
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = serif(30), color = p.ink)
        Text(subtitle, style = serif(14, FontWeight.Normal, italic = true), color = p.secondary)
        Spacer(Modifier.height(6.dp))
        Rule(double = true)
    }
}

// ---- Controls ----

/** Outlined in ink, inked in while pressed (or when `filled`). */
@Composable
fun PrintButton(text: String, modifier: Modifier = Modifier, filled: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    val p = ink
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val inked = filled || pressed
    Box(
        modifier
            .background(if (inked) p.ink else Color.Transparent, RoundedCornerShape(3.dp))
            .border(1.dp, p.ink.copy(alpha = if (enabled) 0.7f else 0.3f), RoundedCornerShape(3.dp))
            .clickable(interaction, null, enabled = enabled, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium),
             color = if (inked) p.sheet else p.ink.copy(alpha = if (enabled) 1f else 0.4f))
    }
}

/** Squared switch: ink-outlined track, square knob; inked in when on. */
@Composable
fun PrintToggle(on: Boolean, onChange: (Boolean) -> Unit) {
    val p = ink
    val knobX by animateDpAsState(if (on) 21.dp else 3.dp, label = "knob")
    val track by animateColorAsState(if (on) p.ink else Color.Transparent, label = "track")
    Box(
        Modifier.size(40.dp, 22.dp)
            .background(track, RoundedCornerShape(3.dp))
            .border(1.dp, p.ink.copy(alpha = if (on) 1f else 0.55f), RoundedCornerShape(3.dp))
            .clickable { onChange(!on) },
    ) {
        Box(Modifier.offset(x = knobX, y = 3.dp).size(16.dp)
            .background(if (on) p.sheet else p.ink.copy(alpha = 0.7f), RoundedCornerShape(2.dp)))
    }
}

/**
 * Drag that only starts when the finger lands on a handle (within `grab` of a point that
 * `handleAt` returns); anywhere else the touch is left alone so the page can scroll. Stops
 * a scroll that happens to pass over an EQ curve or fader from changing the setting.
 */
suspend fun androidx.compose.ui.input.pointer.PointerInputScope.dragHandle(
    grab: Float,
    handleAt: (Offset) -> Int?,
    onMove: (Int, Offset) -> Unit,
    onEnd: (Int) -> Unit,
    /** If set, the finger must rest this long before the drag takes over (a quick swipe scrolls). */
    holdMillis: Long = 0,
    onGrab: () -> Unit = {},
) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val index = handleAt(down.position) ?: return@awaitEachGesture
        if (holdMillis > 0) {
            // Moving or lifting before the hold ends means it was a scroll or a tap: leave it alone.
            val interrupted = withTimeoutOrNull(holdMillis) {
                while (true) {
                    val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: return@withTimeoutOrNull true
                    if (!change.pressed || (change.position - down.position).getDistance() > viewConfiguration.touchSlop) return@withTimeoutOrNull true
                }
                @Suppress("UNREACHABLE_CODE") true
            }
            if (interrupted != null) return@awaitEachGesture
            onGrab()
        }
        down.consume()
        onMove(index, down.position)
        drag(down.id) { change ->
            change.consume()
            onMove(index, change.position)
        }
        onEnd(index)
    }
}

/** Labelled row with a trailing control. */
@Composable
fun SettingRow(title: String, detail: String? = null, control: @Composable () -> Unit) {
    val p = ink
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = serif(15), color = p.ink)
            if (detail != null) Text(detail, style = serif(12, FontWeight.Normal, italic = true), color = p.secondary)
        }
        Spacer(Modifier.size(12.dp))
        control()
    }
}

/** Outlined phone or laptop, drawn in ink. */
@Composable
fun DeviceIcon(isPhone: Boolean, modifier: Modifier = Modifier) {
    val p = ink
    Canvas(modifier) {
        val s = size.minDimension
        val stroke = androidx.compose.ui.graphics.drawscope.Stroke(1.4f * density)
        if (isPhone) {
            val w = s * 0.42f; val h = s * 0.7f
            drawRoundRect(p.ink, Offset((size.width - w) / 2, (size.height - h) / 2), androidx.compose.ui.geometry.Size(w, h),
                CornerRadius(3 * density), style = stroke)
            drawLine(p.ink, Offset(size.width / 2 - w * 0.18f, (size.height + h) / 2 - 4 * density),
                Offset(size.width / 2 + w * 0.18f, (size.height + h) / 2 - 4 * density), 1.4f * density)
        } else {
            val w = s * 0.62f; val h = s * 0.4f; val top = (size.height - h) / 2 - s * 0.05f
            drawRoundRect(p.ink, Offset((size.width - w) / 2, top), androidx.compose.ui.geometry.Size(w, h), CornerRadius(2 * density), style = stroke)
            drawLine(p.ink, Offset((size.width - s * 0.8f) / 2, top + h + 3 * density), Offset((size.width + s * 0.8f) / 2, top + h + 3 * density), 1.8f * density)
        }
    }
}

@Composable
fun Dot(color: Color, size: Dp = 6.dp) = Canvas(Modifier.size(size)) { drawCircle(color) }

@Composable
fun PaperScreen(content: @Composable () -> Unit) = Box(Modifier.fillMaxSize().paper()) { content() }
