package com.example.camera.data

import android.content.Context
import android.content.SharedPreferences

/**
 * Small preference bag for camera behaviour. Deliberately flat and synchronous:
 * it is read once when the screen composes and written on change.
 */
class SettingsStore(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("halo_settings", Context.MODE_PRIVATE)

    var grid: Boolean
        get() = prefs.getBoolean(KEY_GRID, true)
        set(value) = prefs.edit().putBoolean(KEY_GRID, value).apply()

    var timerSeconds: Int
        get() = prefs.getInt(KEY_TIMER, 0)
        set(value) = prefs.edit().putInt(KEY_TIMER, value).apply()

    var autoAi: Boolean
        get() = prefs.getBoolean(KEY_AUTO_AI, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_AI, value).apply()

    var mirrorSelfie: Boolean
        get() = prefs.getBoolean(KEY_MIRROR, true)
        set(value) = prefs.edit().putBoolean(KEY_MIRROR, value).apply()

    var haptics: Boolean
        get() = prefs.getBoolean(KEY_HAPTICS, true)
        set(value) = prefs.edit().putBoolean(KEY_HAPTICS, value).apply()

    var saveToGallery: Boolean
        get() = prefs.getBoolean(KEY_SAVE_GALLERY, true)
        set(value) = prefs.edit().putBoolean(KEY_SAVE_GALLERY, value).apply()

    var videoQuality: String
        get() = prefs.getString(KEY_VIDEO_QUALITY, "FHD") ?: "FHD"
        set(value) = prefs.edit().putString(KEY_VIDEO_QUALITY, value).apply()

    var frameRate: Int
        get() = prefs.getInt(KEY_FPS, 30)
        set(value) = prefs.edit().putInt(KEY_FPS, value).apply()

    var photoAspect: String
        get() = prefs.getString(KEY_ASPECT, "RATIO_4_3") ?: "RATIO_4_3"
        set(value) = prefs.edit().putString(KEY_ASPECT, value).apply()

    var lastMode: String
        get() = prefs.getString(KEY_MODE, "PHOTO") ?: "PHOTO"
        set(value) = prefs.edit().putString(KEY_MODE, value).apply()

    companion object {
        private const val KEY_GRID = "grid"
        private const val KEY_TIMER = "timer_seconds"
        private const val KEY_AUTO_AI = "auto_ai"
        private const val KEY_MIRROR = "mirror_selfie"
        private const val KEY_HAPTICS = "haptics"
        private const val KEY_SAVE_GALLERY = "save_to_gallery"
        private const val KEY_VIDEO_QUALITY = "video_quality"
        private const val KEY_FPS = "frame_rate"
        private const val KEY_ASPECT = "photo_aspect"
        private const val KEY_MODE = "last_mode"
    }
}
