package dev.rustmodforge.core.archive

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

/**
 * Limits applied to every imported archive. Imported jars are untrusted input: these bound
 * memory, disk and CPU no matter what the archive's headers claim.
 */
data class ArchiveLimits(
    /** Most entries an archive may list. Horizon's own content limit is 65,536. */
    val maxEntries: Int = 65_536,
    /** Largest single entry once decompressed. */
    val maxEntryBytes: Long = 64L shl 20,
    /** Largest total of all decompressed entries actually read. */
    val maxTotalBytes: Long = 1L shl 30,
    /** Highest decompressed:compressed ratio for an entry bigger than [ratioFloorBytes]. */
    val maxCompressionRatio: Long = 200,
    val ratioFloorBytes: Long = 1L shl 20,
    /** Longest entry path in bytes (the Android launcher refuses past 1,024). */
    val maxPathBytes: Int = 1024,
    /** How deep jar-in-jar nesting is followed. */
    val maxNestingDepth: Int = 2,
)

class ArchiveException(message: String) : IOException(message)

/** One entry, with its normalized path and declared sizes. */
data class ArchiveEntry(val path: String, val size: Long, val compressedSize: Long)

/**
 * Read-only view of a zip/jar that refuses path traversal, absolute paths, duplicates and
 * oversized or over-compressed entries, and counts every byte it hands out. Nothing is
 * extracted to disk unless the caller asks for a specific entry, and then only below a
 * directory the caller owns.
 */
class SafeArchive private constructor(
    val source: File,
    private val zip: ZipFile,
    val limits: ArchiveLimits,
    val entries: List<ArchiveEntry>,
    private val byPath: Map<String, ZipEntry>,
) : AutoCloseable {

    private var bytesRead = 0L

    fun contains(path: String) = byPath.containsKey(path)

    /** Opens an entry; reading more than its limit throws instead of exhausting memory or disk. */
    fun open(path: String): InputStream {
        val entry = byPath[path] ?: throw ArchiveException("no entry $path")
        return LimitedInput(zip.getInputStream(entry), path)
    }

    fun readBytes(path: String): ByteArray = open(path).use { it.readBytes() }

    fun readText(path: String): String = readBytes(path).toString(Charsets.UTF_8).removePrefix("﻿")

    /** Copies one entry to [dir]/[relative], refusing anything that would land outside [dir]. */
    fun extractTo(path: String, dir: File, relative: String = path): File {
        val root = dir.canonicalFile
        val target = File(root, relative).canonicalFile
        if (!target.path.startsWith(root.path + File.separator)) {
            throw ArchiveException("refusing to write $relative outside ${root.path}")
        }
        target.parentFile.mkdirs()
        open(path).use { input -> target.outputStream().use { input.copyTo(it) } }
        return target
    }

    val totalBytesRead get() = bytesRead

    override fun close() = zip.close()

    private inner class LimitedInput(private val inner: InputStream, private val path: String) : InputStream() {
        private var count = 0L
        private fun account(n: Int) {
            if (n <= 0) return
            count += n
            bytesRead += n
            if (count > limits.maxEntryBytes) throw ArchiveException("$path is larger than ${limits.maxEntryBytes} bytes")
            if (bytesRead > limits.maxTotalBytes) throw ArchiveException("archive expands past ${limits.maxTotalBytes} bytes")
        }
        override fun read(): Int = inner.read().also { if (it >= 0) account(1) }
        override fun read(b: ByteArray, off: Int, len: Int): Int = inner.read(b, off, len).also { account(it) }
        override fun close() = inner.close()
    }

    companion object {
        fun open(file: File, limits: ArchiveLimits = ArchiveLimits()): SafeArchive {
            val zip = try {
                ZipFile(file)
            } catch (e: Exception) {
                throw ArchiveException("${file.name} is not a readable zip/jar: ${e.message}")
            }
            try {
                val list = ArrayList<ArchiveEntry>()
                val map = HashMap<String, ZipEntry>()
                val all = zip.entries()
                var count = 0
                while (all.hasMoreElements()) {
                    val e = all.nextElement()
                    if (++count > limits.maxEntries) throw ArchiveException("more than ${limits.maxEntries} entries")
                    if (e.isDirectory) continue
                    val path = normalize(e.name, limits)
                    if (map.containsKey(path)) throw ArchiveException("duplicate entry $path")
                    val size = e.size
                    val compressed = e.compressedSize
                    if (size > limits.maxEntryBytes) throw ArchiveException("$path declares $size bytes")
                    if (size > limits.ratioFloorBytes && compressed > 0 && size / compressed > limits.maxCompressionRatio) {
                        throw ArchiveException("$path is compressed ${size / compressed}:1, refused as a zip bomb")
                    }
                    map[path] = e
                    list += ArchiveEntry(path, size, compressed)
                }
                return SafeArchive(file, zip, limits, list.sortedBy { it.path }, map)
            } catch (e: Exception) {
                zip.close()
                throw e
            }
        }

        /** A path as Horizon's readers accept it: relative, '/'-separated, no '.', '..' or empty parts. */
        fun normalize(raw: String, limits: ArchiveLimits = ArchiveLimits()): String {
            if (raw.toByteArray().size > limits.maxPathBytes) throw ArchiveException("entry path longer than ${limits.maxPathBytes} bytes")
            if (raw.contains('\u0000')) throw ArchiveException("entry path contains NUL")
            if (raw.contains('\\')) throw ArchiveException("entry path $raw uses '\\'")
            if (raw.startsWith("/")) throw ArchiveException("absolute entry path $raw")
            if (raw.length >= 2 && raw[1] == ':') throw ArchiveException("drive-letter entry path $raw")
            val parts = raw.split('/')
            for ((i, p) in parts.withIndex()) {
                if (p == "..") throw ArchiveException("path traversal in $raw")
                if (p == "." || (p.isEmpty() && i != parts.lastIndex)) throw ArchiveException("malformed entry path $raw")
            }
            return raw
        }
    }
}
