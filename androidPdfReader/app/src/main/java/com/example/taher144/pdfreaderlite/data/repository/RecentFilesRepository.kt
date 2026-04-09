package com.example.taher144.pdfreaderlite.data.repository

import com.example.taher144.pdfreaderlite.data.model.RecentPdfRecord
import kotlinx.coroutines.flow.Flow

interface RecentFilesRepository {
    val recentFiles: Flow<List<RecentPdfRecord>>

    suspend fun upsert(record: RecentPdfRecord)

    suspend fun delete(documentId: String)

    suspend fun updateReadingProgress(
        documentId: String,
        currentPage: Int,
        totalPages: Int
    )
}
