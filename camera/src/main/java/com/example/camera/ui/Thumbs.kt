package com.example.camera.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
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

/** Shares a mixed selection of photos and videos in one chooser. */
fun shareFiles(context: Context, files: List<File>) {
    if (files.isEmpty()) return
    try {
        val uris = files.map { file ->
            FileProvider.getUriForFile(
                context,
                context.packageName + ".fileprovider",
                file
            )
        }.toTypedArray()
        val allVideo = files.all { PhotoStore.isVideo(it) }
        val allPhoto = files.none { PhotoStore.isVideo(it) }
        val send = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = when {
                allVideo -> "video/mp4"
                allPhoto -> "image/jpeg"
                else -> "*/*"
            }
            // ACTION_SEND_MULTIPLE reads EXTRA_STREAMS, not EXTRA_STREAM.
            send.putExtra(Intent.EXTRA_STREAMS, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(send, "Share ${files.size} items")
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
    } catch (t: Throwable) {
        // No share target available.
    }
}
