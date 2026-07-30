package com.example.taher144.pdfreaderlite.data.repository

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.example.taher144.pdfreaderlite.data.model.PdfBookmark
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

/**
 * Persists at most one bookmark per document so it survives app restarts.
 */
interface UserPdfBookmarkRepository {
    suspend fun getBookmark(documentId: String): PdfBookmark?

    /** Replaces any existing bookmark for [bookmark.documentId]. */
    suspend fun setBookmark(bookmark: PdfBookmark)

    suspend fun clearBookmark(documentId: String)
}

class UserPrefsUserPdfBookmarkRepository(
    private val context: Context,
) : UserPdfBookmarkRepository {
    private val mutex = Mutex()
    private var cachedMap: Map<String, String>? = null

    override suspend fun getBookmark(documentId: String): PdfBookmark? {
        if (documentId.isBlank()) return null
        val map = mutex.withLock { ensureMapLoaded() }
        val raw = map[documentId] ?: return null
        return parseBookmark(documentId, raw)
    }

    override suspend fun setBookmark(bookmark: PdfBookmark) {
        if (bookmark.documentId.isBlank()) return
        mutex.withLock {
            val map = ensureMapLoaded().toMutableMap()
            map[bookmark.documentId] = JSONObject().apply {
                put("page", bookmark.pageIndex)
                put("x", bookmark.x.toDouble())
                put("y", bookmark.y.toDouble())
            }.toString()
            cachedMap = map
            saveMap(map)
        }
    }

    override suspend fun clearBookmark(documentId: String) {
        if (documentId.isBlank()) return
        mutex.withLock {
            val map = ensureMapLoaded().toMutableMap()
            if (map.remove(documentId) != null) {
                cachedMap = map
                saveMap(map)
            }
        }
    }

    private suspend fun ensureMapLoaded(): Map<String, String> {
        return cachedMap ?: loadMapFromDisk().also { cachedMap = it }
    }

    private suspend fun loadMapFromDisk(): Map<String, String> {
        return context.pdfReaderDataStore.data.map { preferences ->
            decodeMap(preferences[BookmarkBlobKey].orEmpty())
        }.first()
    }

    private suspend fun saveMap(map: Map<String, String>) {
        context.pdfReaderDataStore.edit { preferences ->
            preferences[BookmarkBlobKey] = encodeMap(map)
        }
    }

    private fun parseBookmark(documentId: String, raw: String): PdfBookmark? {
        if (raw.isBlank()) return null
        return runCatching {
            val o = JSONObject(raw)
            val page = o.optInt("page", -1)
            if (page < 0) return null
            PdfBookmark(
                documentId = documentId,
                pageIndex = page,
                x = o.optDouble("x").toFloat(),
                y = o.optDouble("y").toFloat(),
            )
        }.getOrNull()
    }

    private fun decodeMap(raw: String): Map<String, String> {
        if (raw.isBlank()) return emptyMap()
        return runCatching {
            val root = JSONObject(raw)
            val out = mutableMapOf<String, String>()
            val keys = root.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                out[k] = root.optString(k)
            }
            out
        }.getOrElse { emptyMap() }
    }

    private fun encodeMap(map: Map<String, String>): String {
        val root = JSONObject()
        map.forEach { (k, v) -> root.put(k, v) }
        return root.toString()
    }

    private companion object {
        val BookmarkBlobKey = stringPreferencesKey("user_pdf_bookmarks_by_document_v1")
    }
}
