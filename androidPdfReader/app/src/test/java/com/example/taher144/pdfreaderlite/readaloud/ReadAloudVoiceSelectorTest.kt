package com.example.taher144.pdfreaderlite.readaloud

import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReadAloudVoiceSelectorTest {

    @Test
    fun selectBestVoice_returnsNullWhenVoicesNullOrEmpty() {
        assertNull(ReadAloudVoiceSelector.selectBestVoice(null))
        assertNull(ReadAloudVoiceSelector.selectBestVoice(emptyList()))
    }

    @Test
    fun selectBestVoice_filtersOutNetworkRequiredVoices() {
        val networkVoice = Voice(
            "en-us-x-sfg-network",
            Locale.US,
            Voice.QUALITY_VERY_HIGH,
            Voice.LATENCY_NORMAL,
            true, // requires network
            emptySet()
        )
        val result = ReadAloudVoiceSelector.selectBestVoice(listOf(networkVoice), Locale.US)
        assertNull("Network-requiring voices should be filtered out", result)
    }

    @Test
    fun selectBestVoice_filtersOutUninstalledVoices() {
        val uninstalledVoice = Voice(
            "en-us-x-sfg-local",
            Locale.US,
            Voice.QUALITY_VERY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            setOf(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
        )
        val result = ReadAloudVoiceSelector.selectBestVoice(listOf(uninstalledVoice), Locale.US)
        assertNull("Uninstalled voices should be filtered out", result)
    }

    @Test
    fun selectBestVoice_filtersOutNonMatchingLanguage() {
        val frenchVoice = Voice(
            "fr-fr-x-standard",
            Locale.FRANCE,
            Voice.QUALITY_VERY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            emptySet()
        )
        val result = ReadAloudVoiceSelector.selectBestVoice(listOf(frenchVoice), Locale.US)
        assertNull("Non-matching language should be filtered out", result)
    }

    @Test
    fun selectBestVoice_prefersHighQualityAndNeuralOverStandard() {
        val roboticStandard = Voice(
            "en-us-standard",
            Locale.US,
            Voice.QUALITY_NORMAL,
            Voice.LATENCY_LOW,
            false,
            emptySet()
        )
        val neuralVoice = Voice(
            "en-us-neural-local",
            Locale.US,
            Voice.QUALITY_VERY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            emptySet()
        )
        val candidates = listOf(roboticStandard, neuralVoice)
        val selected = ReadAloudVoiceSelector.selectBestVoice(candidates, Locale.US)

        assertNotNull(selected)
        assertEquals("en-us-neural-local", selected?.name)
    }

    @Test
    fun selectBestVoice_prefersMatchingCountryWhenQualityIsEqual() {
        val gbVoice = Voice(
            "en-gb-local",
            Locale.UK,
            Voice.QUALITY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            emptySet()
        )
        val usVoice = Voice(
            "en-us-local",
            Locale.US,
            Voice.QUALITY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            emptySet()
        )
        val selected = ReadAloudVoiceSelector.selectBestVoice(listOf(gbVoice, usVoice), Locale.US)

        assertNotNull(selected)
        assertEquals("en-us-local", selected?.name)
    }

    @Test
    fun selectBestVoice_selectsBengaliVoiceForBengaliLocale() {
        val bengaliVoiceBd = Voice(
            "bn-bd-x-ban-local",
            Locale.forLanguageTag("bn-BD"),
            Voice.QUALITY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            emptySet()
        )
        val englishVoice = Voice(
            "en-us-neural-local",
            Locale.US,
            Voice.QUALITY_VERY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            emptySet()
        )
        val selected = ReadAloudVoiceSelector.selectBestVoice(
            listOf(englishVoice, bengaliVoiceBd),
            Locale.forLanguageTag("bn-BD")
        )

        assertNotNull(selected)
        assertEquals("bn-bd-x-ban-local", selected?.name)
    }

    @Test
    fun selectBestVoice_prefersBengaliBdOverBengaliInWhenBdRequested() {
        val bengaliIn = Voice(
            "bn-in-x-cbf-local",
            Locale.forLanguageTag("bn-IN"),
            Voice.QUALITY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            emptySet()
        )
        val bengaliBd = Voice(
            "bn-bd-x-ban-local",
            Locale.forLanguageTag("bn-BD"),
            Voice.QUALITY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            emptySet()
        )
        val selected = ReadAloudVoiceSelector.selectBestVoice(
            listOf(bengaliIn, bengaliBd),
            Locale.forLanguageTag("bn-BD")
        )

        assertNotNull(selected)
        assertEquals("bn-bd-x-ban-local", selected?.name)
    }
}
