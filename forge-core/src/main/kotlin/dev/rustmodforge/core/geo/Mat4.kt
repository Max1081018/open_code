package dev.rustmodforge.core.geo

import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** Row-major 4×4 affine matrix: just what bone transforms and display transformations need. */
class Mat4(val m: DoubleArray = identity()) {
    operator fun times(o: Mat4): Mat4 {
        val r = DoubleArray(16)
        for (i in 0 until 4) for (j in 0 until 4) {
            var s = 0.0
            for (k in 0 until 4) s += m[i * 4 + k] * o.m[k * 4 + j]
            r[i * 4 + j] = s
        }
        return Mat4(r)
    }

    fun apply(p: DoubleArray): DoubleArray = DoubleArray(3) { i -> m[i * 4] * p[0] + m[i * 4 + 1] * p[1] + m[i * 4 + 2] * p[2] + m[i * 4 + 3] }

    companion object {
        fun identity() = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)
        fun translate(x: Double, y: Double, z: Double) = Mat4(doubleArrayOf(1.0, 0.0, 0.0, x, 0.0, 1.0, 0.0, y, 0.0, 0.0, 1.0, z, 0.0, 0.0, 0.0, 1.0))
        fun scale(x: Double, y: Double, z: Double) = Mat4(doubleArrayOf(x, 0.0, 0.0, 0.0, 0.0, y, 0.0, 0.0, 0.0, 0.0, z, 0.0, 0.0, 0.0, 0.0, 1.0))
        fun rotX(deg: Double): Mat4 { val a = Math.toRadians(deg); val c = cos(a); val s = sin(a)
            return Mat4(doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, c, -s, 0.0, 0.0, s, c, 0.0, 0.0, 0.0, 0.0, 1.0)) }
        fun rotY(deg: Double): Mat4 { val a = Math.toRadians(deg); val c = cos(a); val s = sin(a)
            return Mat4(doubleArrayOf(c, 0.0, s, 0.0, 0.0, 1.0, 0.0, 0.0, -s, 0.0, c, 0.0, 0.0, 0.0, 0.0, 1.0)) }
        fun rotZ(deg: Double): Mat4 { val a = Math.toRadians(deg); val c = cos(a); val s = sin(a)
            return Mat4(doubleArrayOf(c, -s, 0.0, 0.0, s, c, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)) }
        /** Bedrock/Blockbench Euler order: Z, then Y, then X (matrix Rz·Ry·Rx). */
        fun rotZYX(deg: DoubleArray) = rotZ(deg[2]) * rotY(deg[1]) * rotX(deg[0])
    }
}

/** Unit quaternion [x, y, z, w]. */
data class Quat(val x: Double, val y: Double, val z: Double, val w: Double) {
    operator fun times(o: Quat) = Quat(
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
        w * o.w - x * o.x - y * o.y - z * o.z,
    )

    fun normalized(): Quat { val n = sqrt(x * x + y * y + z * z + w * w); return if (n == 0.0) IDENTITY else Quat(x / n, y / n, z / n, w / n) }

    companion object {
        val IDENTITY = Quat(0.0, 0.0, 0.0, 1.0)
        fun axis(ax: Double, ay: Double, az: Double, deg: Double): Quat {
            val h = Math.toRadians(deg) / 2
            val s = sin(h)
            return Quat(ax * s, ay * s, az * s, cos(h))
        }
        /** The same rotation as [Mat4.rotZYX]. */
        fun zyx(deg: DoubleArray) = axis(0.0, 0.0, 1.0, deg[2]) * axis(0.0, 1.0, 0.0, deg[1]) * axis(1.0, 0.0, 0.0, deg[0])
    }
}
