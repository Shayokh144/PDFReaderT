package com.example.taher144.pdfreaderlite.reader

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.util.SparseArray
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.Toast
import androidx.core.os.bundleOf
import androidx.fragment.app.activityViewModels
import androidx.lifecycle.lifecycleScope
import androidx.pdf.ExperimentalPdfApi
import androidx.pdf.PdfDocument
import androidx.pdf.PdfPoint
import androidx.pdf.view.Highlight
import androidx.pdf.view.PdfView
import androidx.pdf.viewer.fragment.PdfViewerFragment
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.app.appContainer
import com.example.taher144.pdfreaderlite.data.model.PdfBookmark
import com.example.taher144.pdfreaderlite.ui.reader.PdfSearchResult
import com.example.taher144.pdfreaderlite.ui.reader.ReaderViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlin.math.min

@kotlin.OptIn(ExperimentalPdfApi::class)
class ReaderPdfViewerFragment : PdfViewerFragment() {

    private val readerViewModel: ReaderViewModel by activityViewModels()
    private var pdfViewRef: PdfView? = null
    private var pendingInitialPage: Int? = null
    private var resumePositionListener: PdfView.OnViewportChangedListener? = null
    private var resumePositionTimeout: Runnable? = null
    private var resumePositionTargetPage: Int = -1

    /** In-memory list shared with [ReaderPdfSelectionConfigurator]; persisted via app DataStore. */
    private val userSessionHighlights = mutableListOf<Highlight>()

    private var searchJob: Job? = null
    private var temporaryHighlightJob: Job? = null
    private var temporaryHighlight: List<Highlight>? = null

