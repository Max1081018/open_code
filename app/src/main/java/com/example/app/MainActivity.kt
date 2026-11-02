package com.example.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.app.ui.AppTheme
import com.example.app.ui.ThemeMode
import com.example.app.ui.ThemeStore
import com.example.app.ui.WingmanScreen
import com.example.app.ui.WingmanViewModel

class MainActivity : ComponentActivity() {

    private val vm: WingmanViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val themeStore = ThemeStore(this)
        setContent {
            val mode by themeStore.mode.collectAsStateWithLifecycle()
            val darkTheme = when (mode) {
                ThemeMode.SYSTEM -> isSystemInDarkTheme()
                ThemeMode.LIGHT -> false
                ThemeMode.DARK -> true
            }
            AppTheme(darkTheme = darkTheme) {
                WingmanScreen(
                    vm = vm,
                    themeMode = mode,
                    onCycleTheme = { themeStore.cycle() }
                )
            }
        }
    }
}
