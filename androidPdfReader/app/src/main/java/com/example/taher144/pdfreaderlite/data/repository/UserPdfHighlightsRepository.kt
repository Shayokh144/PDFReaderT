package com.example.taher144.pdfreaderlite.data.repository

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.pdf.PdfRect
import androidx.pdf.selection.model.TextSelection
import androidx.pdf.view.Highlight
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists user highlight rectangles per document so they survive app restarts and URIs that cannot
 * be written back to the PDF file.
 */
interface UserPdfHighlightsRepository {
    suspend fun getHighlights(documentId: String): List<Highlight>

    suspend fun appendFromTextSelection(
        documentId: String,
        selection: TextSelection,
        colorArgb: Int,
    )
}

class UserPrefsUserPdfHighlightsRepository(
    private val context: Context,
) : UserPdfHighlightsRepository {
    private val mutex = Mutex()
    private var cachedMap: Map<String, String>? = null

    override suspend fun getHighlights(documentId: String): List<Highlight> {
        if (documentId.isBlank()) return emptyList()
        val map = mutex.withLock { ensureMapLoaded() }
        val jsonArray = map[documentId] ?: return emptyList()
        return parseHighlightsJson(jsonArray)
    }

    override suspend fun appendFromTextSelection(
        documentId: String,
        selection: TextSelection,
        colorArgb: Int,
    ) {
        if (documentId.isBlank()) return
        mutex.withLock {
            val map = ensureMapLoaded().toMutableMap()
            val existing = map[documentId]?.let { JSONArray(it) } ?: JSONArray()
            for (bound in selection.bounds) {
                existing.put(
                    JSONObject().apply {
                        put("page", bound.pageNum)
                        put("left", bound.left.toDouble())
                        put("top", bound.top.toDouble())
                        put("right", bound.right.toDouble())
                        put("bottom", bound.bottom.toDouble())
                        put("color", colorArgb)
                    },
                )
            }
            map[documentId] = existing.toString()
            cachedMap = map
            saveMap(map)
        }
    }

    private suspend fun ensureMapLoaded(): Map<String, String> {
        return cachedMap ?: loadMapFromDisk().also { cachedMap = it }
    }

    private suspend fun loadMapFromDisk(): Map<String, String> {
        return context.pdfReaderDataStore.data.map { preferences ->
            decodeMap(preferences[HighlightsBlobKey].orEmpty())
        }.first()
    }

    private suspend fun saveMap(map: Map<String, String>) {
        context.pdfReaderDataStore.edit { preferences ->
            preferences[HighlightsBlobKey] = encodeMap(map)
        }
    }

    private fun parseHighlightsJson(jsonArray: String): List<Highlight> {
        if (jsonArray.isBlank()) return emptyList()
        val arr = runCatching { JSONArray(jsonArray) }.getOrNull() ?: return emptyList()
        val out = ArrayList<Highlight>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val page = o.optInt("page", -1)
            if (page < 0) continue
            val left = o.optDouble("left").toFloat()
            val top = o.optDouble("top").toFloat()
            val right = o.optDouble("right").toFloat()
            val bottom = o.optDouble("bottom").toFloat()
            val color = o.optInt("color", 0)
            runCatching {
                out += Highlight(PdfRect(page, left, top, right, bottom), color)
            }
        }
        return out
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
        val HighlightsBlobKey = stringPreferencesKey("user_pdf_highlights_by_document_v1")
    }
}
