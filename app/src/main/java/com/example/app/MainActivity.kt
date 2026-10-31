package com.example.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.example.app.ui.AppTheme
import com.example.app.ui.TaskScreen
import com.example.app.ui.TaskViewModel
import com.example.app.ui.ThemeMode
import com.example.app.ui.ThemeStore

class MainActivity : ComponentActivity() {

    private val vm: TaskViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val themeStore = ThemeStore(this)
        setContent {
            val mode by themeStore.mode.collectAsState()
            val darkTheme = when (mode) {
                ThemeMode.SYSTEM -> isSystemInDarkTheme()
                ThemeMode.LIGHT -> false
                ThemeMode.DARK -> true
            }
            AppTheme(darkTheme = darkTheme) {
                TaskScreen(
                    vm = vm,
                    themeMode = mode,
                    onCycleTheme = { themeStore.cycle() }
                )
            }
        }
    }
}
