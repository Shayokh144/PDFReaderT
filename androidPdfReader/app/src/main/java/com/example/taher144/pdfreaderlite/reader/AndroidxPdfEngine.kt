package com.example.taher144.pdfreaderlite.reader

import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.ext.SdkExtensions
import com.example.taher144.pdfreaderlite.data.repository.PersistedUriHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AndroidxPdfEngine(
    private val context: Context,
    private val persistedUriHelper: PersistedUriHelper
) : PdfEngine {

    override fun isReaderSupportedOnDevice(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return SdkExtensions.getExtensionVersion(Build.VERSION_CODES.S) >= REQUIRED_SDK_EXTENSION
    }

    override suspend fun openDocument(uri: Uri): PdfEngineDocument = withContext(Dispatchers.IO) {
        check(persistedUriHelper.canRead(uri)) { "Unable to access document URI." }

        val pageCount = resolvePageCount(uri)

        PdfEngineDocument(
            documentId = uri.toString(),
            uri = uri,
            pageCount = pageCount,
            supportsTextSelection = true,
            supportsAnnotations = true,
            isReadOnlyForAnnotations = false
        )
    }

    override fun createReaderIntent(
        context: Context,
        request: ReaderLaunchRequest
    ) = AndroidxPdfReaderActivity.newIntent(
        context = context,
        documentId = request.documentId,
        uri = request.uri,
        initialPage = request.initialPage
    )

    private fun resolvePageCount(uri: Uri): Int {
        return try {
            context.contentResolver.openFileDescriptor(uri, "r")?.use { fd ->
                PdfRenderer(fd).use { renderer ->
                    renderer.pageCount
                }
            } ?: 0
        } catch (_: Exception) {
            0
        }
    }

    companion object {
        private const val REQUIRED_SDK_EXTENSION = 13
    }
}
