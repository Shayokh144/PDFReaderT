package com.example.taher144.pdfreaderlite.readaloud

import android.content.Context
import android.net.Uri
import androidx.pdf.PdfDocument
import androidx.pdf.SandboxedPdfLoader
import kotlinx.coroutines.Dispatchers

/**
 * Opens a PDF via [SandboxedPdfLoader] and extracts page text using [PdfDocument.getPageContent].
 */
class PdfTextExtractor(
    context: Context
) {
    private val loader = SandboxedPdfLoader(context.applicationContext, Dispatchers.IO)

    suspend fun open(uri: Uri): PdfDocument = loader.openDocument(uri)

    suspend fun extractPageText(document: PdfDocument, pageIndex: Int): String {
        return runCatching {
            val pageContent = document.getPageContent(pageIndex)
            pageContent?.textContents
                ?.joinToString(separator = "") { it.text }
                .orEmpty()
                .trim()
        }.getOrDefault("")
    }

    suspend fun hasAnyReadableText(
        document: PdfDocument,
        startPage: Int = 0,
        pagesToScan: Int = MAX_EMPTY_SCAN_PAGES
    ): Boolean {
        val end = minOf(document.pageCount, maxOf(startPage, 0) + pagesToScan)
        for (page in maxOf(startPage, 0) until end) {
            if (extractPageText(document, page).isNotBlank()) return true
        }
        // Also scan from the beginning if startPage was mid-document and early pages were empty.
        if (startPage > 0) {
            for (page in 0 until minOf(startPage, pagesToScan)) {
                if (extractPageText(document, page).isNotBlank()) return true
            }
        }
        return false
    }

    companion object {
        private const val MAX_EMPTY_SCAN_PAGES = 20
    }
}
