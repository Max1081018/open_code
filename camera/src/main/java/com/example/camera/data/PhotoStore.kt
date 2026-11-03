package com.example.camera.data

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.MediaMetadataRetriever
import android.os.Build
import android.provider.MediaStore
import android.util.LruCache
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * App-private photo and video library. Media never leaves the app unless the user
 * shares it or explicitly exports it to the system gallery.
 */
class PhotoStore private constructor(context: Context) {

    private val root: File = File(context.filesDir, "photos")
    private val videoDir: File = File(context.filesDir, "videos")
    private val thumbs = LruCache<String, Bitmap>(64)
    private val durations = LruCache<String, Long>(32)

    init {
        root.mkdirs()
        videoDir.mkdirs()
    }

    companion object {
        @Volatile
        private var instance: PhotoStore? = null

        fun get(context: Context): PhotoStore = instance ?: synchronized(this) {
            instance ?: PhotoStore(context.applicationContext).also { instance = it }
        }

        private fun stamp(): String =
            SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())

        fun isVideo(file: File): Boolean =
            file.extension.equals("mp4", true) ||
                file.extension.equals("mkv", true) ||
                file.extension.equals("mov", true)
    }

    fun newCaptureFile(): File = File(root, "IMG_${stamp()}.jpg")

    fun newEditFile(): File = File(root, "IMG_${stamp()}_edit.jpg")

    fun newVideoFile(): File = File(videoDir, "VID_${stamp()}.mp4")

    fun photos(): List<File> = listIn(root)

    fun videos(): List<File> = listIn(videoDir)

    fun all(): List<File> = photos() + videos()

    fun latestPhoto(): File? = photos().firstOrNull()

    private fun listIn(dir: File): List<File> = dir.listFiles { f ->
        f.isFile && f.length() > 0
    }?.sortedByDescending { it.lastModified() } ?: emptyList()

    fun write(bitmap: Bitmap, file: File, quality: Int = 97): Boolean {
        return try {
            file.parentFile?.mkdirs()
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
            }
            thumbs.remove(file.absolutePath)
            file.length() > 0
        } catch (t: Throwable) {
            file.delete()
            false
        }
    }

    fun delete(file: File): Boolean {
        thumbs.remove(file.absolutePath)
        durations.remove(file.absolutePath)
        return file.delete()
    }

    fun decode(file: File, maxDim: Int): Bitmap? {
        if (!file.exists() || isVideo(file)) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxDim) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val raw = BitmapFactory.decodeFile(file.absolutePath, opts) ?: return null

        val upright = orient(file, raw)
        if (upright !== raw) raw.recycle()

        val scaled = scaleDown(upright, maxDim)
        if (scaled !== upright) upright.recycle()
        return scaled
    }

    /** Square centre-cropped thumbnail, cached in memory. Photos and videos. */
    fun thumbnail(file: File, size: Int): Bitmap? {
        val key = file.absolutePath + "@" + size
        thumbs.get(key)?.let { return it }

        val decoded = if (isVideo(file)) {
            videoFrame(file)
        } else {
            decode(file, size * 2)
        } ?: return null
        val side = min(decoded.width, decoded.height)
        val left = (decoded.width - side) / 2
        val top = (decoded.height - side) / 2

        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        Canvas(out).drawBitmap(
            decoded,
            Rect(left, top, left + side, top + side),
            Rect(0, 0, size, size),
            Paint(Paint.FILTER_BITMAP_FLAG)
        )
        decoded.recycle()
        thumbs.put(key, out)
        return out
    }

    /** Middle frame of a video, used for the gallery tile and player poster. */
    fun videoFrame(file: File): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val frame = retriever.getFrameAtTime(
                -1L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            )
            frame
        } catch (t: Throwable) {
            null
        } finally {
            try {
                retriever.release()
            } catch (t: Throwable) {
                // Nothing to release.
            }
        }
    }

    fun durationMs(file: File): Long {
        if (!isVideo(file)) return 0L
        durations.get(file.absolutePath)?.let { return it }
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val value = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: 0L
            durations.put(file.absolutePath, value)
            value
        } catch (t: Throwable) {
            0L
        } finally {
            try {
                retriever.release()
            } catch (t: Throwable) {
                // Nothing to release.
            }
        }
    }

    /**
     * Copies a file into the system gallery (Pictures/Halo Camera or Movies/Halo
     * Camera). No permission is needed on Android 10+, which covers the target
     * device; on older versions the caller must hold WRITE_EXTERNAL_STORAGE.
     */
    fun exportToSystemGallery(context: Context, file: File): Boolean {
        if (!file.exists() || file.length() == 0L) return false
        val video = isVideo(file)
        val resolver = context.contentResolver
        val collection = if (video) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(
                MediaStore.MediaColumns.MIME_TYPE,
                if (video) "video/mp4" else "image/jpeg"
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    if (video) "Movies/Halo Camera" else "Pictures/Halo Camera"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
        val uri = resolver.insert(collection, values) ?: return false
        return try {
            val out = resolver.openOutputStream(uri)
            if (out == null) {
                resolver.delete(uri, null, null)
                return false
            }
            out.use { destination ->
                file.inputStream().use { it.copyTo(destination) }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            }
            true
        } catch (t: Throwable) {
            try {
                resolver.delete(uri, null, null)
            } catch (ignored: Throwable) {
                // Keep the original error.
            }
            false
        }
    }

    private fun scaleDown(bmp: Bitmap, maxDim: Int): Bitmap {
        val longEdge = max(bmp.width, bmp.height)
        if (longEdge <= maxDim) return bmp
        val ratio = maxDim.toFloat() / longEdge.toFloat()
        val w = max(1, (bmp.width * ratio).toInt())
        val h = max(1, (bmp.height * ratio).toInt())
        return Bitmap.createScaledBitmap(bmp, w, h, true)
    }

    private fun orient(file: File, bmp: Bitmap): Bitmap {
        val exif = try {
            ExifInterface(file.absolutePath)
        } catch (t: Throwable) {
            return bmp
        }
        val orientation = exif.getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL
        )
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            else -> return bmp
        }
        return try {
            Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
        } catch (t: Throwable) {
            bmp
        }
    }
}
