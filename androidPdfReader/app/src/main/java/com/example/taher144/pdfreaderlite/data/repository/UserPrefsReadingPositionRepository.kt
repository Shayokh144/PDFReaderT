package com.example.taher144.pdfreaderlite.data.repository

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.example.taher144.pdfreaderlite.data.model.ReaderSessionState
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

class UserPrefsReadingPositionRepository(
    private val context: Context
) : ReadingPositionRepository {
    private val mutex = Mutex()
    private var cachedStates: Map<String, ReaderSessionState>? = null

    override suspend fun get(documentId: String): ReaderSessionState? {
        return mutex.withLock {
            ensureStatesLoaded()[documentId]
        }
    }

    override suspend fun update(state: ReaderSessionState) {
        mutex.withLock {
            val current = ensureStatesLoaded()
            if (current[state.documentId] == state) return@withLock

            val updatedStates = current.toMutableMap().apply {
                put(state.documentId, state)
            }
            cachedStates = updatedStates

            context.pdfReaderDataStore.edit { preferences ->
                preferences[ReadingStateKey] = encodeStates(updatedStates.values.toList())
            }
        }
    }

    private suspend fun ensureStatesLoaded(): Map<String, ReaderSessionState> {
        return cachedStates ?: loadStatesFromDisk().also { cachedStates = it }
    }

    private suspend fun loadStatesFromDisk(): Map<String, ReaderSessionState> {
        return context.pdfReaderDataStore.data.map { preferences ->
            decodeStates(preferences[ReadingStateKey].orEmpty())
        }.first()
    }

    private fun decodeStates(rawValue: String): Map<String, ReaderSessionState> {
        if (rawValue.isBlank()) {
            return emptyMap()
        }

        val jsonArray = JSONArray(rawValue)
        return buildMap {
            for (index in 0 until jsonArray.length()) {
                val item = jsonArray.optJSONObject(index) ?: continue
                val documentId = item.optString("documentId")
                put(
                    documentId,
                    ReaderSessionState(
                        documentId = documentId,
                        currentPage = item.optInt("currentPage"),
                        isSaving = item.optBoolean("isSaving"),
                        isReadOnly = item.optBoolean("isReadOnly"),
                        pendingSaveCount = item.optInt("pendingSaveCount")
                    )
                )
            }
        }
    }

    private fun encodeStates(states: List<ReaderSessionState>): String {
        val jsonArray = JSONArray()
        states.forEach { state ->
            jsonArray.put(
                JSONObject().apply {
                    put("documentId", state.documentId)
                    put("currentPage", state.currentPage)
                    put("isSaving", state.isSaving)
                    put("isReadOnly", state.isReadOnly)
                    put("pendingSaveCount", state.pendingSaveCount)
                }
            )
        }
        return jsonArray.toString()
    }

    private companion object {
        val ReadingStateKey = stringPreferencesKey("reader_states_json")
    }
}
