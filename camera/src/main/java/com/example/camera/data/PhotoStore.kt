package com.example.camera.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
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
 * App-private photo library. Photos never leave the app unless the user shares
 * them, so no storage permission is ever needed.
 */
class PhotoStore private constructor(context: Context) {

    private val dir: File = File(context.filesDir, "photos").apply { if (!exists()) mkdirs() }
    private val thumbs = LruCache<String, Bitmap>(48)

    companion object {
        @Volatile
        private var instance: PhotoStore? = null

        fun get(context: Context): PhotoStore = instance ?: synchronized(this) {
            instance ?: PhotoStore(context.applicationContext).also { instance = it }
        }

        private fun stamp(): String =
            SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())
    }

    fun newCaptureFile(): File = File(dir, "IMG_${stamp()}.jpg")

    fun newEditFile(): File = File(dir, "IMG_${stamp()}_edit.jpg")

    fun list(): List<File> =
        dir.listFiles { f -> f.isFile && f.length() > 0 && f.extension.equals("jpg", true) }
            ?.sortedByDescending { it.lastModified() }
            ?: emptyList()

    fun latest(): File? = list().firstOrNull()

    fun write(bitmap: Bitmap, file: File): Boolean {
        return try {
            file.parentFile?.mkdirs()
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
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
        return file.delete()
    }

    fun decode(file: File, maxDim: Int): Bitmap? {
        if (!file.exists()) return null
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

    /** Square centre-cropped thumbnail, cached in memory. */
    fun thumbnail(file: File, size: Int): Bitmap? {
        val key = file.absolutePath + "@" + size
        thumbs.get(key)?.let { return it }

        val decoded = decode(file, size * 2) ?: return null
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
