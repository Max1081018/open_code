package com.example.app.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The API key lives in EncryptedSharedPreferences, backed by the Android
 * keystore. It is never written to Room, never logged and never committed.
 *
 * If secure storage is unavailable on the device the key is held in memory for
 * the session only; [isPersistent] reports which of the two is happening so the
 * UI can say so instead of pretending.
 */
class CoachSettings(context: Context) {

    private val appContext = context.applicationContext
    private val prefs: SharedPreferences? = runCatching { openPrefs(appContext) }.getOrNull()

    val isPersistent: Boolean
        get() = prefs != null

    private val _config = MutableStateFlow(prefs?.let { read(it) } ?: CoachConfig())
    val config: StateFlow<CoachConfig> = _config.asStateFlow()

    fun save(updated: CoachConfig) {
        val cleaned = updated.copy(
            apiKey = updated.apiKey.trim(),
            baseUrl = updated.baseUrl.trim().trimEnd('/').ifBlank { CoachConfig.DEFAULT_BASE_URL },
            model = updated.model.trim().ifBlank { CoachConfig.DEFAULT_MODEL },
            myVoice = updated.myVoice.trim()
        )
        _config.value = cleaned
        prefs?.edit()
            ?.putString(KEY_API, cleaned.apiKey)
            ?.putString(KEY_BASE_URL, cleaned.baseUrl)
            ?.putString(KEY_MODEL, cleaned.model)
            ?.putString(KEY_VOICE, cleaned.myVoice)
            ?.apply()
    }

    fun clearKey() {
        prefs?.edit()?.remove(KEY_API)?.apply()
        _config.value = _config.value.copy(apiKey = "")
    }

    private fun read(from: SharedPreferences): CoachConfig = CoachConfig(
        apiKey = from.getString(KEY_API, "").orEmpty(),
        baseUrl = from.getString(KEY_BASE_URL, CoachConfig.DEFAULT_BASE_URL)
            .orEmpty()
            .ifBlank { CoachConfig.DEFAULT_BASE_URL },
        model = from.getString(KEY_MODEL, CoachConfig.DEFAULT_MODEL)
            .orEmpty()
            .ifBlank { CoachConfig.DEFAULT_MODEL },
        myVoice = from.getString(KEY_VOICE, "").orEmpty()
    )

    private companion object {
        const val FILE = "wingman_coach_secure"
        const val KEY_API = "api_key"
        const val KEY_BASE_URL = "base_url"
        const val KEY_MODEL = "model"
        const val KEY_VOICE = "my_voice"

        @Suppress("DEPRECATION")
        fun openPrefs(context: Context): SharedPreferences = try {
            build(context)
        } catch (first: Exception) {
            // A restored backup or a wiped keystore can leave a file we cannot
            // decrypt. Throwing here would crash on launch, so reset it once.
            context.deleteSharedPreferences(FILE)
            build(context)
        }

        @Suppress("DEPRECATION")
        fun build(context: Context): SharedPreferences {
            val key = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            return EncryptedSharedPreferences.create(
                context,
                FILE,
                key,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        }
    }
}
