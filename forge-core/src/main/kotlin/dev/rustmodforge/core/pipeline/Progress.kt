package dev.rustmodforge.core.pipeline

import java.util.concurrent.atomic.AtomicBoolean

class CancelledException : Exception("Conversion cancelled")

/** Shared between the UI (which cancels) and the pipeline (which checks between steps). */
class CancellationToken {
    private val flag = AtomicBoolean(false)
    fun cancel() = flag.set(true)
    val isCancelled get() = flag.get()
    fun check() { if (flag.get()) throw CancelledException() }
}

/** A stage's progress: [fraction] in 0..1 of that stage, with a human-readable [detail]. */
fun interface ProgressListener {
    fun onProgress(stage: String, fraction: Float, detail: String)
}

object NoProgress : ProgressListener {
    override fun onProgress(stage: String, fraction: Float, detail: String) {}
}
