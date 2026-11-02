package com.example.camera

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.core.view.WindowCompat
import com.example.camera.ui.CameraApp
import com.example.camera.ui.CameraViewModel
import com.example.camera.ui.HaloTheme

class MainActivity : ComponentActivity() {

    private val vm: CameraViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContent {
            HaloTheme {
                CameraApp(vm)
            }
        }
    }
}
