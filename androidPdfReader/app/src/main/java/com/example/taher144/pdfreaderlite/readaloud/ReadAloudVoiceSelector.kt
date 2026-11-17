package com.example.taher144.pdfreaderlite.readaloud

import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import java.util.Locale

/**
 * Evaluates and selects the highest quality on-device (offline) voice available from the device's
 * [TextToSpeech] engine for a given target [Locale].
 */
object ReadAloudVoiceSelector {

    /**
     * Selects the best on-device [Voice] from [voices] matching [targetLocale].
     *
     * Strict requirements:
     * - Must not require network connection ([Voice.isNetworkConnectionRequired] == false) to ensure
     *   smooth, offline playback without network calls.
     * - Must not have [TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED] in its features.
     * - Must match the language of [targetLocale].
     *
     * Ranking preferences:
     * 1. Matching country/region (e.g. US).
     * 2. Stated voice quality ([Voice.QUALITY_VERY_HIGH], [Voice.QUALITY_HIGH], etc.).
     * 3. Neural/natural voice naming heuristics (Google offline neural packs).
     * 4. Latency score (tiebreaker).
     *
     * Returns null if no eligible on-device voice is found, allowing the system default to remain.
     */
    fun selectBestVoice(
        voices: Collection<Voice>?,
        targetLocale: Locale = Locale.US
    ): Voice? {
        if (voices.isNullOrEmpty()) return null

        val candidates = voices.filter { voice ->
            !voice.isNetworkConnectionRequired &&
                !voice.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) &&
                voice.locale.language.equals(targetLocale.language, ignoreCase = true)
        }

        if (candidates.isEmpty()) return null

        return candidates.maxByOrNull { voice -> scoreVoice(voice, targetLocale) }
    }

    internal fun scoreVoice(voice: Voice, targetLocale: Locale): Int {
        var score = 0

        // 1. Regional match (e.g., en-US vs en-GB when US is requested)
        if (targetLocale.country.isNotEmpty() &&
            voice.locale.country.equals(targetLocale.country, ignoreCase = true)
        ) {
            score += 1000
        }

        // 2. Official TTS Quality (QUALITY_VERY_HIGH=500, QUALITY_HIGH=400, QUALITY_NORMAL=300)
        score += voice.quality

        // 3. Heuristic bonuses for modern neural / natural voice naming patterns
        val lowerName = voice.name.lowercase(Locale.ROOT)
        if (lowerName.contains("neural")) score += 250
        if (lowerName.contains("natural")) score += 200
        if (lowerName.contains("premium")) score += 150
        if (lowerName.contains("enhanced")) score += 100
        // Google offline voice packs often end with "-local" or have specific quality identifiers
        if (lowerName.contains("local")) score += 50

        // 4. Latency bonus (LATENCY_VERY_LOW=100 ... LATENCY_HIGH=400) -> lower latency gives up to 50 pts
        score += (600 - voice.latency).coerceIn(0, 50)

        return score
    }
}
