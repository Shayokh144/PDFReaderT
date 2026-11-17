package com.example.taher144.pdfreaderlite.readaloud

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

class ReadAloudLanguageDetectorTest {

    @Test
    fun detectLanguage_emptyOrBlank_returnsDefaultLocale() {
        assertEquals(ReadAloudLanguageDetector.DEFAULT_LOCALE, ReadAloudLanguageDetector.detectLanguage(""))
        assertEquals(ReadAloudLanguageDetector.DEFAULT_LOCALE, ReadAloudLanguageDetector.detectLanguage("   \n\t"))
    }

    @Test
    fun detectLanguage_punctuationAndDigitsOnly_returnsDefaultLocale() {
        assertEquals(ReadAloudLanguageDetector.DEFAULT_LOCALE, ReadAloudLanguageDetector.detectLanguage("12345 67890 !?., । ॥"))
    }

    @Test
    fun detectLanguage_pureEnglishText_returnsDefaultLocale() {
        val englishText = "The quick brown fox jumps over the lazy dog. Reading PDFs aloud is wonderful."
        val detected = ReadAloudLanguageDetector.detectLanguage(englishText)
        assertEquals(Locale.US, detected)
    }

    @Test
    fun detectLanguage_pureBengaliText_returnsBengaliLocale() {
        val bengaliText = "আমাদের সোনার বাংলা, আমি তোমায় ভালোবাসি। চিরদিন তোমার আকাশ, তোমার বাতাস।"
        val detected = ReadAloudLanguageDetector.detectLanguage(bengaliText)
        assertEquals("bn", detected.language)
        assertEquals("BD", detected.country)
    }

    @Test
    fun detectLanguage_predominantlyBengaliWithEnglishTitle_returnsBengaliLocale() {
        val mixedText = "Chapter 1: আমাদের সোনার বাংলা, আমি তোমায় ভালোবাসি।"
        val detected = ReadAloudLanguageDetector.detectLanguage(mixedText)
        assertEquals("bn", detected.language)
    }

    @Test
    fun detectLanguage_englishWithMinorityBengaliCitation_returnsEnglishLocale() {
        val englishWithMinorCitation = "This document presents the architecture of the system. Ref: [বাংলা]"
        val detected = ReadAloudLanguageDetector.detectLanguage(englishWithMinorCitation)
        assertEquals(Locale.US, detected)
    }
}
