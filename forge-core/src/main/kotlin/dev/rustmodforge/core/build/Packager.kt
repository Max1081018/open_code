package dev.rustmodforge.core.build

import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Packs a generated folder into a `.hmod`/`.hnmod` zip, deterministically (sorted, fixed times). */
object Packager {
    private const val FIXED_TIME = 315532800000L // 1980-01-01, the zip epoch

    fun pack(dir: File, out: File, include: (String) -> Boolean = { true }): File {
        out.parentFile?.mkdirs()
        val files = dir.walkTopDown().filter { it.isFile }.map { it.relativeTo(dir).invariantSeparatorsPath to it }
            .filter { include(it.first) }.sortedBy { it.first }.toList()
        val tmp = File(out.parentFile, out.name + ".part")
        ZipOutputStream(tmp.outputStream().buffered()).use { zip ->
            zip.setLevel(9)
            for ((path, f) in files) {
                val e = ZipEntry(path)
                e.time = FIXED_TIME
                zip.putNextEntry(e)
                f.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
        if (out.exists()) out.delete()
        check(tmp.renameTo(out)) { "could not move ${tmp.name} to ${out.name}" }
        return out
    }

    fun sha256(f: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { input -> val buf = ByteArray(65536); while (true) { val n = input.read(buf); if (n < 0) break; md.update(buf, 0, n) } }
        return md.digest().joinToString("") { "%02x".format(it) }
    }
}
