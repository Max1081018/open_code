package dev.rustmodforge.core.bytecode

import dev.rustmodforge.core.archive.SafeArchive
import org.objectweb.asm.ClassReader
import org.objectweb.asm.util.Textifier
import org.objectweb.asm.util.TraceClassVisitor
import java.io.PrintWriter
import java.io.StringWriter

/**
 * Readable bytecode for the class viewer and for AI context, from ASM's Textifier (the
 * established JVM disassembler). Classes are parsed, never loaded. A Java-source decompiler can
 * be added behind the same call; the disassembly is what the analysers themselves read.
 */
object Disassembler {
    fun disassemble(archive: SafeArchive, internalName: String, maxChars: Int = 200_000): String {
        val path = "$internalName.class"
        if (!archive.contains(path)) return "// $internalName is not in this jar"
        val sw = StringWriter()
        ClassReader(archive.readBytes(path)).accept(TraceClassVisitor(null, Textifier(), PrintWriter(sw)), ClassReader.SKIP_FRAMES)
        val text = sw.toString()
        return if (text.length > maxChars) text.take(maxChars) + "\n// … trimmed at $maxChars characters" else text
    }
}
