package app.kurotoon.native.experience

import android.content.Context
import android.net.Uri
import app.kurotoon.native.data.KurotoonPreferences
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.Closeable

/**
 * Optional reader ambience. Nothing starts on launch; playback requires an explicit user action
 * and obeys persisted enable/volume preferences. ExoPlayer handles audio focus and noisy-device
 * transitions rather than maintaining a custom media thread.
 */
class AmbientAudioController(
    context: Context,
    private val preferences: KurotoonPreferences,
    private val scope: CoroutineScope,
    private val onError: (String) -> Unit = {},
) : Closeable {
    private val appContext = context.applicationContext
    private var player: ExoPlayer? = null

    fun playSelectedTrack(trackUrl: String) {
        val uri = runCatching { Uri.parse(trackUrl) }.getOrNull()
        if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank()) {
            onError("Ambience needs a valid HTTPS audio URL")
            return
        }
        scope.launch {
            val settings = preferences.settings.first()
            if (!settings.ambientAudioEnabled) {
                onError("Ambient audio is turned off in experience settings")
                return@launch
            }
            withContext(Dispatchers.Main.immediate) {
                runCatching {
                    releasePlayer()
                    val attributes = AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                        .build()
                    player = ExoPlayer.Builder(appContext).build().apply {
                        setAudioAttributes(attributes, true)
                        setHandleAudioBecomingNoisy(true)
                        volume = settings.ambienceVolume.coerceIn(0f, 1f)
                        repeatMode = Player.REPEAT_MODE_ONE
                        addListener(object : Player.Listener {
                            override fun onPlayerError(error: PlaybackException) {
                                onError("Ambience playback failed: ${error.errorCodeName}")
                                stop()
                            }
                        })
                        setMediaItem(MediaItem.fromUri(uri))
                        prepare()
                        playWhenReady = true
                    }
                }.onFailure { error ->
                    releasePlayer()
                    onError(error.message ?: "Could not start ambience")
                }
            }
        }
    }

    fun pause() {
        scope.launch { withContext(Dispatchers.Main.immediate) { player?.pause() } }
    }

    fun setVolume(volume: Float) {
        scope.launch {
            val settings = preferences.settings.first()
            if (!settings.ambientAudioEnabled) return@launch
            withContext(Dispatchers.Main.immediate) {
                player?.volume = volume.coerceIn(0f, 1f)
            }
        }
    }

    fun stop() {
        scope.launch { withContext(Dispatchers.Main.immediate) { releasePlayer() } }
    }

    override fun close() = stop()

    private fun releasePlayer() {
        player?.run {
            stop()
            clearMediaItems()
            release()
        }
        player = null
    }
}
