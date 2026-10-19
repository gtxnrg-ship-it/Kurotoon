package app.kurotoon.android.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val GalaxyColors = darkColorScheme(
    primary = Color(0xFF9DCBFF),
    onPrimary = Color(0xFF061427),
    secondary = Color(0xFFC2B2FF),
    onSecondary = Color(0xFF21154A),
    tertiary = Color(0xFF78E3D1),
    background = Color(0xFF070A18),
    onBackground = Color(0xFFF3F5FF),
    surface = Color(0xFF10162A),
    onSurface = Color(0xFFF3F5FF),
    surfaceVariant = Color(0xFF202943),
    onSurfaceVariant = Color(0xFFBBC5E0),
    outline = Color(0xFF657492),
)

@Composable
fun KurotoonTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = GalaxyColors,
        content = content,
    )
}
