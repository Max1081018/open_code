package com.example.camera.ui

import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

@Composable
fun CameraApp(vm: CameraViewModel) {
    val context = LocalContext.current

    val toast = vm.toast
    LaunchedEffect(toast) {
        if (toast != null) {
            Toast.makeText(context, toast, Toast.LENGTH_SHORT).show()
            vm.clearToast()
        }
    }

    val share = vm.shareRequest
    LaunchedEffect(share) {
        if (share != null) {
            sharePhoto(context, share)
            vm.clearShare()
        }
    }

    BackHandler(enabled = vm.screen != Screen.Camera) {
        if (vm.screen == Screen.Editor) vm.closeEditor() else vm.openCamera()
    }

    Box(modifier = Modifier.fillMaxSize().background(Ink)) {
        when (vm.screen) {
            Screen.Camera -> CameraScreen(vm)
            Screen.Gallery -> GalleryScreen(vm)
            Screen.Editor -> EditorScreen(vm)
        }

        if (vm.busy) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.35f)),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator(
                    color = Amber,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(30.dp)
                )
            }
        }
    }
}
