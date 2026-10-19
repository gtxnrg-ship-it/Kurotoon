package app.kurotoon.native.experience

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import app.kurotoon.native.data.KurotoonPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class HapticMoment { TAP, PAGE_TURN, CONFIRM, WARNING, ERROR }

/** Small, cancellable system haptics; users can disable all patterns from experience preferences. */
class HapticsController(
    context: Context,
    private val preferences: KurotoonPreferences,
    private val scope: CoroutineScope,
) {
    private val appContext = context.applicationContext

    fun play(moment: HapticMoment = HapticMoment.TAP) {
        scope.launch {
            if (!preferences.settings.first().hapticsEnabled) return@launch
            withContext(Dispatchers.Main.immediate) {
                val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    appContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    appContext.getSystemService(Vibrator::class.java)
                } ?: return@withContext
                if (!vibrator.hasVibrator()) return@withContext

                val pattern = when (moment) {
                    HapticMoment.TAP -> longArrayOf(0, 9) to intArrayOf(0, 42)
                    HapticMoment.PAGE_TURN -> longArrayOf(0, 7, 22, 8) to intArrayOf(0, 30, 0, 45)
                    HapticMoment.CONFIRM -> longArrayOf(0, 12, 35, 18) to intArrayOf(0, 45, 0, 60)
                    HapticMoment.WARNING -> longArrayOf(0, 18, 42, 18) to intArrayOf(0, 80, 0, 65)
                    HapticMoment.ERROR -> longArrayOf(0, 36) to intArrayOf(0, 100)
                }
                runCatching {
                    vibrator.vibrate(VibrationEffect.createWaveform(pattern.first, pattern.second, -1))
                }
            }
        }
    }
}
