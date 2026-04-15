package com.example.taher144.pdfreaderlite.data.repository

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.example.taher144.pdfreaderlite.data.model.RecentPdfRecord
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

class UserPrefsRecentFilesRepository(
    private val context: Context
) : RecentFilesRepository {
    private val mutex = Mutex()
    private var cachedRecords: List<RecentPdfRecord>? = null

    override val recentFiles: Flow<List<RecentPdfRecord>> =
        context.pdfReaderDataStore.data.map { preferences ->
            decodeRecords(preferences[RecentFilesKey].orEmpty())
        }.onEach { records ->
            // No mutex: same mutex is held during persist(); withLock here deadlocks reentrantly.
            cachedRecords = records
        }

    override suspend fun upsert(record: RecentPdfRecord) {
        mutex.withLock {
            val updatedRecords = ensureRecordsLoaded()
                .filterNot { it.id == record.id }
                .plus(record)
                .sortedByDescending { it.lastOpenedAt }

            if (cachedRecords == updatedRecords) return@withLock
            cachedRecords = updatedRecords
            persist(updatedRecords)
        }
    }

    override suspend fun delete(documentId: String) {
        mutex.withLock {
            val updatedRecords = ensureRecordsLoaded().filterNot { it.id == documentId }
            if (cachedRecords == updatedRecords) return@withLock
            cachedRecords = updatedRecords
            persist(updatedRecords)
        }
    }

    override suspend fun updateReadingProgress(
        documentId: String,
        currentPage: Int,
        totalPages: Int
    ) {
        mutex.withLock {
            val current = ensureRecordsLoaded()
            val updatedRecords = current.map { record ->
                if (record.id != documentId) {
                    record
                } else {
                    record.copy(
                        lastPage = currentPage,
                        totalPages = totalPages
                    )
                }
            }

            if (current == updatedRecords) return@withLock
            cachedRecords = updatedRecords
            persist(updatedRecords)
        }
    }

    private suspend fun ensureRecordsLoaded(): List<RecentPdfRecord> {
        return cachedRecords ?: loadRecordsFromDisk().also { cachedRecords = it }
    }

    private suspend fun loadRecordsFromDisk(): List<RecentPdfRecord> {
        // Must not use recentFiles.first(): that flow's onEach would need this mutex while we
        // already hold it from upsert/delete/updateReadingProgress.
        return context.pdfReaderDataStore.data.map { preferences ->
            decodeRecords(preferences[RecentFilesKey].orEmpty())
        }.first()
    }

    private suspend fun persist(records: List<RecentPdfRecord>) {
        context.pdfReaderDataStore.edit { preferences ->
            preferences[RecentFilesKey] = encodeRecords(records)
        }
    }

    private fun decodeRecords(rawValue: String): List<RecentPdfRecord> {
        if (rawValue.isBlank()) {
            return emptyList()
        }

        return buildList {
            val jsonArray = JSONArray(rawValue)
            for (index in 0 until jsonArray.length()) {
                val item = jsonArray.optJSONObject(index) ?: continue
                add(
                    RecentPdfRecord(
                        id = item.optString("id"),
                        displayName = item.optString("displayName"),
                        persistedUri = item.optString("persistedUri"),
                        dateAdded = item.optLong("dateAdded"),
                        lastOpenedAt = item.optLong("lastOpenedAt"),
                        fileSizeBytes = if (item.has("fileSizeBytes")) item.optLong("fileSizeBytes") else null,
                        lastPage = item.optInt("lastPage"),
                        totalPages = item.optInt("totalPages")
                    )
                )
            }
        }
    }

    private fun encodeRecords(records: List<RecentPdfRecord>): String {
        val jsonArray = JSONArray()
        records.forEach { record ->
            jsonArray.put(
                JSONObject().apply {
                    put("id", record.id)
                    put("displayName", record.displayName)
                    put("persistedUri", record.persistedUri)
                    put("dateAdded", record.dateAdded)
                    put("lastOpenedAt", record.lastOpenedAt)
                    if (record.fileSizeBytes != null) {
                        put("fileSizeBytes", record.fileSizeBytes)
                    }
                    put("lastPage", record.lastPage)
                    put("totalPages", record.totalPages)
                }
            )
        }
        return jsonArray.toString()
    }

    private companion object {
        val RecentFilesKey = stringPreferencesKey("recent_files_json")
    }
}
