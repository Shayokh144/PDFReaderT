package com.example.taher144.pdfreaderlite.reader

import android.content.Context
import android.net.Uri
import android.os.Bundle
import androidx.core.os.bundleOf
import androidx.pdf.ExperimentalPdfApi
import androidx.pdf.PdfDocument
import androidx.pdf.view.Highlight
import androidx.pdf.view.PdfView
import androidx.pdf.viewer.fragment.PdfViewerFragment
import com.example.taher144.pdfreaderlite.app.appContainer
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@kotlin.OptIn(ExperimentalPdfApi::class)
class ReaderPdfViewerFragment : PdfViewerFragment() {

    private var pdfViewRef: PdfView? = null
    private var pendingInitialPage: Int? = null

    /** In-memory list shared with [ReaderPdfSelectionConfigurator]; persisted via app DataStore. */
    private val userSessionHighlights = mutableListOf<Highlight>()

    override fun onAttach(context: Context) {
        super.onAttach(context)
        val uriString = arguments?.getString(ARG_URI) ?: return
        documentUri = Uri.parse(uriString)
    }

    /** 0-based resume index: page at viewport center via [PdfView.viewToPdfPoint], not last visible row. */
    @ExperimentalPdfApi
    val currentVisiblePage: Int
        get() {
            val view = pdfViewRef ?: return arguments?.getInt(ARG_INITIAL_PAGE, 0) ?: 0
            val totalPages = view.pdfDocument?.pageCount ?: 0
            val maxIndex = if (totalPages > 0) totalPages - 1 else null

            val w = view.width
            val h = view.height
            if (w > 0 && h > 0) {
                val center = view.viewToPdfPoint(w / 2f, h / 2f)
                if (center != null) {
                    return if (maxIndex != null) {
                        center.pageNum.coerceIn(0, maxIndex)
                    } else {
                        center.pageNum.coerceAtLeast(0)
                    }
                }
            }

            return fallbackPageIndexFromVisibleRange(view, maxIndex)
        }

    private fun fallbackPageIndexFromVisibleRange(view: PdfView, maxIndex: Int?): Int {
        val first = view.firstVisiblePage
        val count = view.visiblePagesCount.coerceAtLeast(1)
        val lastVisible = first + count - 1
        return if (maxIndex != null) lastVisible.coerceIn(0, maxIndex) else lastVisible
    }

    @ExperimentalPdfApi
    override fun onPdfViewCreated(pdfView: PdfView) {
        super.onPdfViewCreated(pdfView)
        this.pdfViewRef = pdfView
        val uri = arguments?.getString(ARG_URI)?.let(Uri::parse) ?: return
        val documentId = arguments?.getString(ARG_DOCUMENT_ID).orEmpty()
        ReaderPdfSelectionConfigurator.attach(
            pdfView = pdfView,
            documentUri = uri,
            documentId = documentId,
            lifecycleOwner = viewLifecycleOwner,
            highlightsRepository = requireContext().applicationContext.appContainer.userPdfHighlightsRepository,
            sessionHighlights = userSessionHighlights,
        )
    }

    /**
     * Hide the default annotation toolbox (pen FAB). We apply highlights from the text selection
     * menu instead of the external annotate intent flow.
     */
    override fun onRequestImmersiveMode(enterImmersive: Boolean) {
        super.onRequestImmersiveMode(enterImmersive)
        isToolboxVisible = false
    }

    override fun onLoadDocumentSuccess(document: PdfDocument) {
        super.onLoadDocumentSuccess(document)
        isToolboxVisible = false
        val documentId = arguments?.getString(ARG_DOCUMENT_ID).orEmpty()
        if (documentId.isNotBlank()) {
            // Never use runBlocking here: DataStore + main thread can deadlock and kill the app.
            viewLifecycleOwner.lifecycleScope.launch {
                val loaded = runCatching {
                    withContext(Dispatchers.IO) {
                        requireContext().applicationContext.appContainer.userPdfHighlightsRepository
                            .getHighlights(documentId)
                    }
                }.getOrElse { emptyList() }
                if (!isAdded) return@launch
                userSessionHighlights.clear()
                userSessionHighlights.addAll(loaded)
                pdfViewRef?.setHighlights(userSessionHighlights.toList())
            }
        }
        val initialPage = pendingInitialPage ?: arguments?.getInt(ARG_INITIAL_PAGE, 0) ?: 0
        pendingInitialPage = null
        if (initialPage > 0) {
            // PdfView only wires PdfDocument into the scroller after this callback; scrolling
            // immediately throws IllegalStateException ("without PdfDocument").
            scheduleScrollToPage(initialPage)
        }
    }

    private fun scheduleScrollToPage(page: Int) {
        val view = pdfViewRef ?: return
        fun attempt(tryIndex: Int) {
            if (!isAdded) return
            val v = pdfViewRef ?: return
            if (runCatching { v.scrollToPage(page) }.isSuccess) return
            if (tryIndex >= MAX_SCROLL_TO_PAGE_ATTEMPTS) return
            v.postDelayed({ attempt(tryIndex + 1) }, SCROLL_TO_PAGE_RETRY_DELAY_MS)
        }
        view.post { attempt(0) }
    }

    override fun onDestroyView() {
        pdfViewRef = null
        super.onDestroyView()
    }

    companion object {
        private const val MAX_SCROLL_TO_PAGE_ATTEMPTS = 25
        private const val SCROLL_TO_PAGE_RETRY_DELAY_MS = 32L

        private const val ARG_URI = "document_uri"
        private const val ARG_INITIAL_PAGE = "initial_page"
        private const val ARG_DOCUMENT_ID = "document_id"

        fun newInstance(uri: Uri, initialPage: Int, documentId: String): ReaderPdfViewerFragment {
            return ReaderPdfViewerFragment().apply {
                pendingInitialPage = initialPage
                arguments = bundleOf(
                    ARG_URI to uri.toString(),
                    ARG_INITIAL_PAGE to initialPage,
                    ARG_DOCUMENT_ID to documentId,
                )
            }
        }
    }
}
