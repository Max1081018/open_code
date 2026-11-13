package dev.rustmodforge.core.bytecode

import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.model.ApiUsage
import dev.rustmodforge.core.model.ClassSummary
import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassVisitor
import org.objectweb.asm.FieldVisitor
import org.objectweb.asm.MethodVisitor
import org.objectweb.asm.Opcodes
import org.objectweb.asm.tree.ClassNode

/** What pass 1 keeps per class: names only, a few hundred bytes, so big mods fit in memory. */
class ClassHeader(
    val name: String,
    val superName: String?,
    val interfaces: List<String>,
    val methods: List<Pair<String, String>>,
    val fields: List<Pair<String, String>>,
    val size: Long,
    /** Owners of every field/method the class references, and its string constants (bounded). */
    val references: Set<String>,
    val strings: List<String>,
    val path: String,
    val access: Int,
)

/**
 * Bytecode reader. Pass 1 visits every class once and keeps only [ClassHeader]s. Pass 2
 * ([node]) re-reads one class as an ASM tree when an analyser needs its instructions. Classes
 * are parsed, never loaded or executed.
 */
class ClassScanner(private val archive: SafeArchive) {
    val headers = LinkedHashMap<String, ClassHeader>()

    fun scanHeaders(onProgress: (Int, Int) -> Unit = { _, _ -> }, cancelled: () -> Boolean = { false }) {
        val classes = archive.entries.filter { it.path.endsWith(".class") && !it.path.startsWith("META-INF/versions/") }
        for ((i, e) in classes.withIndex()) {
            if (cancelled()) return
            val bytes = try { archive.readBytes(e.path) } catch (_: Exception) { continue }
            val header = try { readHeader(bytes, e.path, e.size) } catch (_: Exception) { null } ?: continue
            headers[header.name] = header
            if (i % 50 == 0) onProgress(i, classes.size)
        }
        onProgress(classes.size, classes.size)
    }

    fun node(name: String): ClassNode? {
        val h = headers[name] ?: return null
        return try {
            ClassNode().also { ClassReader(archive.readBytes(h.path)).accept(it, ClassReader.SKIP_FRAMES) }
        } catch (_: Exception) { null }
    }

    /** Superclass chain, crossing into vanilla names when the mod's own classes end. */
    fun superChain(name: String): List<String> {
        val out = ArrayList<String>()
        var cur: String? = headers[name]?.superName
        var guard = 0
        while (cur != null && guard++ < 64) {
            out += cur
            cur = headers[cur]?.superName
        }
        return out
    }

    /** The vanilla concept a class extends or implements, nearest first, per [Vanilla.entityBases] order. */
    fun vanillaBase(name: String, order: List<String> = Vanilla.entityBases): String? {
        val chain = superChain(name)
        val concepts = chain.mapNotNull { Vanilla.classConcept(it) }
        return order.firstOrNull { it in concepts } ?: concepts.firstOrNull()
    }

    fun implementsConcept(name: String, concept: String): Boolean {
        val names = Vanilla.classes[concept] ?: return false
        val seen = HashSet<String>()
        fun visit(n: String?): Boolean {
            if (n == null || !seen.add(n)) return false
            if (n in names) return true
            val h = headers[n] ?: return false
            return h.interfaces.any { visit(it) } || visit(h.superName)
        }
        return visit(name)
    }

    fun extendsConcept(name: String, concept: String): Boolean {
        val names = Vanilla.classes[concept] ?: Vanilla.goals[concept] ?: return false
        return superChain(name).any { it in names }
    }

    fun summaries(): List<ClassSummary> = headers.values.map {
        ClassSummary(
            name = it.name.replace('/', '.'), superName = it.superName?.replace('/', '.'),
            interfaces = it.interfaces.map { i -> i.replace('/', '.') }, methodCount = it.methods.size,
            fieldCount = it.fields.size, size = it.size,
            vanillaBase = vanillaBase(it.name, Vanilla.entityBases + listOf("Goal", "Item", "Block", "BlockEntity", "Screen", "EntityRenderer", "EntityModel")),
        )
    }

