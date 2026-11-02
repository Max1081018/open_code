package com.example.camera.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoEnhanceTest {

    private fun solid(argb: Int, count: Int = 400): IntArray = IntArray(count) { argb }

    @Test
    fun stats_reportsDarkImageAsDark() {
        val stats = AutoEnhance.stats(solid(0xFF101010.toInt()))
        assertTrue(stats.meanLuma < 0.15f)
        assertEquals(0f, stats.warmth, 0.01f)
    }

    @Test
    fun stats_handlesEmptyInput() {
        val stats = AutoEnhance.stats(IntArray(0))
        assertEquals(0.5f, stats.meanLuma, 0.0001f)
    }

    @Test
    fun suggest_brightensDarkPhotos() {
        val params = AutoEnhance.suggest(AutoEnhance.stats(solid(0xFF181818.toInt())))
        assertTrue("dark photo should gain exposure", params.exposure > 0.3f)
    }

    @Test
    fun suggest_darkensBlownOutPhotos() {
        val params = AutoEnhance.suggest(AutoEnhance.stats(solid(0xFFF0F0F0.toInt())))
        assertTrue("bright photo should lose exposure", params.exposure < 0f)
    }

    @Test
    fun suggest_addsContrastToFlatImages() {
        val flat = AutoEnhance.suggest(AutoEnhance.stats(solid(0xFF808080.toInt())))
        val contrasty = AutoEnhance.suggest(
            AutoEnhance.stats(
                IntArray(400) { i -> if (i % 2 == 0) 0xFF000000.toInt() else 0xFFFFFFFF.toInt() }
            )
        )
        assertTrue(flat.contrast > contrasty.contrast)
    }

    @Test
    fun suggest_alwaysEnablesTastefulDefaults() {
        val params = AutoEnhance.suggest(ImageStats(0.5f, 0.4f, 0f))
        assertTrue(params.hdr)
        assertTrue(params.beauty)
        assertTrue(params.sharpen > 0f)
    }

    @Test
    fun suggest_staysInsideSliderRanges() {
        val extremeDark = AutoEnhance.suggest(ImageStats(0f, 0f, -1f))
        val extremeBright = AutoEnhance.suggest(ImageStats(1f, 1f, 1f))
        for (p in listOf(extremeDark, extremeBright)) {
            assertTrue(p.exposure in -1f..1f)
            assertTrue(p.contrast in -1f..1f)
            assertTrue(p.saturation in -1f..1f)
            assertTrue(p.warmth in -1f..1f)
        }
    }
}
