package local.connecthead.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import kotlin.math.hypot
import kotlin.math.min

/**
 * Flat-shaded vector drawing of the ULT WEAR, traced from Sony's straight-on product shot
 * (coordinates are in that photo's pixels; same drawing as the Mac app). From the front the
 * cups are seen edge-on: the ear-pad strip, a diagonal housing seam, the yoke's slot and the
 * outer rim; the tall band has slider joints near the shoulders and a joint above each yoke.
 */
@Composable
fun HeadphoneIllustration(modifier: Modifier = Modifier, color: Color = Color(0xFF5C6863)) {
    Canvas(modifier) {
        val s = min(size.width / FRAME.width, size.height / FRAME.height)
        withTransform({
            translate((size.width - FRAME.width * s) / 2, (size.height - FRAME.height * s) / 2)
            scale(s, s, Offset.Zero)
            translate(-FRAME.left, -FRAME.top)
        }) { drawHeadphones(color) }
    }
}

private val FRAME = Rect(360f, 100f, 1175f, 1010f)
private const val MID_X = 766.5f
private const val BAND_WIDTH = 76f

private val BAND_CENTRE = listOf(
    Offset(766.5f, 158f), Offset(900f, 175f), Offset(990f, 223f), Offset(1044f, 280f),
    Offset(1080f, 340f), Offset(1102f, 428f), Offset(1112f, 500f), Offset(1114f, 575f),
)

private val CUP_OUTLINE = listOf(
    Offset(1008f, 534f), Offset(1052f, 548f), Offset(1092f, 556f), Offset(1146f, 566f),
    Offset(1150f, 640f), Offset(1152f, 722f), Offset(1118f, 834f), Offset(1062f, 914f),
    Offset(1024f, 934f), Offset(950f, 952f), Offset(892f, 962f), Offset(846f, 946f),
    Offset(808f, 912f), Offset(800f, 876f), Offset(820f, 812f), Offset(858f, 738f),
    Offset(928f, 620f), Offset(972f, 554f),
)

private fun mirror(p: Offset, side: Float) = if (side > 0) p else Offset(2 * MID_X - p.x, p.y)
private fun mix(a: Color, b: Color, t: Float) = lerp(a, b, t)

private fun DrawScope.drawHeadphones(base: Color) {
    val light = mix(base, Color.White, 0.2f)
    val dark = mix(base, Color.Black, 0.28f)
    val deep = mix(base, Color.Black, 0.55f)

    // Soft floor shadow.
    drawIntoCanvas { c ->
        val paint = android.graphics.Paint().apply {
            this.color = android.graphics.Color.argb(76, 0, 0, 0)
            maskFilter = android.graphics.BlurMaskFilter(18f, android.graphics.BlurMaskFilter.Blur.NORMAL)
        }
        c.nativeCanvas.drawOval(420f, 950f, 1113f, 990f, paint)
    }

    // ---- Headband ----
    val right = BAND_CENTRE
    val left = right.reversed().map { mirror(it, -1f) }
    val spine = smooth(left.dropLast(1) + right, 14)
    val outer = ArrayList<Offset>(); val inner = ArrayList<Offset>()
    spine.indices.forEach { i ->
        val a = spine[maxOf(i - 1, 0)]; val b = spine[minOf(i + 1, spine.size - 1)]
        val len = maxOf(hypot(b.x - a.x, b.y - a.y), 0.001f)
        val n = Offset((b.y - a.y) / len, -(b.x - a.x) / len)
        outer += spine[i] + n * (BAND_WIDTH / 2); inner += spine[i] - n * (BAND_WIDTH / 2)
    }
    val band = polygon(outer + inner.reversed())
    translate(0f, 8f) { drawPath(band, Color.Black.copy(alpha = 0.12f)) }
    drawPath(band, Brush.verticalGradient(listOf(light, base, dark), startY = 110f, endY = 600f))
    drawPath(polyline(outer), Color.White.copy(alpha = 0.14f), style = Stroke(5f))
    drawPath(polyline(inner), deep.copy(alpha = 0.45f), style = Stroke(3f))
    val count = spine.size
    listOf(65, 68, count - 66, count - 69).forEach { seam(outer, inner, it, 2.2f, deep) }
    listOf(7, count - 8).forEach { seam(outer, inner, it, 3f, deep) }

    // ---- Cups ----
    for (side in listOf(-1f, 1f)) {
        fun m(x: Float, y: Float) = mirror(Offset(x, y), side)
        val outline = polygon(smooth(CUP_OUTLINE.map { mirror(it, side) }, 10, closed = true))
        translate(0f, 10f) { drawPath(outline, Color.Black.copy(alpha = 0.14f)) }
        drawPath(outline, Brush.linearGradient(listOf(mix(base, Color.Black, 0.12f), deep), m(980f, 540f), m(820f, 930f)))

        clipPath(outline) {
            val seamA = m(1056f, 540f) to m(828f, 940f)
            drawPath(halfPlane(seamA, m(1200f, 700f)), Brush.linearGradient(listOf(light, base, dark), m(1100f, 560f), m(900f, 960f)))
            val seamB = m(1130f, 650f) to m(950f, 958f)
            drawPath(halfPlane(seamB, m(1200f, 900f)), Brush.linearGradient(listOf(base, mix(dark, Color.Black, 0.1f)), m(1150f, 650f), m(1000f, 940f)))
            for ((a, b) in listOf(seamA, seamB)) {
                drawLine(deep.copy(alpha = 0.7f), a, b, 2.4f)
                drawLine(Color.White.copy(alpha = 0.16f), a + Offset(side * 4, 0f), b + Offset(side * 4, 0f), 2.5f)
            }
            // The yoke arm's slot: an outlined capsule.
            val s0 = m(1086f, 560f); val s1 = m(1030f, 760f)
            drawLine(deep.copy(alpha = 0.9f), s0, s1, 49f, StrokeCap.Round)
            drawLine(Brush.linearGradient(listOf(mix(light, Color.White, 0.05f), base), m(1090f, 560f), m(1020f, 780f)), s0, s1, 43.8f, StrokeCap.Round)
            // Mic grille.
            for (k in 0 until 7) {
                val y = 652f + k * 8
                drawLine(deep.copy(alpha = 0.6f), m(1133f + k * 1.6f, y), m(1146f + k * 1.2f, y + 3), 2f)
            }
            drawPath(outline, Brush.linearGradient(listOf(Color.White.copy(alpha = 0.22f), Color.Transparent, Color.Black.copy(alpha = 0.2f)), m(1100f, 540f), m(850f, 960f)), style = Stroke(3f))
        }

        if (side > 0) {
            drawCircle(Color(0xFF73FF99), 4.5f, Offset(1044.5f, 832.5f))
            drawCircle(deep, 15f, Offset(895f, 926f))
            drawCircle(Color.Black.copy(alpha = 0.85f), 7f, Offset(895f, 926f))
            drawRoundRect(Color.Black.copy(alpha = 0.8f), Offset(873f, 944f), androidx.compose.ui.geometry.Size(22f, 10f),
                androidx.compose.ui.geometry.CornerRadius(4f))
        }
    }
}

