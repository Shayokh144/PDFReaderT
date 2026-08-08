package com.example.taher144.pdfreaderlite.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.example.taher144.pdfreaderlite.data.model.ReaderSessionState
import com.example.taher144.pdfreaderlite.data.model.RecentPdfRecord
import com.example.taher144.pdfreaderlite.data.repository.PersistedUriAccess
import com.example.taher144.pdfreaderlite.data.repository.ReadingPositionRepository
import com.example.taher144.pdfreaderlite.data.repository.RecentFilesRepository
import com.example.taher144.pdfreaderlite.reader.PdfEngine
import com.example.taher144.pdfreaderlite.reader.PdfEngineDocument
import com.example.taher144.pdfreaderlite.reader.ReaderLaunchRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.Flow

internal class FakeRecentFilesRepository(
    initial: List<RecentPdfRecord> = emptyList()
) : RecentFilesRepository {
    val records = MutableStateFlow(initial)
    val upsertCalls = mutableListOf<RecentPdfRecord>()
    val deletedIds = mutableListOf<String>()
    val readingTimeUpdates = mutableListOf<Pair<String, Long>>()
    val progressUpdates = mutableListOf<Triple<String, Int, Int>>()

    override val recentFiles: Flow<List<RecentPdfRecord>> = records

    override suspend fun upsert(record: RecentPdfRecord) {
        upsertCalls += record
        val without = records.value.filterNot { it.id == record.id }
        records.value = listOf(record) + without
    }

    override suspend fun delete(documentId: String) {
        deletedIds += documentId
        records.value = records.value.filterNot { it.id == documentId }
    }

    override suspend fun updateReadingProgress(
        documentId: String,
        currentPage: Int,
        totalPages: Int
    ) {
        progressUpdates += Triple(documentId, currentPage, totalPages)
    }

    override suspend fun updateReadingTime(documentId: String, deltaSeconds: Long) {
        readingTimeUpdates += documentId to deltaSeconds
    }
}

internal class FakeReadingPositionRepository : ReadingPositionRepository {
    val states = mutableMapOf<String, ReaderSessionState>()
    val updates = mutableListOf<ReaderSessionState>()

    override suspend fun get(documentId: String): ReaderSessionState? = states[documentId]

    override suspend fun update(state: ReaderSessionState) {
        updates += state
        states[state.documentId] = state
    }
}

internal class FakePersistedUriAccess(
    var canReadResult: Boolean = true,
    var displayName: String? = "sample.pdf",
    var fileSizeBytes: Long? = 1024L
) : PersistedUriAccess {
    val permissionUris = mutableListOf<Uri>()

    override fun takePersistableReadWritePermission(uri: Uri) {
        permissionUris += uri
    }

    override fun canRead(uri: Uri): Boolean = canReadResult

    override fun getDisplayName(uri: Uri): String? = displayName

    override fun getFileSizeBytes(uri: Uri): Long? = fileSizeBytes
}

internal class FakePdfEngine(
    var document: PdfEngineDocument? = null,
    var throwOnOpen: Throwable? = null
) : PdfEngine {
    val openedUris = mutableListOf<Uri>()

    override suspend fun openDocument(uri: Uri): PdfEngineDocument {
        openedUris += uri
        throwOnOpen?.let { throw it }
        return document ?: PdfEngineDocument(
            documentId = "doc-1",
            uri = uri,
            pageCount = 10,
            supportsTextSelection = true,
            supportsAnnotations = true,
            isReadOnlyForAnnotations = false
        )
    }

    override fun createReaderIntent(context: Context, request: ReaderLaunchRequest): Intent {
        return Intent()
    }
}

internal class FakeElapsedClock(var nowMs: Long = 0L) {
    fun elapsedRealtime(): Long = nowMs
}
