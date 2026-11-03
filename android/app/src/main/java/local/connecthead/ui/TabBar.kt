package local.connecthead.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.cos
import kotlin.math.sin

/**
 * The phone navigation, laid out like the portfolio site's mobile edition (a bottom tab bar
 * within reach of a thumb; four sections in the bar, the rest under More) but printed in this
 * app's paper and ink: a double rule on top, the active section inked in, tracked capitals.
 */
enum class Page(val title: String, val primary: Boolean, val icon: DrawScope.(Color) -> Unit) {
    OVERVIEW("Overview", true, { homeIcon(it) }),
    SOUND("Sound", true, { soundIcon(it) }),
    EQUALIZER("Equalizer", true, { slidersIcon(it) }),
    LISTENING("Listening", true, { chartIcon(it) }),
    DEVICES("Devices", false, { devicesIcon(it) }),
    SETTINGS("Settings", false, { gearIcon(it) }),
}

@Composable
fun TabBar(page: Page, moreOpen: Boolean, onSelect: (Page) -> Unit, onMore: () -> Unit) {
    val p = ink
    Column(Modifier.fillMaxWidth().paper().navigationBarsPadding()) {
        Rule(double = true)
        Row(Modifier.fillMaxWidth().height(62.dp).padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Page.entries.filter { it.primary }.forEach { item ->
                Tab(item.title, active = item == page, open = false, Modifier.weight(1f), icon = item.icon) { onSelect(item) }
            }
            Tab("More", active = !page.primary, open = moreOpen, Modifier.weight(1f), icon = { moreIcon(it) }) { onMore() }
        }
    }
}

@Composable
private fun Tab(label: String, active: Boolean, open: Boolean, modifier: Modifier,
                icon: DrawScope.(Color) -> Unit, onClick: () -> Unit) {
    val p = ink
    Column(
        modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, indication = null, onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier.size(46.dp, 28.dp)
                .background(when { active -> p.ink; open -> p.ink.copy(alpha = 0.08f); else -> Color.Transparent }, RoundedCornerShape(3.dp))
                .border(1.dp, if (open && !active) p.ink.copy(alpha = 0.5f) else Color.Transparent, RoundedCornerShape(3.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.size(18.dp)) { icon(if (active) p.sheet else p.ink.copy(alpha = 0.8f)) }
        }
        Text(label.uppercase(), style = labelStyle.copy(fontSize = 9.sp, letterSpacing = 1.1.sp,
            fontWeight = if (active) FontWeight.Bold else FontWeight.SemiBold),
            color = if (active) p.ink else p.ink.copy(alpha = 0.65f), textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            maxLines = 1, modifier = Modifier.padding(top = 4.dp))
    }
}

/** The sections that don't fit in the bar, as a grid rising above it, over a scrim. */
@Composable
fun MorePanel(open: Boolean, page: Page, onSelect: (Page) -> Unit, onDismiss: () -> Unit) {
    val p = ink
    AnimatedVisibility(open, enter = fadeIn(tween(150)), exit = fadeOut(tween(120))) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f))
            .clickable(remember { MutableInteractionSource() }, indication = null, onClick = onDismiss))
    }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        AnimatedVisibility(open, enter = fadeIn(tween(180)) + slideInVertically(tween(180)) { it / 6 },
            exit = fadeOut(tween(120)) + slideOutVertically(tween(120)) { it / 6 }) {
            Row(
                Modifier.padding(horizontal = 14.dp).padding(bottom = 12.dp).fillMaxWidth()
                    .printPanel(fill = p.paper)
                    .padding(10.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Page.entries.filter { !it.primary }.forEach { item ->
                    val active = item == page
                    Column(
                        Modifier.weight(1f).height(84.dp).clip(RoundedCornerShape(3.dp)).clickable { onSelect(item) },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        Box(Modifier.size(42.dp).background(if (active) p.ink else Color.Transparent, RoundedCornerShape(3.dp))
                            .border(1.dp, p.ink.copy(alpha = if (active) 1f else 0.5f), RoundedCornerShape(3.dp)), contentAlignment = Alignment.Center) {
                            Canvas(Modifier.size(19.dp)) { item.icon(this, if (active) p.sheet else p.ink) }
                        }
                        Text(item.title.uppercase(), style = labelStyle.copy(fontSize = 9.5.sp, letterSpacing = 1.2.sp,
                            fontWeight = if (active) FontWeight.Bold else FontWeight.SemiBold), color = p.ink,
                            modifier = Modifier.padding(top = 7.dp))
                    }
                }
                // Keep the grid three across, like the site.
                Box(Modifier.weight(1f))
            }
        }
    }
}