private fun DrawScope.seam(outer: List<Offset>, inner: List<Offset>, i: Int, width: Float, deep: Color) {
    drawLine(deep.copy(alpha = 0.85f), outer[i], inner[i], width)
    drawLine(Color.White.copy(alpha = 0.12f), outer[i + 1], inner[i + 1], 1.5f)
}

private fun polygon(points: List<Offset>) = Path().apply {
    moveTo(points[0].x, points[0].y); points.drop(1).forEach { lineTo(it.x, it.y) }; close()
}

private fun polyline(points: List<Offset>) = Path().apply {
    moveTo(points[0].x, points[0].y); points.drop(1).forEach { lineTo(it.x, it.y) }
}

/** A big polygon covering everything on one side of the line through `l`. */
private fun halfPlane(l: Pair<Offset, Offset>, towards: Offset): Path {
    val (a, b) = l
    val d = b - a
    val len = maxOf(hypot(d.x, d.y), 0.001f)
    val u = d / len
    var n = Offset(-u.y, u.x)
    if ((towards.x - a.x) * n.x + (towards.y - a.y) * n.y < 0) n = -n
    val far = 2000f
    return polygon(listOf(a - u * far, a + u * far, a + u * far + n * far, a - u * far + n * far))
}

/** Catmull-Rom through the points. */
private fun smooth(p: List<Offset>, n: Int, closed: Boolean = false): List<Offset> {
    val count = p.size
    fun at(i: Int) = if (closed) p[((i % count) + count) % count] else p[i.coerceIn(0, count - 1)]
    val out = ArrayList<Offset>()
    val segments = if (closed) count else count - 1
    for (i in 0 until segments) {
        val p0 = at(i - 1); val p1 = at(i); val p2 = at(i + 1); val p3 = at(i + 2)
        for (k in 0 until n) {
            val t = k.toFloat() / n; val t2 = t * t; val t3 = t2 * t
            fun c(a: Float, b: Float, cc: Float, d: Float) =
                0.5f * (2 * b + (cc - a) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (3 * b - a - 3 * cc + d) * t3)
            out += Offset(c(p0.x, p1.x, p2.x, p3.x), c(p0.y, p1.y, p2.y, p3.y))
        }
    }
    if (!closed) out += p.last()
    return out
}
