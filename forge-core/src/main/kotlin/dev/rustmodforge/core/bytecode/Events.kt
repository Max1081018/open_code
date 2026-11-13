package dev.rustmodforge.core.bytecode

import org.objectweb.asm.Handle
import org.objectweb.asm.Opcodes
import org.objectweb.asm.Type
import org.objectweb.asm.tree.AbstractInsnNode
import org.objectweb.asm.tree.FieldInsnNode
import org.objectweb.asm.tree.IincInsnNode
import org.objectweb.asm.tree.InsnNode
import org.objectweb.asm.tree.IntInsnNode
import org.objectweb.asm.tree.InvokeDynamicInsnNode
import org.objectweb.asm.tree.JumpInsnNode
import org.objectweb.asm.tree.LdcInsnNode
import org.objectweb.asm.tree.MethodInsnNode
import org.objectweb.asm.tree.MethodNode
import org.objectweb.asm.tree.TypeInsnNode
import org.objectweb.asm.tree.VarInsnNode

/**
 * A method body flattened to the instructions the analysers care about, in order. Pattern
 * matching over this is how constants (an entity's size, a goal's speed, an attribute's value)
 * are tied to the calls that use them, without executing anything.
 */
sealed class Ev {
    data class Num(val value: Double, val isInt: Boolean) : Ev()
    data class Str(val value: String) : Ev()
    data class Cls(val type: String) : Ev()
    data class GetStatic(val owner: String, val name: String, val desc: String) : Ev()
    data class GetField(val owner: String, val name: String, val desc: String) : Ev()
    data class PutStatic(val owner: String, val name: String, val desc: String) : Ev()
    data class PutField(val owner: String, val name: String, val desc: String) : Ev()
    data class New(val type: String) : Ev()
    data class Invoke(val opcode: Int, val owner: String, val name: String, val desc: String) : Ev() {
        val argCount get() = Type.getArgumentTypes(desc).size
        val isStatic get() = opcode == Opcodes.INVOKESTATIC
        val returnType: String get() = Type.getReturnType(desc).let { if (it.sort == Type.OBJECT) it.internalName else it.descriptor }
    }
    /** A lambda or method reference: the implementation method it points at. */
    data class Indy(val name: String, val impl: Handle?) : Ev()
    data class Load(val index: Int) : Ev()
    data class Store(val index: Int) : Ev()
    data class Compare(val opcode: Int) : Ev()
    object Return : Ev()
    object Neg : Ev()
    object Mul : Ev()
}

object Events {
    fun of(method: MethodNode): List<Ev> {
        val out = ArrayList<Ev>(method.instructions.size())
        for (insn in method.instructions) toEv(insn)?.let { out += it }
        return out
    }

    private fun toEv(insn: AbstractInsnNode): Ev? = when (insn) {
        is InsnNode -> when (val op = insn.opcode) {
            in Opcodes.ICONST_M1..Opcodes.ICONST_5 -> Ev.Num((op - Opcodes.ICONST_0).toDouble(), true)
            Opcodes.LCONST_0, Opcodes.LCONST_1 -> Ev.Num((op - Opcodes.LCONST_0).toDouble(), true)
            Opcodes.FCONST_0, Opcodes.FCONST_1, Opcodes.FCONST_2 -> Ev.Num((op - Opcodes.FCONST_0).toDouble(), false)
            Opcodes.DCONST_0, Opcodes.DCONST_1 -> Ev.Num((op - Opcodes.DCONST_0).toDouble(), false)
            Opcodes.IRETURN, Opcodes.LRETURN, Opcodes.FRETURN, Opcodes.DRETURN, Opcodes.ARETURN, Opcodes.RETURN -> Ev.Return
            Opcodes.FNEG, Opcodes.DNEG, Opcodes.INEG, Opcodes.LNEG -> Ev.Neg
            Opcodes.FMUL, Opcodes.DMUL, Opcodes.IMUL -> Ev.Mul
            Opcodes.FCMPG, Opcodes.FCMPL, Opcodes.DCMPG, Opcodes.DCMPL, Opcodes.LCMP -> Ev.Compare(op)
            else -> null
        }
        is IntInsnNode -> if (insn.opcode == Opcodes.BIPUSH || insn.opcode == Opcodes.SIPUSH) Ev.Num(insn.operand.toDouble(), true) else null
        is LdcInsnNode -> when (val v = insn.cst) {
            is Int -> Ev.Num(v.toDouble(), true)
            is Long -> Ev.Num(v.toDouble(), true)
            is Float -> Ev.Num(v.toString().toDouble(), false)
            is Double -> Ev.Num(v, false)
            is String -> Ev.Str(v)
            is Type -> Ev.Cls(v.internalName)
            else -> null
        }
        is FieldInsnNode -> when (insn.opcode) {
            Opcodes.GETSTATIC -> Ev.GetStatic(insn.owner, insn.name, insn.desc)
            Opcodes.GETFIELD -> Ev.GetField(insn.owner, insn.name, insn.desc)
            Opcodes.PUTSTATIC -> Ev.PutStatic(insn.owner, insn.name, insn.desc)
            Opcodes.PUTFIELD -> Ev.PutField(insn.owner, insn.name, insn.desc)
            else -> null
        }
        is TypeInsnNode -> if (insn.opcode == Opcodes.NEW) Ev.New(insn.desc) else null
        is MethodInsnNode -> Ev.Invoke(insn.opcode, insn.owner, insn.name, insn.desc)
        is InvokeDynamicInsnNode -> Ev.Indy(insn.name, insn.bsmArgs.filterIsInstance<Handle>().firstOrNull())
        is VarInsnNode -> when (insn.opcode) {
            in Opcodes.ILOAD..Opcodes.ALOAD -> Ev.Load(insn.`var`)
            in Opcodes.ISTORE..Opcodes.ASTORE -> Ev.Store(insn.`var`)
            else -> null
        }
        is JumpInsnNode -> when (insn.opcode) {
            Opcodes.IFLT, Opcodes.IFGT, Opcodes.IFLE, Opcodes.IFGE, Opcodes.IF_ICMPLT, Opcodes.IF_ICMPGT, Opcodes.IF_ICMPLE, Opcodes.IF_ICMPGE -> Ev.Compare(insn.opcode)
            else -> null
        }
        is IincInsnNode -> null
        else -> null
    }

    /** Numbers in [events] between [from] (inclusive) and [to] (exclusive), negation applied. */
    fun numbersBetween(events: List<Ev>, from: Int, to: Int): List<Double> {
        val out = ArrayList<Double>()
        for (i in from.coerceAtLeast(0) until to.coerceAtMost(events.size)) {
            when (val e = events[i]) {
                is Ev.Num -> out += e.value
                is Ev.Neg -> if (out.isNotEmpty()) out[out.lastIndex] = -out.last()
                else -> {}
            }
        }
        return out
    }

    fun fmt(d: Double): String = if (d == Math.floor(d) && !d.isInfinite() && kotlin.math.abs(d) < 1e15) d.toLong().toString() else d.toString()
}
