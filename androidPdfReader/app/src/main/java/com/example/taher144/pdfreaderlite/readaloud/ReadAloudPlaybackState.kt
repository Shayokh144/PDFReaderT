package com.example.taher144.pdfreaderlite.readaloud

sealed class ReadAloudPlaybackState {
    data object Idle : ReadAloudPlaybackState()

    data class Preparing(
        val documentId: String,
        val title: String
    ) : ReadAloudPlaybackState()

    data class Playing(
        val documentId: String,
        val title: String,
        val currentPage: Int,
        val totalPages: Int
    ) : ReadAloudPlaybackState()

    data class Paused(
        val documentId: String,
        val title: String,
        val currentPage: Int,
        val totalPages: Int
    ) : ReadAloudPlaybackState()

    data class Error(
        val reason: Reason,
        val documentId: String? = null
    ) : ReadAloudPlaybackState() {
        enum class Reason {
            NO_TEXT,
            TTS_UNAVAILABLE,
            LANGUAGE_UNSUPPORTED,
            OPEN_FAILED
        }
    }

    val isActive: Boolean
        get() = this is Preparing || this is Playing || this is Paused

    val documentIdOrNull: String?
        get() = when (this) {
            is Preparing -> documentId
            is Playing -> documentId
            is Paused -> documentId
            is Error -> documentId
            Idle -> null
        }
}
