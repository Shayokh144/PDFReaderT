package com.example.taher144.pdfreaderlite.reader

import android.net.Uri
import androidx.annotation.ColorInt
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import androidx.pdf.EditablePdfDocument
import androidx.pdf.ExperimentalPdfApi
import androidx.pdf.selection.ContextMenuComponent
import androidx.pdf.selection.PdfSelectionMenuKeys
import androidx.pdf.selection.SelectionMenuComponent
import androidx.pdf.selection.model.TextSelection
import androidx.pdf.view.Highlight
import androidx.pdf.view.PdfView
import com.example.taher144.pdfreaderlite.data.repository.UserPdfHighlightsRepository
import com.example.taher144.pdfreaderlite.R
import com.google.android.material.snackbar.Snackbar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private object HighlightMenuKey

/**
 * Customizes the PDF text selection menu (Copy, Select All, Highlight) and applies highlight
 * annotations. Smart actions from [android.view.textclassifier.TextClassifier] are removed for a
 * consistent menu.
 */
@OptIn(ExperimentalPdfApi::class)
object ReaderPdfSelectionConfigurator {

    fun attach(
        pdfView: PdfView,
        documentUri: Uri,
        documentId: String,
        lifecycleOwner: LifecycleOwner,
        highlightsRepository: UserPdfHighlightsRepository,
        sessionHighlights: MutableList<Highlight>,
        @ColorInt highlightColorArgb: Int = PdfHighlightPersistence.DefaultHighlightColorArgb,
    ) {
        val preparer = object : PdfView.SelectionMenuItemPreparer {
            override fun onPrepareSelectionMenuItems(components: MutableList<ContextMenuComponent>) {
                components.removeAll { it.key === PdfSelectionMenuKeys.SmartActionKey }
                if (components.any { it.key === HighlightMenuKey }) return

                val highlightLabel = pdfView.context.getString(R.string.pdf_reader_highlight)
                val highlightDesc = pdfView.context.getString(R.string.pdf_reader_highlight_description)
                components.add(
                    SelectionMenuComponent(
                        key = HighlightMenuKey,
                        label = highlightLabel,
                        contentDescription = highlightDesc,
                    ) {
                        val selection = pdfView.currentSelection as? TextSelection
                        if (selection == null) {
                            close()
                        } else {
                            // Apply yellow overlay immediately on the main thread (same tap as the menu action).
                            showHighlightOverlayOnly(
                                pdfView,
                                sessionHighlights,
                                selection,
                                highlightColorArgb,
                            )
                            close()
                            pdfView.clearCurrentSelection()

                            lifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
                                highlightsRepository.appendFromTextSelection(
                                    documentId = documentId,
                                    selection = selection,
                                    colorArgb = highlightColorArgb,
                                )
                                val doc = pdfView.pdfDocument as? EditablePdfDocument
                                if (doc == null) {
                                    withContext(Dispatchers.Main) {
                                        Snackbar.make(
                                                pdfView,
                                                pdfView.context.getString(R.string.pdf_reader_highlight_read_only_document),
                                                Snackbar.LENGTH_LONG,
                                            )
                                            .show()
                                    }
                                    return@launch
                                }
                                try {
                                    PdfHighlightPersistence.applyHighlightAndSave(
                                        context = pdfView.context,
                                        document = doc,
                                        uri = documentUri,
                                        selection = selection,
                                        colorArgb = highlightColorArgb,
                                    )
                                } catch (_: Exception) {
                                    withContext(Dispatchers.Main) {
                                        Snackbar.make(
                                                pdfView,
                                                pdfView.context.getString(R.string.pdf_reader_highlight_save_failed),
                                                Snackbar.LENGTH_LONG,
                                            )
                                            .show()
                                    }
                                }
                            }
                        }
                    },
                )
            }
        }
        pdfView.addSelectionMenuItemPreparer(preparer)
    }

    private fun showHighlightOverlayOnly(
        pdfView: PdfView,
        sessionHighlights: MutableList<Highlight>,
        selection: TextSelection,
        colorArgb: Int,
    ) {
        selection.bounds.forEach { rect ->
            sessionHighlights += Highlight(rect, colorArgb)
        }
        pdfView.setHighlights(sessionHighlights.toList())
    }
}
