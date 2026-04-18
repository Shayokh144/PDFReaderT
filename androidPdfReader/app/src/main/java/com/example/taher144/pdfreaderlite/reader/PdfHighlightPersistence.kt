package com.example.taher144.pdfreaderlite.reader

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.RectF
import android.net.Uri
import androidx.pdf.EditablePdfDocument
import androidx.pdf.MutableEditsDraft
import androidx.pdf.annotation.models.HighlightAnnotation
import androidx.pdf.selection.model.TextSelection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * Persists text highlights as real PDF highlight annotations and writes the updated bytes back to
 * [uri] when the content provider allows read/write access.
 */
object PdfHighlightPersistence {

    /** Standard translucent yellow used for both overlay and embedded annotation color. */
    @JvmField
    val DefaultHighlightColorArgb: Int = Color.argb(0xFF, 0xFA, 0xFA, 0x28)

    /**
     * Inserts one [HighlightAnnotation] per page touched by [selection], with one [RectF] per
     * line (each [androidx.pdf.PdfRect] in the selection).
     */
    @SuppressLint("RestrictedApi")
    suspend fun applyHighlightAndSave(
        context: Context,
        document: EditablePdfDocument,
        uri: Uri,
        selection: TextSelection,
        colorArgb: Int = DefaultHighlightColorArgb,
    ) {
        withContext(Dispatchers.IO) {
            val draft = MutableEditsDraft()
            val byPage = selection.bounds.groupBy { it.pageNum }
            for ((pageNum, rects) in byPage) {
                val rectFs = rects.map { r -> RectF(r.left, r.top, r.right, r.bottom) }
                draft.insert(HighlightAnnotation(pageNum, rectFs, colorArgb))
            }
            document.applyEdits(draft.toEditsDraft())

            val pfd =
                context.contentResolver.openFileDescriptor(uri, "rw")
                    ?: throw IOException("Cannot open document for writing.")
            pfd.use { fd ->
                document.createWriteHandle().use { handle ->
                    handle.writeTo(fd)
                }
            }
        }
    }
}
