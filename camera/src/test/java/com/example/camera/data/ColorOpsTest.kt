package com.example.camera.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ColorOpsTest {

    @Test
    fun clamp01_pinsOutOfRangeValues() {
        assertEquals(0f, ColorOps.clamp01(-0.4f), 0.0001f)
        assertEquals(1f, ColorOps.clamp01(3f), 0.0001f)
        assertEquals(0.42f, ColorOps.clamp01(0.42f), 0.0001f)
    }

    @Test
    fun luma_matchesRec709Weights() {
        assertEquals(1f, ColorOps.luma(1f, 1f, 1f), 0.0001f)
        assertEquals(0f, ColorOps.luma(0f, 0f, 0f), 0.0001f)
        assertEquals(0.7152f, ColorOps.luma(0f, 1f, 0f), 0.0001f)
    }

    @Test
    fun contrast_leavesMidGreyAlone() {
        assertEquals(0.5f, ColorOps.contrast(0.5f, 0.8f), 0.0001f)
    }

    @Test
    fun contrast_pushesValuesAwayFromMidGrey() {
        val dark = ColorOps.contrast(0.2f, 0.5f)
        val light = ColorOps.contrast(0.8f, 0.5f)
        assertTrue(dark < 0.2f)
        assertTrue(light > 0.8f)
    }

    @Test
    fun lift_onlyRaisesValues() {
        assertTrue(ColorOps.lift(0.1f, 0.2f) > 0.1f)
        assertEquals(1f, ColorOps.lift(1f, 0.2f), 0.0001f)
    }

    @Test
    fun saturate_minusOne_producesGrey() {
        val out = ColorOps.saturate(0.9f, 0.2f, 0.1f, -1f)
        assertEquals(out[0], out[1], 0.0001f)
        assertEquals(out[1], out[2], 0.0001f)
    }

    @Test
    fun saturate_zero_isIdentity() {
        val out = ColorOps.saturate(0.3f, 0.6f, 0.9f, 0f)
        assertEquals(0.3f, out[0], 0.0001f)
        assertEquals(0.6f, out[1], 0.0001f)
        assertEquals(0.9f, out[2], 0.0001f)
    }

    @Test
    fun shoulder_isMonotonicAndPinned() {
        assertEquals(0f, ColorOps.shoulder(0f), 0.0001f)
        assertEquals(1f, ColorOps.shoulder(1f), 0.0001f)
        var previous = -1f
        var v = 0f
        while (v <= 1f) {
            val s = ColorOps.shoulder(v)
            assertTrue("shoulder must not decrease at $v", s >= previous - 0.0001f)
            previous = s
            v += 0.05f
        }
    }

    @Test
    fun shoulder_keepsHighlightDetail() {
        assertTrue(ColorOps.shoulder(0.95f) < 0.95f)
        assertTrue(ColorOps.shoulder(0.95f) > 0.9f)
    }

    @Test
    fun pack_producesOpaqueArgb() {
        val packed = ColorOps.pack(1f, 1f, 1f)
        assertEquals(0xFF, (packed shr 24) and 0xFF)
        assertEquals(255, (packed shr 16) and 0xFF)
        assertEquals(255, packed and 0xFF)
    }
}
