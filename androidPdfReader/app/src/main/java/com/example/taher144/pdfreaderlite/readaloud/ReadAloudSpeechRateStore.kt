package com.example.taher144.pdfreaderlite.readaloud

import android.content.Context

/**
 * Persists the user's Read Aloud speech rate. Default is [DEFAULT_RATE] (slightly slower than
 * system normal 1.0).
 */
class ReadAloudSpeechRateStore(
    context: Context
) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getRate(): Float {
        val stored = prefs.getFloat(KEY_SPEECH_RATE, DEFAULT_RATE)
        return stored.coerceIn(MIN_RATE, MAX_RATE)
    }

    fun setRate(rate: Float) {
        prefs.edit()
            .putFloat(KEY_SPEECH_RATE, rate.coerceIn(MIN_RATE, MAX_RATE))
            .apply()
    }

    companion object {
        const val DEFAULT_RATE = 0.85f
        const val MIN_RATE = 0.5f
        const val MAX_RATE = 1.5f

        /** Preset rates offered in the speed picker (includes [DEFAULT_RATE]). */
        val PRESET_RATES = floatArrayOf(0.5f, 0.75f, 0.85f, 1.0f, 1.25f, 1.5f)

        private const val PREFS_NAME = "read_aloud_speech_rate"
        private const val KEY_SPEECH_RATE = "speech_rate"
    }
}
