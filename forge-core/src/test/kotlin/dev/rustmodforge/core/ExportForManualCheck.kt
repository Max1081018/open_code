package dev.rustmodforge.core

import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.pipeline.ConversionPipeline
import dev.rustmodforge.core.pipeline.Project
import dev.rustmodforge.core.pipeline.Quality
import java.io.File
import kotlin.test.Test

/**
 * Writes the generated packs to `RMF_EXPORT_DIR` so Horizon's own `cargo horizon-mod check` can
 * be run against them. Skipped unless that variable is set.
 */
class ExportForManualCheck {
    @Test
    fun exportPacks() {
        val out = System.getenv("RMF_EXPORT_DIR") ?: return
        val dir = File(out).apply { mkdirs() }
        val p = Project.create(Fixtures.tempDir("export"), "sounds", Quality.FAST, listOf(TargetId.HORIZON_ANDROID), listOf(Fixtures.jar("better_sounds")))
        ConversionPipeline(p).run()
        p.out.listFiles()?.forEach { f -> f.copyTo(File(dir, f.name), overwrite = true) }
        println("exported to " + dir.path + ": " + (dir.list()?.joinToString() ?: ""))
    }
}
