package dev.rustmodforge.core.target

import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.util.JsonTree
import java.io.File

/**
 * A generated mod folder on disk. Files stream from the source archive straight to disk so a
 * large mod never sits in memory, and every write is checked to stay inside [root].
 */
class OutputTree(val root: File) {
    private val rootPath = root.canonicalFile.path + File.separator

    init { root.mkdirs() }

    fun file(path: String): File {
        val f = File(root, path).canonicalFile
        require(f.path.startsWith(rootPath)) { "refusing to write $path outside ${root.path}" }
        return f
    }

    fun exists(path: String) = file(path).exists()

    fun put(path: String, bytes: ByteArray) { val f = file(path); f.parentFile.mkdirs(); f.writeBytes(bytes) }
    fun putText(path: String, text: String) = put(path, text.toByteArray())
    fun putJson(path: String, value: Any?) = putText(path, JsonTree.write(value))

    fun copyFrom(archive: SafeArchive, from: String, to: String) {
        val f = file(to)
        f.parentFile.mkdirs()
        archive.open(from).use { input -> f.outputStream().use { input.copyTo(it) } }
    }

    fun readText(path: String) = file(path).readText()

    /** Every file, as `/`-separated paths relative to [root], sorted. */
    fun list(): List<String> = root.walkTopDown().filter { it.isFile }.map { it.relativeTo(root).invariantSeparatorsPath }.sorted().toList()

    fun clear() { root.deleteRecursively(); root.mkdirs() }
}
