package dev.rustmodforge.core

import java.awt.image.BufferedImage
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import javax.imageio.ImageIO
import javax.tools.ToolProvider

/**
 * Builds the fixture mods under src/test/fixtures into real jars: Java sources are compiled with
 * the JDK's javac against compile-only Minecraft stubs, so the analysers read genuine bytecode.
 * Stub classes never go into a jar.
 */
object Fixtures {
    val root = File(System.getProperty("rmf.fixtures") ?: "src/test/fixtures")
    private val work: File = Files.createTempDirectory("rmf-fixtures").toFile().also { it.deleteOnExit() }

    private val stubClasses: File by lazy {
        val out = File(work, "stubs").apply { mkdirs() }
        compile(File(root, "stubs").walkTopDown().filter { it.extension == "java" }.toList(), out, null)
        out
    }

    private fun compile(sources: List<File>, out: File, classpath: File?) {
        if (sources.isEmpty()) return
        val javac = ToolProvider.getSystemJavaCompiler() ?: error("tests need a JDK (javac)")
        val args = mutableListOf("-nowarn", "-proc:none", "--release", "17", "-d", out.path)
        if (classpath != null) { args += "-cp"; args += classpath.path }
        args += sources.map { it.path }
        val code = javac.run(null, null, System.err, *args.toTypedArray())
        check(code == 0) { "javac failed for ${sources.first().parentFile}" }
    }

    fun jar(name: String, extra: Map<String, File> = emptyMap()): File {
        val dir = File(root, name)
        val classes = File(work, "$name-classes").apply { deleteRecursively(); mkdirs() }
        compile(File(dir, "src").walkTopDown().filter { it.extension == "java" }.toList(), classes, stubClasses)
        val jar = File(work, "$name.jar")
        ZipOutputStream(jar.outputStream()).use { zip ->
            fun put(path: String, bytes: ByteArray) { zip.putNextEntry(ZipEntry(path)); zip.write(bytes); zip.closeEntry() }
            classes.walkTopDown().filter { it.isFile }.forEach { put(it.relativeTo(classes).invariantSeparatorsPath, it.readBytes()) }
            val res = File(dir, "resources")
            if (res.exists()) res.walkTopDown().filter { it.isFile }.forEach { put(it.relativeTo(res).invariantSeparatorsPath, it.readBytes()) }
            File(dir, "textures.txt").takeIf { it.exists() }?.readLines()?.filter { it.isNotBlank() }?.forEach { line ->
                val (path, w, h, rgb) = line.trim().split(Regex("\\s+"))
                put(path, png(w.toInt(), h.toInt(), rgb.toInt(16)))
            }
            for ((path, file) in extra) put(path, file.readBytes())
        }
        return jar
    }

    fun png(w: Int, h: Int, rgb: Int): ByteArray {
        val img = BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB)
        for (y in 0 until h) for (x in 0 until w) img.setRGB(x, y, (0xFF shl 24) or (rgb + (x xor y) % 16))
        val out = java.io.ByteArrayOutputStream()
        ImageIO.write(img, "png", out)
        return out.toByteArray()
    }

    fun tempDir(prefix: String): File = Files.createTempDirectory(work.toPath(), prefix).toFile()
}
