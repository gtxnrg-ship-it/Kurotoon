package app.kurotoon.native.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import java.io.IOException

private val Context.kurotoonExperienceDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "kurotoon_experience",
)

data class ExperienceSettings(
    val hapticsEnabled: Boolean = true,
    val ambientAudioEnabled: Boolean = false,
    val narrationEnabled: Boolean = false,
    val galaxyMotionEnabled: Boolean = true,
    val narrationVolume: Float = 0.8f,
    val ambienceVolume: Float = 0.22f,
)

class KurotoonPreferences(private val context: Context) {
    val settings: Flow<ExperienceSettings> = context.kurotoonExperienceDataStore.data
        .catch { error ->
            if (error is IOException) emit(androidx.datastore.preferences.core.emptyPreferences()) else throw error
        }
        .map { preferences ->
            ExperienceSettings(
                hapticsEnabled = preferences[Keys.Haptics] ?: true,
                ambientAudioEnabled = preferences[Keys.Ambience] ?: false,
                narrationEnabled = preferences[Keys.Narration] ?: false,
                galaxyMotionEnabled = preferences[Keys.Motion] ?: true,
                narrationVolume = (preferences[Keys.NarrationVolume] ?: 0.8f).coerceIn(0f, 1f),
                ambienceVolume = (preferences[Keys.AmbienceVolume] ?: 0.22f).coerceIn(0f, 1f),
            )
        }

    suspend fun setHapticsEnabled(enabled: Boolean) = context.kurotoonExperienceDataStore.edit { it[Keys.Haptics] = enabled }
    suspend fun setAmbientAudioEnabled(enabled: Boolean) = context.kurotoonExperienceDataStore.edit { it[Keys.Ambience] = enabled }
    suspend fun setNarrationEnabled(enabled: Boolean) = context.kurotoonExperienceDataStore.edit { it[Keys.Narration] = enabled }
    suspend fun setGalaxyMotionEnabled(enabled: Boolean) = context.kurotoonExperienceDataStore.edit { it[Keys.Motion] = enabled }
    suspend fun setNarrationVolume(volume: Float) = context.kurotoonExperienceDataStore.edit { it[Keys.NarrationVolume] = volume.coerceIn(0f, 1f) }
    suspend fun setAmbienceVolume(volume: Float) = context.kurotoonExperienceDataStore.edit { it[Keys.AmbienceVolume] = volume.coerceIn(0f, 1f) }

    private object Keys {
        val Haptics = booleanPreferencesKey("haptics_enabled")
        val Ambience = booleanPreferencesKey("ambient_audio_enabled")
        val Narration = booleanPreferencesKey("narration_enabled")
        val Motion = booleanPreferencesKey("galaxy_motion_enabled")
        val NarrationVolume = floatPreferencesKey("narration_volume")
        val AmbienceVolume = floatPreferencesKey("ambience_volume")
    }
}
