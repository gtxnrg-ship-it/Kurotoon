package app.kurotoon.android.ui

import android.content.Context
import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

private data class StarParticle(
    val x: Float,
    val y: Float,
    val radius: Float,
    val alpha: Float,
    val phase: Float,
    val speed: Float,
    val hue: Float,
)

private data class NebulaCloud(
    val x: Float,
    val y: Float,
    val radius: Float,
    val hue: Float,
    val phase: Float,
    val drift: Float,
)

/**
 * Procedural native Galaxy backdrop: colour-shifting nebulae, parallax-like drifting clouds,
 * breathing stars, occasional shooting-star filaments and a short-lived touch ripple.
 * It draws directly to one Compose Canvas and creates no bitmap or particle object per frame.
 */
@Composable
fun GalaxyBackdrop(
    motionEnabled: Boolean,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val systemMotionEnabled = remember { systemAnimationsEnabled(context) }
    val animate = motionEnabled && systemMotionEnabled
    var elapsedSeconds by remember { mutableFloatStateOf(0f) }
    var rippleCenter by remember { mutableStateOf(Offset.Zero) }
    var rippleStartedAt by remember { mutableFloatStateOf(-10f) }

    val stars = remember {
        val random = Random(0x4B55524F)
        List(118) {
            StarParticle(
                x = random.nextFloat(),
                y = random.nextFloat(),
                radius = 0.35f + random.nextFloat() * 1.1f,
                alpha = 0.18f + random.nextFloat() * 0.56f,
                phase = random.nextFloat() * (2f * PI.toFloat()),
                speed = 0.12f + random.nextFloat() * 0.42f,
                hue = if (random.nextFloat() > 0.82f) 265f + random.nextFloat() * 35f
                    else 190f + random.nextFloat() * 35f,
            )
        }
    }
    val clouds = remember {
        val random = Random(0x47414C41)
        List(9) { index ->
            NebulaCloud(
                x = random.nextFloat(),
                y = random.nextFloat(),
                radius = 0.16f + random.nextFloat() * 0.30f,
                hue = when {
                    index % 4 == 0 -> 270f + random.nextFloat() * 25f
                    index % 3 == 0 -> 218f + random.nextFloat() * 30f
                    else -> 185f + random.nextFloat() * 42f
                },
                phase = random.nextFloat() * (2f * PI.toFloat()),
                drift = 0.014f + random.nextFloat() * 0.026f,
            )
        }
    }

    LaunchedEffect(animate) {
        if (!animate) {
            elapsedSeconds = 0f
            return@LaunchedEffect
        }
        val startTime = withFrameNanos { it }
        while (true) {
            withFrameNanos { now -> elapsedSeconds = (now - startTime) / 1_000_000_000f }
        }
    }

    Canvas(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(animate) {
                if (animate) {
                    detectTapGestures { point ->
                        rippleCenter = point
                        rippleStartedAt = elapsedSeconds
                    }
                }
            },
    ) {
        val w = size.width
        val h = size.height
        val t = if (animate) elapsedSeconds else 0f
        drawRect(
            brush = Brush.verticalGradient(
                colors = listOf(Color(0xFF070A18), Color(0xFF090D20), Color(0xFF050713)),
                startY = 0f,
                endY = h,
            ),
        )

        // The dominant hue travels slowly across blue, indigo, teal and violet.
        val paletteShift = (sin(t * 0.055f) * 0.5f + 0.5f)
        clouds.forEachIndexed { index, cloud ->
            val driftX = if (animate) sin(t * 0.06f + cloud.phase) * cloud.drift else 0f
            val driftY = if (animate) cos(t * 0.045f + cloud.phase) * cloud.drift * 1.35f else 0f
            val cx = ((cloud.x + driftX + 1f) % 1f) * w
            val cy = ((cloud.y + driftY + 1f) % 1f) * h
            val radius = cloud.radius * maxOf(w, h)
            val hueShift = if (index % 2 == 0) paletteShift * 72f else -paletteShift * 40f
            val hue = (cloud.hue + hueShift + 360f) % 360f
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(
                        Color.hsv(hue, 0.78f, 0.62f, 0.16f),
                        Color.hsv((hue + 18f) % 360f, 0.72f, 0.40f, 0.07f),
                        Color.Transparent,
                    ),
                    center = Offset(cx, cy),
                    radius = radius,
                ),
                radius = radius,
                center = Offset(cx, cy),
            )
        }

        // Broad, low-opacity filaments provide depth instead of a flat star wallpaper.
        for (index in 0 until 4) {
            val shift = if (animate) sin(t * 0.035f + index) * w * 0.025f else 0f
            val y = h * (0.14f + index * 0.18f)
            val hue = (204f + paletteShift * 88f + index * 11f) % 360f
            drawLine(
                color = Color.hsv(hue, 0.65f, 0.92f, 0.028f),
                start = Offset(-w * 0.12f, y),
                end = Offset(w * 0.58f + shift, h * (0.78f - index * 0.11f)),
                strokeWidth = 20f + index * 9f,
                cap = StrokeCap.Round,
            )
        }

        stars.forEach { star ->
            val drift = if (animate) sin(t * 0.05f * star.speed + star.phase) * 0.012f else 0f
            val x = ((star.x + drift + 1f) % 1f) * w
            val yDrift = if (animate) cos(t * 0.035f * star.speed + star.phase) * 0.009f else 0f
            val y = ((star.y + yDrift + 1f) % 1f) * h
            val shimmer = if (animate) sin(t * star.speed + star.phase) * 0.15f else 0f
            val alpha = (star.alpha + shimmer).coerceIn(0.07f, 0.86f)
            drawCircle(
                color = Color.hsv(star.hue, 0.28f, 1f, alpha),
                radius = star.radius,
                center = Offset(x, y),
            )
            if (star.radius > 1.0f && alpha > 0.48f) {
                drawLine(
                    color = Color(0x559CC8FF),
                    start = Offset(x - star.radius * 3f, y),
                    end = Offset(x + star.radius * 3f, y),
                    strokeWidth = 0.6f,
                )
                drawLine(
                    color = Color(0x339CC8FF),
                    start = Offset(x, y - star.radius * 3f),
                    end = Offset(x, y + star.radius * 3f),
                    strokeWidth = 0.6f,
                )
            }
        }

        // One sparse comet trail at a time; deterministic, bounded and very low-opacity.
        if (animate) {
            val cycle = (t % 19f) / 19f
            if (cycle in 0.52f..0.59f) {
                val local = (cycle - 0.52f) / 0.07f
                val x = w * (1.12f - local * 1.35f)
                val y = h * (0.11f + local * 0.30f)
                drawLine(
                    color = Color(0x889EDBFF),
                    start = Offset(x, y),
                    end = Offset(x + w * 0.085f, y - h * 0.018f),
                    strokeWidth = 1.4f,
                    cap = StrokeCap.Round,
                )
            }
        }

        val rippleAge = t - rippleStartedAt
        if (animate && rippleAge in 0f..1.4f) {
            val progress = rippleAge / 1.4f
            drawCircle(
                color = Color(0x6676C9FF).copy(alpha = 0.38f * (1f - progress)),
                radius = 28f + progress * 178f,
                center = rippleCenter,
                style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.4f + (1f - progress) * 1.4f),
            )
            drawCircle(
                color = Color(0x447F8CFF).copy(alpha = 0.16f * (1f - progress)),
                radius = 12f + progress * 92f,
                center = rippleCenter,
                style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1f),
            )
        }
    }
}

private fun systemAnimationsEnabled(context: Context): Boolean = runCatching {
    Settings.Global.getFloat(
        context.contentResolver,
        Settings.Global.ANIMATOR_DURATION_SCALE,
        1f,
    ) > 0f
}.getOrDefault(true)
