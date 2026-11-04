package com.example.camera.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LooksTest {

    @Test
    fun everyFilterHasALook() {
        assertEquals(28, FilterId.values().size)
        for (id in FilterId.values()) {
            assertNotNull(Looks.of(id))
        }
    }

    @Test
    fun originalIsIdentity() {
        assertEquals(Looks.IDENTITY, Looks.of(FilterId.ORIGINAL))
    }

    @Test
    fun noirIsFullyDesaturated() {
        assertEquals(-1f, Looks.of(FilterId.NOIR).saturation, 0.0001f)
    }

    @Test
    fun sunsetIsTheWarmestLook() {
        val sunset = Looks.of(FilterId.SUNSET).warmth
        for (id in FilterId.values()) {
            assertTrue(sunset >= Looks.of(id).warmth)
        }
    }

    @Test
    fun defaultParamsAreIdentity() {
        assertTrue(EditParams().isIdentity)
    }

    @Test
    fun anyEditBreaksIdentity() {
        assertFalse(EditParams(filter = FilterId.LARK).isIdentity)
        assertFalse(EditParams(exposure = 0.1f).isIdentity)
        assertFalse(EditParams(night = true).isIdentity)
        assertFalse(EditParams(portrait = true).isIdentity)
    }

    @Test
    fun resetAdjustmentsKeepsFilterButClearsSliders() {
        val edited = EditParams(
            filter = FilterId.JUNO,
            exposure = 0.4f,
            contrast = 0.2f,
            saturation = 0.3f,
            warmth = 0.1f,
            sharpen = 0.5f,
            night = true,
            hdr = true,
            beauty = true,
            portrait = true,
            relight = true
        )
        val reset = edited.resetAdjustments()
        assertEquals(FilterId.JUNO, reset.filter)
        assertEquals(0f, reset.exposure, 0.0001f)
        assertEquals(0f, reset.sharpen, 0.0001f)
        assertFalse(reset.night)
        assertFalse(reset.hdr)
        assertFalse(reset.beauty)
        assertFalse(reset.portrait)
        assertFalse(reset.relight)
    }
}
