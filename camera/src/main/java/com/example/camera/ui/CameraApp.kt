package com.example.camera.ui

import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

@Composable
fun CameraApp(vm: CameraViewModel) {
    val context = LocalContext.current

    val toast = vm.toast
    LaunchedEffect(toast) {
        if (toast != null) {
            delay(2300)
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
        when (vm.screen) {
            Screen.Editor -> vm.closeEditor()
            Screen.Player -> vm.closePlayer()
            Screen.Gallery -> vm.openCamera()
            Screen.Camera -> Unit
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Ink)
    ) {
        when (vm.screen) {
            Screen.Camera -> CameraScreen(vm)
            Screen.Gallery -> GalleryScreen(vm)
            Screen.Editor -> EditorScreen(vm)
            Screen.Player -> PlayerScreen(vm)
        }

        if (vm.busy) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.45f))
                    // Absorb touches so a double-tap on Save cannot start a
                    // second render behind the scrim.
                    .pointerInput(Unit) {
                        awaitPointerEventScope {
                            while (true) {
                                awaitPointerEvent().changes.forEach { it.consume() }
                            }
                        }
                    },
                contentAlignment = Alignment.Center
            ) {
                BusyOverlay(vm.busyLabel)
            }
        }

        AnimatedVisibility(
            visible = vm.toast != null,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 96.dp)
        ) {
            HaloSnackbar(message = vm.toast ?: "")
        }
    }
}
