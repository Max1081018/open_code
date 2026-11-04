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

    @Test
    fun suggest_foodBoostsSaturation() {
        val stats = ImageStats(meanLuma = 0.5f, averageDeviation = 0.2f, warmth = 0f, saturation = 0.6f)
        val scene = AutoEnhance.classify(stats, emptyList())
        val params = AutoEnhance.suggest(stats, scene)
        assertEquals(Scene.FOOD, scene)
        assertTrue("food should lift saturation", params.saturation > 0.24f)
    }

    @Test
    fun suggest_sunsetBoostsWarmth() {
        val params = AutoEnhance.suggest(ImageStats(0.5f, 0.3f, -0.25f), Scene.SUNSET)
        assertTrue("golden hour should push warmth", params.warmth > 0.1f)
    }

    @Test
    fun suggest_nightBoostsDenoiseAndLiftShadows() {
        val params = AutoEnhance.suggest(ImageStats(0.08f, 0.1f, 0.05f), Scene.NIGHT)
        assertTrue("night should switch the boost on", params.night)
        assertTrue("night should denoise harder", params.denoise > 0.4f)
    }
}
