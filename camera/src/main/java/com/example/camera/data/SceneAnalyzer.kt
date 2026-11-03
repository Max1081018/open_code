package com.example.camera.data

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabelerOptions
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.SegmentationMask
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import kotlinx.coroutines.tasks.await

/** A subject-confidence mask, 0..1 per pixel, produced by ML Kit. */
data class SubjectMask(
    val confidence: FloatArray,
    val width: Int,
    val height: Int,
    val coverage: Float
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SubjectMask) return false
        return width == other.width && height == other.height && confidence.contentEquals(
            other.confidence
        )
    }

    override fun hashCode(): Int = 31 * (31 * width + height) + confidence.contentHashCode()
}

/**
 * Thin wrappers around the bundled ML Kit models. Everything runs on device and is
 * optional: every call degrades to a sensible fallback if the model is missing.
 */
object SceneAnalyzer {

    suspend fun labels(bitmap: Bitmap): List<String> {
        return try {
            val client = ImageLabeling.getClient(
                ImageLabelerOptions.Builder().setConfidenceThreshold(0.35f).build()
            )
            try {
                client.process(InputImage.fromBitmap(bitmap, 0))
                    .await()
                    .map { it.text }
            } finally {
                client.close()
            }
        } catch (t: Throwable) {
            emptyList()
        }
    }

    /**
     * Segments a person out of [bitmap]. Returns null when no subject is found or
     * the model is unavailable, so callers fall back to the radial blur.
     */
    suspend fun subjectMask(bitmap: Bitmap): SubjectMask? {
        return try {
            val options = SelfieSegmenterOptions.Builder()
                .setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE)
                .build()
            val client = Segmentation.getClient(options)
            try {
                val mask: SegmentationMask = client.process(InputImage.fromBitmap(bitmap, 0))
                    .await()
                val width = mask.width
                val height = mask.height
                if (width < 8 || height < 8) return null
                val buffer = mask.buffer
                buffer.rewind()
                val values = FloatArray(width * height)
                var sum = 0f
                for (i in values.indices) {
                    val v = (buffer.get().toInt() and 0xFF) / 255f
                    values[i] = v
                    sum += v
                }
                val coverage = sum / values.size
                if (coverage < 0.02f || coverage > 0.97f) return null
                SubjectMask(values, width, height, coverage)
            } finally {
                client.close()
            }
        } catch (t: Throwable) {
            null
        }
    }
}
