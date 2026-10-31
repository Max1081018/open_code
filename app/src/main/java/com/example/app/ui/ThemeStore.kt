package com.example.app.ui

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class ThemeMode(val label: String) {
    SYSTEM("Auto"),
    LIGHT("Light"),
    DARK("Dark")
}

class ThemeStore(context: Context) {

    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    private val _mode = MutableStateFlow(
        ThemeMode.values().getOrElse(prefs.getInt(KEY_THEME, 0)) { ThemeMode.SYSTEM }
    )
    val mode: StateFlow<ThemeMode> = _mode.asStateFlow()

    fun cycle() {
        val values = ThemeMode.values()
        val next = values[(_mode.value.ordinal + 1) % values.size]
        prefs.edit().putInt(KEY_THEME, next.ordinal).apply()
        _mode.value = next
    }

    private companion object {
        const val KEY_THEME = "theme_mode"
    }
}
