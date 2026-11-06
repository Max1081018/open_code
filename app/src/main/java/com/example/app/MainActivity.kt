package com.example.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.app.ui.AppTheme
import com.example.app.ui.ThemeMode
import com.example.app.ui.ThemeStore
import com.example.app.ui.WingmanScreen
import com.example.app.ui.WingmanViewModel

class MainActivity : ComponentActivity() {

    private val vm: WingmanViewModel by viewModels()

    private val notificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        val themeStore = ThemeStore(this)
        setContent {
            val mode by themeStore.mode.collectAsStateWithLifecycle()
            val darkTheme = when (mode) {
                ThemeMode.SYSTEM -> isSystemInDarkTheme()
                ThemeMode.LIGHT -> false
                ThemeMode.DARK -> true
            }

            SideEffect {
                val background = if (darkTheme) 0xFF0B1020 else 0xFFF6F7FB
                window.statusBarColor = background.toInt()
                window.navigationBarColor = background.toInt()
                WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = !darkTheme
                    isAppearanceLightNavigationBars = !darkTheme
                }
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