    /** APIs whose behaviour cannot be carried to Horizon as data, each with why. */
    fun unsupportedApis(): List<ApiUsage> {
        val rules = listOf(
            Triple("org/spongepowered/asm/", "Mixins", "Mixins patch Minecraft's Java classes; Horizon is Rust and has no Java classes to patch"),
            Triple("org/lwjgl/", "Direct LWJGL/OpenGL", "Horizon renders with wgpu/Vulkan; raw GL calls have no equivalent"),
            Triple("com/mojang/blaze3d/", "Blaze3D rendering", "Custom Java rendering pipelines do not exist in Horizon"),
            Triple("java/lang/reflect/", "Reflection", "Reflection on Minecraft internals cannot be translated"),
            Triple("sun/misc/Unsafe", "sun.misc.Unsafe", "Raw memory access cannot be translated"),
            Triple("java/lang/ProcessBuilder", "Process execution", "Starting external processes is never reproduced"),
            Triple("java/lang/Runtime", "Runtime access", "Runtime.exec and similar are never reproduced"),
            Triple("java/net/", "Networking", "Outgoing network connections are never reproduced"),
            Triple("net/minecraftforge/network/", "Forge networking", "Custom packets need a native mod's mod messages (desktop) or are lost (Android)"),
            Triple("net/neoforged/neoforge/network/", "NeoForge networking", "Custom packets need a native mod's mod messages (desktop) or are lost (Android)"),
            Triple("net/fabricmc/fabric/api/networking/", "Fabric networking", "Custom packets need a native mod's mod messages (desktop) or are lost (Android)"),
            Triple("net/fabricmc/fabric/api/client/rendering/", "Fabric client rendering", "Custom HUD/world rendering needs native render hooks (desktop only)"),
            Triple("net/minecraft/client/renderer/", "Custom Java renderers", "Entity/block renderers are Java; reconstructed from model data where possible"),
            Triple("net/minecraft/class_4587", "Custom Java renderers (intermediary)", "Entity/block renderers are Java; reconstructed from model data where possible"),
            Triple("org/objectweb/asm/", "Runtime bytecode generation", "ASM transformers rewrite Java classes; not translatable"),
            Triple("cpw/mods/modlauncher/", "ModLauncher transformers", "Coremods rewrite Java classes; not translatable"),
            Triple("com/mojang/brigadier/", "Commands (Brigadier)", "Commands need a native mod (desktop) or a WASM mod's command hook (Android)"),
            Triple("net/minecraft/client/KeyMapping", "Key bindings", "Key bindings need a native or WASM client mod"),
            Triple("net/minecraft/client/gui/screens/", "Custom screens", "Java GUI screens are not reproduced as data"),
        )
        return rules.mapNotNull { (prefix, api, why) ->
            val users = headers.values.filter { h -> h.references.any { it.startsWith(prefix) } }.map { it.name.replace('/', '.') }
            if (users.isEmpty()) null else ApiUsage(api, users.take(50), why)
        }
    }

    private fun readHeader(bytes: ByteArray, path: String, size: Long): ClassHeader {
        val methods = ArrayList<Pair<String, String>>()
        val fields = ArrayList<Pair<String, String>>()
        val refs = HashSet<String>()
        val strings = ArrayList<String>()
        var name = ""
        var superName: String? = null
        var interfaces = emptyList<String>()
        var access = 0
        val mv = object : MethodVisitor(Opcodes.ASM9) {
            override fun visitMethodInsn(opcode: Int, owner: String, n: String, d: String, itf: Boolean) {
                if (refs.size < 4096) { refs += owner; refs += "$owner.$n" }
            }
            override fun visitFieldInsn(opcode: Int, owner: String, n: String, d: String) {
                if (refs.size < 4096) { refs += owner; refs += "$owner.$n" }
            }
            override fun visitTypeInsn(opcode: Int, type: String) { if (refs.size < 4096) refs += type }
            override fun visitLdcInsn(value: Any?) {
                if (value is String && strings.size < 512 && value.length < 512) strings += value
                if (value is org.objectweb.asm.Type && refs.size < 4096) refs += value.internalName
            }
        }
        ClassReader(bytes).accept(object : ClassVisitor(Opcodes.ASM9) {
            override fun visit(version: Int, acc: Int, n: String, sig: String?, sup: String?, ifs: Array<out String>?) {
                name = n; superName = sup; interfaces = ifs?.toList() ?: emptyList(); access = acc
            }
            override fun visitMethod(acc: Int, n: String, d: String, sig: String?, ex: Array<out String>?): MethodVisitor {
                methods += n to d
                return mv
            }
            override fun visitField(acc: Int, n: String, d: String, sig: String?, value: Any?): FieldVisitor? {
                fields += n to d
                if (value is String && strings.size < 512) strings += value
                return null
            }
        }, ClassReader.SKIP_FRAMES or ClassReader.SKIP_DEBUG)
        return ClassHeader(name, superName, interfaces, methods, fields, size, refs, strings, path, access)
    }
}
