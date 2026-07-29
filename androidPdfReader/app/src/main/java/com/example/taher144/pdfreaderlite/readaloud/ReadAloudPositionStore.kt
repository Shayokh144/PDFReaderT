package com.example.taher144.pdfreaderlite.readaloud

import android.content.Context

/**
 * Persists last read-aloud position so playback can resume after the OS kills the service.
 */
class ReadAloudPositionStore(
    context: Context
) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(documentId: String, pageIndex: Int, chunkIndex: Int) {
        prefs.edit()
            .putString(KEY_DOCUMENT_ID, documentId)
            .putInt(KEY_PAGE_INDEX, pageIndex)
            .putInt(KEY_CHUNK_INDEX, chunkIndex)
            .apply()
    }

    fun load(documentId: String): Pair<Int, Int>? {
        if (prefs.getString(KEY_DOCUMENT_ID, null) != documentId) return null
        val page = prefs.getInt(KEY_PAGE_INDEX, 0)
        val chunk = prefs.getInt(KEY_CHUNK_INDEX, 0)
        return page to chunk
    }

    fun hasSavedPosition(documentId: String): Boolean = load(documentId) != null

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREFS_NAME = "read_aloud_position"
        private const val KEY_DOCUMENT_ID = "document_id"
        private const val KEY_PAGE_INDEX = "page_index"
        private const val KEY_CHUNK_INDEX = "chunk_index"
    }
}
