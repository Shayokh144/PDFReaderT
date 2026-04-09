package com.example.taher144.pdfreaderlite.reader

import android.content.Context
import android.content.Intent
import android.net.Uri

data class ReaderLaunchRequest(
    val documentId: String,
    val uri: Uri,
    val initialPage: Int
)

data class PdfEngineDocument(
    val documentId: String,
    val uri: Uri,
    val pageCount: Int,
    val supportsTextSelection: Boolean,
    val supportsAnnotations: Boolean,
    val isReadOnlyForAnnotations: Boolean
)

interface PdfEngine {
    fun isReaderSupportedOnDevice(): Boolean = true

    suspend fun openDocument(uri: Uri): PdfEngineDocument

    fun createReaderIntent(
        context: Context,
        request: ReaderLaunchRequest
    ): Intent
}
