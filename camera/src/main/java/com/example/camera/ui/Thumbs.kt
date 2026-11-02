package com.example.camera.ui

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.content.FileProvider
import com.example.camera.data.PhotoStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Loads a square thumbnail off the main thread and keeps it per composition key. */
@Composable
fun rememberThumbnail(store: PhotoStore, file: File?, size: Int): ImageBitmap? {
    val path = file?.absolutePath
    val bitmap by produceState<ImageBitmap?>(null, path, size) {
        value = if (file == null) {
            null
        } else {
            withContext(Dispatchers.IO) { store.thumbnail(file, size)?.asImageBitmap() }
        }
    }
    return bitmap
}

fun sharePhoto(context: Context, file: File) {
    try {
        val uri = FileProvider.getUriForFile(
            context,
            context.packageName + ".fileprovider",
            file
        )
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/jpeg"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(send, "Share photo")
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
    } catch (t: Throwable) {
        // No share target, or the provider was stripped. Nothing useful to do.
    }
}