    private var bookmarkFlagView: ImageView? = null
    private var currentBookmark: PdfBookmark? = null
    private var suppressPdfGesturesUntilUp: Boolean = false
    private var bookmarkDoubleTapDetector: GestureDetector? = null

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
            return visibleCenterPage(view)
        }

    private fun visibleCenterPage(view: PdfView): Int {
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

        setupBookmarkFlagOverlay(pdfView)
        attachBookmarkDoubleTapGesture(pdfView)

        pdfView.addOnViewportChangedListener(object : PdfView.OnViewportChangedListener {
            override fun onViewportChanged(
                firstVisiblePage: Int,
                visiblePagesCount: Int,
                pageLocations: SparseArray<RectF>,
                zoomLevel: Float,
            ) {
                val total = pdfView.pdfDocument?.pageCount ?: 0
                val center = visibleCenterPage(pdfView)
                readerViewModel.updatePageInfo(center, total)
                updateBookmarkFlagPosition()
            }
        })

        observeSearch()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun attachBookmarkDoubleTapGesture(pdfView: PdfView) {
        // Replaces PdfViewerFragment's OnTouchListener (which toggled immersive mode on single-tap),
        // so we must handle single-tap fullscreen here as well as double-tap bookmarks.
        val detector = GestureDetector(
            requireContext(),
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onDown(e: MotionEvent): Boolean = true

                override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                    readerViewModel.toggleFullScreen()
                    return false
                }

                override fun onDoubleTap(e: MotionEvent): Boolean {
                    placeBookmarkAtViewPoint(pdfView, e.x, e.y)
                    suppressPdfGesturesUntilUp = true
                    return true
                }
            }
        )
        bookmarkDoubleTapDetector = detector
        pdfView.setOnTouchListener { _, event ->
            detector.onTouchEvent(event)
            if (suppressPdfGesturesUntilUp) {
                val action = event.actionMasked
                if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                    suppressPdfGesturesUntilUp = false
                }
                // Consume the second-tap stream so PdfView does not zoom on double-tap.
                true
            } else {
                // Let PdfView receive the event for scroll / pinch / selection.
                false
            }
        }
    }

    private fun setupBookmarkFlagOverlay(pdfView: PdfView) {
        val parent = pdfView.parent as? ViewGroup ?: return
        val sizePx = (BOOKMARK_FLAG_DP * resources.displayMetrics.density).toInt()
        val flag = ImageView(requireContext()).apply {
            layoutParams = FrameLayout.LayoutParams(sizePx, sizePx)
            setImageResource(R.drawable.ic_bookmark_flag)
            contentDescription = getString(R.string.pdf_reader_bookmark_flag)
            visibility = android.view.View.GONE
            isClickable = true
            isLongClickable = true
            setOnLongClickListener {
                removeBookmark()
                true
            }
        }
        bookmarkFlagView = flag
        parent.addView(flag)
    }

    private fun placeBookmarkAtViewPoint(pdfView: PdfView, viewX: Float, viewY: Float) {
        val documentId = arguments?.getString(ARG_DOCUMENT_ID).orEmpty()
        if (documentId.isBlank()) return
        val pdfPoint = pdfView.viewToPdfPoint(viewX, viewY) ?: return
        val bookmark = PdfBookmark(
            documentId = documentId,
            pageIndex = pdfPoint.pageNum,
            x = pdfPoint.x,
            y = pdfPoint.y,
        )
        currentBookmark = bookmark
        updateBookmarkFlagPosition()
        viewLifecycleOwner.lifecycleScope.launch {
            withContext(Dispatchers.IO) {
                requireContext().applicationContext.appContainer.userPdfBookmarkRepository
                    .setBookmark(bookmark)
            }
        }
    }

    private fun removeBookmark() {
        val documentId = arguments?.getString(ARG_DOCUMENT_ID).orEmpty()
        currentBookmark = null
        bookmarkFlagView?.visibility = android.view.View.GONE
        if (documentId.isBlank()) return
        viewLifecycleOwner.lifecycleScope.launch {
            withContext(Dispatchers.IO) {
                requireContext().applicationContext.appContainer.userPdfBookmarkRepository
                    .clearBookmark(documentId)
            }
        }
    }

    private fun updateBookmarkFlagPosition() {
        val pdfView = pdfViewRef ?: return
        val flag = bookmarkFlagView ?: return
        val bookmark = currentBookmark
        if (bookmark == null) {
            flag.visibility = android.view.View.GONE
            return
        }
        val viewPoint = pdfView.pdfToViewPoint(
            PdfPoint(bookmark.pageIndex, bookmark.x, bookmark.y)
        )
        if (viewPoint == null) {
            flag.visibility = android.view.View.GONE
            return
        }
        // Position so the flag tip sits near the tap point (pole at left, tip near top-left).
        flag.x = pdfView.left + viewPoint.x - (flag.width * 0.15f)
        flag.y = pdfView.top + viewPoint.y - (flag.height * 0.1f)
        flag.visibility = android.view.View.VISIBLE
        flag.bringToFront()
    }

    private fun scheduleRestoreBookmarkFromStore() {
        val documentId = arguments?.getString(ARG_DOCUMENT_ID).orEmpty()
        if (documentId.isBlank()) return
        viewLifecycleOwner.lifecycleScope.launch {
            val loaded = runCatching {
                withContext(Dispatchers.IO) {
                    requireContext().applicationContext.appContainer.userPdfBookmarkRepository
                        .getBookmark(documentId)
                }
            }.getOrNull()
            if (!isAdded) return@launch
            currentBookmark = loaded
            updateBookmarkFlagPosition()
        }
    }

    /** Scrolls to the saved bookmark page/position, or shows a toast if none exists. */
    fun goToBookmark(): Boolean {
        val bookmark = currentBookmark
        if (bookmark == null) {
            Toast.makeText(requireContext(), R.string.pdf_reader_bookmark_missing, Toast.LENGTH_SHORT).show()
            return false
        }
        val view = pdfViewRef
        if (view != null) {
            val point = PdfPoint(bookmark.pageIndex, bookmark.x, bookmark.y)
            if (runCatching { view.scrollToPosition(point) }.isSuccess) {
                view.post { updateBookmarkFlagPosition() }
                return true
            }
        }
        scheduleScrollToPage(bookmark.pageIndex) {
            updateBookmarkFlagPosition()
        }
        return true
    }

    private fun observeSearch() {
        viewLifecycleOwner.lifecycleScope.launch {
            readerViewModel.searchText.collect { query ->
                performSearch(query)
            }
        }
        viewLifecycleOwner.lifecycleScope.launch {
            readerViewModel.searchNavigation.collect { navRequest ->
                if (navRequest != null) {
                    navigateToSearchResult(navRequest.pageIndex, navRequest.matchIndex, navRequest.matchLength)
                    readerViewModel.clearSearchNavigation()
                }
            }
        }
    }

    @ExperimentalPdfApi
    private fun performSearch(query: String) {
        searchJob?.cancel()
        if (query.isBlank()) {
            readerViewModel.setSearchResults(emptyList())
            return
        }
        searchJob = viewLifecycleOwner.lifecycleScope.launch {
            delay(300) // debounce
            val doc = pdfViewRef?.pdfDocument ?: return@launch
            val pageCount = doc.pageCount
            if (pageCount == 0) return@launch

            val results = mutableListOf<PdfSearchResult>()
            withContext(Dispatchers.IO) {
                try {
                    val matches = doc.searchDocument(query, 0 until pageCount)
                    for (i in 0 until matches.size()) {
                        val pageIndex = matches.keyAt(i)
                        val pageMatches = matches.valueAt(i)
                        if (pageMatches.isNotEmpty()) {
                            val pageContent = doc.getPageContent(pageIndex)
                            val fullText = pageContent?.textContents?.joinToString(separator = "") { it.text } ?: ""
                            
                            pageMatches.forEachIndexed { matchIndex, matchBounds ->
                                val startIndex = matchBounds.textStartIndex
                                val matchLength = query.length // approximate, actual match might differ slightly
                                
                                val safeStartIndex = min(startIndex, fullText.length)
                                val snippetStart = max(0, safeStartIndex - 30)
                                val snippetEnd = min(fullText.length, safeStartIndex + matchLength + 30)
                                
                                var rawSnippet = fullText.substring(snippetStart, snippetEnd).replace("\n", " ")
                                var snippetMatchStart = safeStartIndex - snippetStart
                                
                                // Trim start manually to adjust snippetMatchStart
                                val trimmedStart = rawSnippet.trimStart()
                                val startTrimCount = rawSnippet.length - trimmedStart.length
                                rawSnippet = trimmedStart.trimEnd()
                                snippetMatchStart -= startTrimCount
                                
                                var snippet = rawSnippet
                                if (snippetStart > 0) {
                                    snippet = "…$snippet"
                                    snippetMatchStart += 1
                                }
                                if (snippetEnd < fullText.length) {
                                    snippet = "$snippet…"
                                }
                                
                                results.add(
                                    PdfSearchResult(
                                        pageIndex = pageIndex,
                                        snippet = snippet,
                                        matchIndex = matchIndex,
                                        matchLength = matchLength,
                                        snippetMatchStartIndex = snippetMatchStart
                                    )
                                )
                            }
                        }
                    }
                } catch (e: Exception) {
                    // Ignore search errors
                }
            }
            readerViewModel.setSearchResults(results)
        }
    }

    @ExperimentalPdfApi
    private fun navigateToSearchResult(pageIndex: Int, matchIndex: Int, matchLength: Int) {
        val view = pdfViewRef ?: return
        val doc = view.pdfDocument ?: return
        
        scheduleScrollToPage(pageIndex)
        
        temporaryHighlightJob?.cancel()
        temporaryHighlightJob = viewLifecycleOwner.lifecycleScope.launch {
            val query = readerViewModel.searchText.value
            if (query.isBlank()) return@launch
            
            try {
                val matches = doc.searchDocument(query, pageIndex..pageIndex)
                val pageMatches = matches.get(pageIndex)
                if (pageMatches != null && matchIndex < pageMatches.size) {
                    val matchBounds = pageMatches[matchIndex]
                    
                    // Remove previous temporary highlights
                    temporaryHighlight?.let {
                        userSessionHighlights.removeAll(it)
                    }
                    
                    // Add new temporary highlights (yellow, 50% opacity)
                    val newHighlights = matchBounds.bounds.map { rectF ->
                        Highlight(androidx.pdf.PdfRect(pageIndex, rectF.left, rectF.top, rectF.right, rectF.bottom), android.graphics.Color.argb(128, 255, 255, 0))
                    }
                    temporaryHighlight = newHighlights
                    userSessionHighlights.addAll(newHighlights)
                    view.setHighlights(userSessionHighlights.toList())
                    
                    // Remove after 2 seconds
                    delay(2000)
                    userSessionHighlights.removeAll(newHighlights)
                    temporaryHighlight = null
                    view.setHighlights(userSessionHighlights.toList())
                }
            } catch (e: Exception) {
                // Ignore errors
            }
        }
    }

    /**
     * Hide the default annotation toolbox (pen FAB) and toggle full-screen mode.
     * The library calls this on single-tap; we relay it to the activity via the shared ViewModel.
     */
    override fun onRequestImmersiveMode(enterImmersive: Boolean) {
        super.onRequestImmersiveMode(enterImmersive)
        isToolboxVisible = false
        readerViewModel.setFullScreen(enterImmersive)
    }

    override fun onResume() {
        super.onResume()
        // PdfView clears highlight overlays when the surface pauses; reload from store when doc still loaded.
        val view = pdfViewRef ?: return
        fun restoreIfReady() {
            if (pdfViewRef?.pdfDocument != null) {
                scheduleRestoreHighlightsFromStore()
                scheduleRestoreBookmarkFromStore()
            }
        }
        restoreIfReady()
        if (view.pdfDocument == null) {
            view.post { restoreIfReady() }
        }
    }

    override fun onLoadDocumentSuccess(document: PdfDocument) {
        super.onLoadDocumentSuccess(document)
        isToolboxVisible = false
        scheduleRestoreHighlightsFromStore()
        scheduleRestoreBookmarkFromStore()
        readerViewModel.updatePageInfo(
            pdfViewRef?.let { visibleCenterPage(it) } ?: 0,
            document.pageCount
        )
        val initialPage = pendingInitialPage ?: arguments?.getInt(ARG_INITIAL_PAGE, 0) ?: 0
        pendingInitialPage = null
        if (initialPage > 0) {
            val pdfView = pdfViewRef
            if (pdfView != null) {
                startResumePositionOverlay(pdfView, initialPage)
                // PdfView only wires PdfDocument into the scroller after this callback; scrolling
                // immediately throws IllegalStateException ("without PdfDocument").
                scheduleScrollToPage(initialPage) {
                    clearResumePositionOverlay(pdfView)
                }
            } else {
                (activity as? ReaderResumeLoadingController)?.setResumeLoadingVisible(false)
            }
        }
    }

    /** Never use runBlocking on the main thread here: DataStore can deadlock. */
    private fun scheduleRestoreHighlightsFromStore() {
        val documentId = arguments?.getString(ARG_DOCUMENT_ID).orEmpty()
        if (documentId.isBlank()) return
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

    /** Scrolls the viewer to [page] (0-based). Used by Read Aloud auto-follow. */
    fun scrollToPage(page: Int) {
        scheduleScrollToPage(page)
    }

    private fun scheduleScrollToPage(page: Int, onScrollGaveUp: (() -> Unit)? = null) {
        val view = pdfViewRef ?: return
        fun attempt(tryIndex: Int) {
            if (!isAdded) return
            val v = pdfViewRef ?: return
            if (runCatching { v.scrollToPage(page) }.isSuccess) return
            if (tryIndex >= MAX_SCROLL_TO_PAGE_ATTEMPTS) {
                onScrollGaveUp?.invoke()
                return
            }
            v.postDelayed({ attempt(tryIndex + 1) }, SCROLL_TO_PAGE_RETRY_DELAY_MS)
        }
        view.post { attempt(0) }
    }

    private fun startResumePositionOverlay(pdfView: PdfView, targetPage: Int) {
        resumePositionTargetPage = targetPage
        val listener = object : PdfView.OnViewportChangedListener {
            override fun onViewportChanged(
                firstVisiblePage: Int,
                visiblePagesCount: Int,
                pageLocations: SparseArray<RectF>,
                zoomLevel: Float,
            ) {
                if (!isAdded || resumePositionTargetPage < 0) return
                val v = pdfViewRef ?: return
                if (visibleCenterPage(v) != resumePositionTargetPage) return
                clearResumePositionOverlay(pdfView)
            }
        }
        resumePositionListener = listener
        pdfView.addOnViewportChangedListener(listener)
        val timeout = Runnable {
            if (!isAdded) return@Runnable
            clearResumePositionOverlay(pdfView)
        }
        resumePositionTimeout = timeout
        pdfView.postDelayed(timeout, RESUME_LOADING_TIMEOUT_MS)
    }

    private fun clearResumePositionOverlay(pdfView: PdfView) {
        if (resumePositionListener == null && resumePositionTimeout == null && resumePositionTargetPage < 0) {
            return
        }
        resumePositionTimeout?.let { pdfView.removeCallbacks(it) }
        resumePositionTimeout = null
        resumePositionListener?.let { pdfView.removeOnViewportChangedListener(it) }
        resumePositionListener = null
        resumePositionTargetPage = -1
        (activity as? ReaderResumeLoadingController)?.setResumeLoadingVisible(false)
    }

    override fun onDestroyView() {
        pdfViewRef?.let { clearResumePositionOverlay(it) }
        pdfViewRef?.setOnTouchListener(null)
        bookmarkFlagView?.let { flag ->
            (flag.parent as? ViewGroup)?.removeView(flag)
        }
        bookmarkFlagView = null
        bookmarkDoubleTapDetector = null
        pdfViewRef = null
        super.onDestroyView()
    }

    companion object {
        private const val MAX_SCROLL_TO_PAGE_ATTEMPTS = 25
        private const val SCROLL_TO_PAGE_RETRY_DELAY_MS = 32L
        private const val RESUME_LOADING_TIMEOUT_MS = 15_000L
        private const val BOOKMARK_FLAG_DP = 16

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
