package app.kurotoon.android.experience

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import app.kurotoon.android.data.KurotoonPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.Closeable
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.UUID

enum class NarrationState { INITIALIZING, SPEAKING, COMPLETED, DISABLED, FAILED, STOPPED }

interface NarrationProvider : Closeable {
    val id: String
    val isOnDevice: Boolean
    fun speak(text: String, onState: (NarrationState, String?) -> Unit = { _, _ -> })
    fun stop()
}

/**
 * Uses the speech engine installed on the device, including any open-source Android TTS engine
 * the user has installed and selected at OS level. This is the reliable fallback provider.
 * Offline model-based open-source voices are kept behind the same interface and are not bundled
 * into the APK; voice models should be optional, checksummed downloads rather than hidden payloads.
 */
class AndroidSystemNarrationProvider(
    context: Context,
    private val preferences: KurotoonPreferences,
    private val scope: CoroutineScope,
) : NarrationProvider {
    override val id = "android-system-tts"
    override val isOnDevice = true

    private val appContext = context.applicationContext
    private val initialized = CompletableDeferred<Unit>()
    private val listeners = ConcurrentHashMap<String, (NarrationState, String?) -> Unit>()
    @Volatile private var engine: TextToSpeech? = null

    init {
        engine = TextToSpeech(appContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                engine?.language = Locale.getDefault()
                engine?.setSpeechRate(1.0f)
                engine?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String) {
                        listeners[utteranceId]?.invoke(NarrationState.SPEAKING, null)
                    }

                    override fun onDone(utteranceId: String) {
                        listeners.remove(utteranceId)?.invoke(NarrationState.COMPLETED, null)
                    }

                    @Deprecated("Deprecated by Android")
                    override fun onError(utteranceId: String) {
                        listeners.remove(utteranceId)?.invoke(NarrationState.FAILED, "System TTS could not render this text")
                    }

                    override fun onError(utteranceId: String, errorCode: Int) {
                        listeners.remove(utteranceId)?.invoke(
                            NarrationState.FAILED,
                            "System TTS failed with code $errorCode",
                        )
                    }
                })
                initialized.complete(Unit)
            } else {
                initialized.completeExceptionally(IllegalStateException("No working system text-to-speech engine"))
            }
        }
    }

    override fun speak(text: String, onState: (NarrationState, String?) -> Unit) {
        val cleaned = text.trim()
        if (cleaned.isBlank()) {
            onState(NarrationState.FAILED, "There is no text to narrate")
            return
        }
        if (cleaned.length > MAX_TEXT_LENGTH) {
            onState(NarrationState.FAILED, "Split long narration into shorter passages")
            return
        }
        val utteranceId = UUID.randomUUID().toString()
        scope.launch {
            val settings = preferences.settings.first()
            if (!settings.narrationEnabled) {
                onState(NarrationState.DISABLED, "Narration is turned off in experience settings")
                return@launch
            }
            onState(NarrationState.INITIALIZING, null)
            runCatching {
                initialized.await()
                withContext(Dispatchers.Main.immediate) {
                    val tts = requireNotNull(engine)
                    tts.setSpeechRate(1.0f)
                    listeners[utteranceId] = onState
                    val result = tts.speak(cleaned, TextToSpeech.QUEUE_FLUSH, Bundle(), utteranceId)
                    if (result == TextToSpeech.ERROR) {
                        listeners.remove(utteranceId)
                        onState(NarrationState.FAILED, "System TTS rejected the passage")
                    }
                }
            }.onFailure { error ->
                listeners.remove(utteranceId)
                onState(NarrationState.FAILED, error.message ?: "Narration failed")
            }
        }
    }

    override fun stop() {
        scope.launch {
            withContext(Dispatchers.Main.immediate) {
                engine?.stop()
                listeners.values.toList().forEach { it(NarrationState.STOPPED, null) }
                listeners.clear()
            }
        }
    }

    override fun close() {
        stop()
        scope.launch {
            withContext(Dispatchers.Main.immediate) {
                engine?.shutdown()
                engine = null
            }
        }
    }

    private companion object {
        const val MAX_TEXT_LENGTH = 4_000
    }
}
