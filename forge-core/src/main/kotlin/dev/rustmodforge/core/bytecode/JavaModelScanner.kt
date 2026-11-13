package dev.rustmodforge.core.bytecode

import dev.rustmodforge.core.geo.RigBone
import dev.rustmodforge.core.geo.RigCube
import dev.rustmodforge.core.geo.RigModel
import kotlinx.serialization.Serializable
import org.objectweb.asm.Type
import org.objectweb.asm.tree.ClassNode
import org.objectweb.asm.tree.MethodNode

/** A vanilla-style entity model as `createBodyLayer()` builds it, in Java model space. */
@Serializable
data class JavaPart(
    val name: String,
    val parent: String?,
    /** `PartPose` offset (y down) and rotation in radians. */
    val offset: List<Double>,
    val rotation: List<Double>,
    val cubes: List<JavaCube>,
)

@Serializable
data class JavaCube(val u: Int, val v: Int, val origin: List<Double>, val size: List<Double>, val inflate: Double, val mirror: Boolean)

@Serializable
data class JavaLayer(val ownerClass: String, val method: String, val textureWidth: Int, val textureHeight: Int, val parts: List<JavaPart>) {
    /**
     * Converts to Bedrock convention. Java model space is Bedrock's turned 180° about z (y down,
     * x mirrored) and raised 24 pixels, so: x → -x, y → 24 - y, rotations about x and y negate.
     */
    fun toRig(): RigModel {
        val abs = HashMap<String, DoubleArray>()
        fun absOf(p: JavaPart): DoubleArray = abs.getOrPut(p.name) {
            val parent = parts.firstOrNull { it.name == p.parent }?.let { absOf(it) } ?: doubleArrayOf(0.0, 0.0, 0.0)
            doubleArrayOf(parent[0] + p.offset[0], parent[1] + p.offset[1], parent[2] + p.offset[2])
        }
        val bones = parts.map { p ->
            val a = absOf(p)
            RigBone(
                name = p.name, parent = p.parent?.takeIf { it != "root" },
                pivot = listOf(-a[0], 24 - a[1], a[2]),
                rotation = listOf(-Math.toDegrees(p.rotation[0]), -Math.toDegrees(p.rotation[1]), Math.toDegrees(p.rotation[2])),
                cubes = p.cubes.map { c ->
                    RigCube(
                        origin = listOf(-(a[0] + c.origin[0] + c.size[0]), 24 - (a[1] + c.origin[1] + c.size[1]), a[2] + c.origin[2]),
                        size = c.size, inflate = c.inflate, mirror = c.mirror, boxUv = listOf(c.u.toDouble(), c.v.toDouble()),
                    )
                },
            )
        }.filter { it.name != "root" }
        return RigModel("java.${ownerClass.substringAfterLast('/')}", textureWidth, textureHeight, bones, "java:$ownerClass.$method")
    }
}

/**
 * Extracts `createBodyLayer()`-style models from bytecode: the sequence of
 * `addOrReplaceChild(name, CubeListBuilder.create().texOffs(u, v).addBox(...), PartPose...)`
 * calls and `LayerDefinition.create(mesh, w, h)`. Only literal constants are read; a model
 * computed in loops is reported as not extractable.
 */
object JavaModelScanner {
    private val layerReturns = setOf("net/minecraft/client/model/geom/builders/LayerDefinition", "net/minecraft/class_5607",
        "net/minecraft/client/model/TexturedModelData")

    fun scan(node: ClassNode): List<JavaLayer> = node.methods.filter { m ->
        Type.getReturnType(m.desc).let { it.sort == Type.OBJECT && it.internalName in layerReturns }
    }.mapNotNull { scanMethod(node.name, it) }

    private fun scanMethod(owner: String, m: MethodNode): JavaLayer? {
        val ev = Events.of(m)
        val varPart = HashMap<Int, String>()
        val parts = ArrayList<JavaPart>()
        var texW = 64; var texH = 64
        var segmentStart = 0
        for ((i, e) in ev.withIndex()) {
            if (e is Ev.Invoke && Vanilla.isMethod("addOrReplaceChild", e.name) && e.argCount == 3) {
                val seg = ev.subList(segmentStart, i)
                segmentStart = i + 1
                val nameIdx = seg.indexOfFirst { it is Ev.Str }
                if (nameIdx < 0) continue
                val name = (seg[nameIdx] as Ev.Str).value
                val parentVar = (seg.getOrNull(nameIdx - 1) as? Ev.Load)?.index
                val parent = parentVar?.let { varPart[it] } ?: "root"
                val cubes = ArrayList<JavaCube>()
                var u = 0; var v = 0; var mirror = false
                var last = nameIdx + 1
                for ((j, s) in seg.withIndex()) {
                    if (j <= nameIdx || s !is Ev.Invoke) continue
                    val nums = Events.numbersBetween(seg, last, j)
                    when {
                        Vanilla.isMethod("texOffs", s.name) && nums.size >= 2 -> { u = nums[nums.size - 2].toInt(); v = nums.last().toInt() }
                        s.name == "mirror" || s.name == "m_171555_" || s.name == "method_32106" -> mirror = s.argCount == 0 || nums.lastOrNull() != 0.0
                        Vanilla.isMethod("addBox", s.name) && nums.size >= 6 -> {
                            val k = nums.size - (if (nums.size >= 7) 7 else 6)
                            val box = nums.subList(k, k + 6)
                            val inflate = if (nums.size >= 7) nums.last() else 0.0
                            cubes += JavaCube(u, v, box.subList(0, 3), box.subList(3, 6), inflate, mirror)
                        }
                        else -> {}
                    }
                    if (Vanilla.isMethod("texOffs", s.name) || Vanilla.isMethod("addBox", s.name)) last = j + 1
                }
                val poseIdx = seg.indexOfLast { it is Ev.Invoke && (Vanilla.isMethod("partOffset", it.name) || Vanilla.isMethod("partOffsetAndRotation", it.name)) && it.owner.contains("PartPose") || (it is Ev.Invoke && it.owner == "net/minecraft/class_5603") }
                var offset = listOf(0.0, 0.0, 0.0); var rotation = listOf(0.0, 0.0, 0.0)
                if (poseIdx >= 0) {
                    val call = seg[poseIdx] as Ev.Invoke
                    val nums = Events.numbersBetween(seg, (poseIdx - 14).coerceAtLeast(last), poseIdx)
                    if (call.argCount == 6 && nums.size >= 6) { val n = nums.takeLast(6); offset = n.subList(0, 3); rotation = n.subList(3, 6) }
                    else if (call.argCount == 3 && nums.size >= 3) offset = nums.takeLast(3)
                }
                parts += JavaPart(name, parent, offset, rotation, cubes)
                (ev.getOrNull(i + 1) as? Ev.Store)?.let { varPart[it.index] = name }
            }
            if (e is Ev.Invoke && Vanilla.isMethod("layerCreate", e.name) && e.argCount == 3 && e.owner in layerReturns) {
                val nums = Events.numbersBetween(ev, i - 3, i)
                if (nums.size >= 2) { texW = nums[nums.size - 2].toInt(); texH = nums.last().toInt() }
            }
            // The mesh's root: `PartDefinition root = mesh.getRoot();`
            if (e is Ev.Invoke && (e.name == "getRoot" || e.name == "m_171576_" || e.name == "method_32111")) {
                (ev.getOrNull(i + 1) as? Ev.Store)?.let { varPart[it.index] = "root" }
            }
        }
        if (parts.isEmpty()) return null
        return JavaLayer(owner, m.name, texW, texH, parts)
    }
}
