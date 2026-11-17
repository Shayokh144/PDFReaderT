package com.example.taher144.pdfreaderlite.readaloud

import java.util.Locale

/**
 * Detects the dominant language for a given text snippet to select the appropriate TTS voice.
 * Supports English and Bengali on-device using Unicode block inspection without external ML models.
 */
object ReadAloudLanguageDetector {

    val BENGALI_LOCALE: Locale = Locale.forLanguageTag("bn-BD")
    val DEFAULT_LOCALE: Locale = Locale.US

    /**
     * Determines whether [text] is predominantly Bengali or English (default).
     *
     * Inspects Unicode code points:
     * - Bengali characters reside in `\u0980`..`\u09FF`.
     * - Latin characters reside in standard ASCII a-z / A-Z.
     */
    fun detectLanguage(text: String): Locale {
        if (text.isBlank()) return DEFAULT_LOCALE

        var bengaliCount = 0
        var latinCount = 0

        for (char in text) {
            when {
                char in '\u0980'..'\u09FF' -> bengaliCount++
                char in 'a'..'z' || char in 'A'..'Z' -> latinCount++
            }
        }

        val totalLetters = bengaliCount + latinCount
        if (totalLetters == 0) return DEFAULT_LOCALE

        // If Bengali outnumbers Latin, or accounts for at least 30% of total alphabetic chars:
        return if (bengaliCount >= latinCount || (bengaliCount.toDouble() / totalLetters) >= 0.3) {
            BENGALI_LOCALE
        } else {
            DEFAULT_LOCALE
        }
    }
}
