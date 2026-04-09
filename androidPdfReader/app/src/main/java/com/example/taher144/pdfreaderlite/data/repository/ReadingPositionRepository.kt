package com.example.taher144.pdfreaderlite.data.repository

import com.example.taher144.pdfreaderlite.data.model.ReaderSessionState

interface ReadingPositionRepository {
    suspend fun get(documentId: String): ReaderSessionState?

    suspend fun update(state: ReaderSessionState)
}