// ---- Line icons, Feather-style (24-unit grid, 2-unit strokes) ----

private fun DrawScope.u(v: Float) = v / 24f * size.minDimension
private fun DrawScope.pt(x: Float, y: Float) = Offset(u(x), u(y))
private fun DrawScope.line(c: Color) = Stroke(u(2f), cap = StrokeCap.Round, join = StrokeJoin.Round)

private fun DrawScope.homeIcon(c: Color) {
    val house = Path().apply {
        moveTo(u(3f), u(9f)); lineTo(u(12f), u(2f)); lineTo(u(21f), u(9f)); lineTo(u(21f), u(20f))
        quadraticTo(u(21f), u(22f), u(19f), u(22f)); lineTo(u(5f), u(22f)); quadraticTo(u(3f), u(22f), u(3f), u(20f)); close()
    }
    drawPath(house, c, style = line(c))
    drawPath(Path().apply { moveTo(u(9f), u(22f)); lineTo(u(9f), u(12f)); lineTo(u(15f), u(12f)); lineTo(u(15f), u(22f)) }, c, style = line(c))
}

private fun DrawScope.soundIcon(c: Color) {
    // Headphones: band arc and two cups.
    drawArc(c, 180f, 180f, false, pt(3f, 4f), Size(u(18f), u(18f)), style = line(c))
    drawRoundRect(c, pt(3f, 13f), Size(u(5f), u(8f)), CornerRadius(u(2f)), style = line(c))
    drawRoundRect(c, pt(16f, 13f), Size(u(5f), u(8f)), CornerRadius(u(2f)), style = line(c))
}

private fun DrawScope.slidersIcon(c: Color) {
    val s = line(c)
    for ((x, knob) in listOf(4f to 14f, 12f to 8f, 20f to 16f)) {
        drawLine(c, pt(x, 3f), pt(x, 21f), s.width, StrokeCap.Round)
        drawLine(c, pt(x - 3f, knob), pt(x + 3f, knob), s.width, StrokeCap.Round)
    }
}

private fun DrawScope.chartIcon(c: Color) {
    val w = u(2f)
    drawLine(c, pt(18f, 20f), pt(18f, 10f), w, StrokeCap.Round)
    drawLine(c, pt(12f, 20f), pt(12f, 4f), w, StrokeCap.Round)
    drawLine(c, pt(6f, 20f), pt(6f, 14f), w, StrokeCap.Round)
}

private fun DrawScope.devicesIcon(c: Color) {
    drawRoundRect(c, pt(2f, 5f), Size(u(14f), u(10f)), CornerRadius(u(1.5f)), style = line(c))
    drawLine(c, pt(1f, 19f), pt(15f, 19f), u(2f), StrokeCap.Round)
    drawRoundRect(c, pt(17f, 8f), Size(u(6f), u(12f)), CornerRadius(u(1.5f)), style = line(c))
}

private fun DrawScope.gearIcon(c: Color) {
    drawCircle(c, u(3f), pt(12f, 12f), style = line(c))
    drawCircle(c, u(7f), pt(12f, 12f), style = line(c))
    for (i in 0 until 8) {
        val a = i * Math.PI / 4
        drawLine(c, Offset(u(12f) + (cos(a) * u(7f)).toFloat(), u(12f) + (sin(a) * u(7f)).toFloat()),
            Offset(u(12f) + (cos(a) * u(10f)).toFloat(), u(12f) + (sin(a) * u(10f)).toFloat()), u(2f), StrokeCap.Round)
    }
}

private fun DrawScope.moreIcon(c: Color) {
    for (x in listOf(5f, 12f, 19f)) drawCircle(c, u(1.6f), pt(x, 12f))
}
