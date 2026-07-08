package com.example.taher144.pdfreaderlite.reader

import android.content.Context
import android.content.Intent
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Bundle
import android.view.View
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.pdf.ExperimentalPdfApi
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.ui.reader.ReaderViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class AndroidxPdfReaderActivity : AppCompatActivity(), ReaderResumeLoadingController {

    private val viewModel: ReaderViewModel by viewModels()

    private lateinit var readerResumeLoadingOverlay: View
    private lateinit var toolbar: View
    private lateinit var pageCounter: android.widget.TextView

    private val documentId: String by lazy {
        intent.getStringExtra(EXTRA_DOCUMENT_ID).orEmpty()
    }

    private val documentUri: Uri? by lazy {
        intent.data
    }

    private val initialPage: Int by lazy {
        intent.getIntExtra(EXTRA_INITIAL_PAGE, 0)
    }

    private var totalPages: Int = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        setContentView(R.layout.activity_androidx_pdf_reader)

        readerResumeLoadingOverlay = findViewById(R.id.reader_resume_loading_overlay)
        if (savedInstanceState == null && initialPage > 0) {
            setResumeLoadingVisible(true)
        } else {
            setResumeLoadingVisible(false)
        }

        toolbar = findViewById<androidx.appcompat.widget.Toolbar>(R.id.toolbar)
        
        ViewCompat.setOnApplyWindowInsetsListener(toolbar) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(view.paddingLeft, systemBars.top, view.paddingRight, view.paddingBottom)
            insets
        }
        
        setSupportActionBar(toolbar as androidx.appcompat.widget.Toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = ""

        pageCounter = findViewById(R.id.page_counter)
        
        ViewCompat.setOnApplyWindowInsetsListener(pageCounter) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            // Add the bottom inset to the existing margin
            val layoutParams = view.layoutParams as android.widget.FrameLayout.LayoutParams
            layoutParams.bottomMargin = systemBars.bottom + (12 * view.resources.displayMetrics.density).toInt()
            view.layoutParams = layoutParams
            insets
        }

        val uri = documentUri
        if (uri == null) {
            finish()
            return
        }

        totalPages = resolvePageCount(uri)

        if (savedInstanceState == null) {
            val fragment = ReaderPdfViewerFragment.newInstance(uri, initialPage, documentId)
            supportFragmentManager.beginTransaction()
                .replace(R.id.pdf_fragment_container, fragment, TAG_PDF_FRAGMENT)
                .commit()
        }

        startPeriodicPagePersistence()
        observeFullScreenState()
        observePageCounter()
    }

    override fun onCreateOptionsMenu(menu: android.view.Menu): Boolean {
        menuInflater.inflate(R.menu.menu_pdf_reader, menu)
        return true
    }

    override fun onOptionsItemSelected(item: android.view.MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_search -> {
                viewModel.setIsSearching(true)
                true
            }
            android.R.id.home -> {
                finish()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    override fun setResumeLoadingVisible(visible: Boolean) {
        readerResumeLoadingOverlay.visibility = if (visible) View.VISIBLE else View.GONE
    }

    override fun onResume() {
        super.onResume()
        viewModel.beginReadingSession(documentId)
    }

    override fun onPause() {
        super.onPause()
        viewModel.commitReadingTimeIfNeeded()
        persistReadingState(sync = false)
    }

    override fun onDestroy() {
        viewModel.commitReadingTimeIfNeeded()
        persistReadingState(sync = true)
        viewModel.resetFullScreen()
        viewModel.resetSearchState()
        viewModel.closeCoordinator()
        super.onDestroy()
    }

    // --- Full-screen mode ---

    private fun observeFullScreenState() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.isFullScreen.collect { fullScreen ->
                    applyFullScreen(fullScreen)
                }
            }
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.isSearching.collect { isSearching ->
                    if (isSearching) {
                        if (supportFragmentManager.findFragmentByTag("search_bottom_sheet") == null) {
                            PdfSearchBottomSheetFragment().show(supportFragmentManager, "search_bottom_sheet")
                        }
                    } else {
                        val fragment = supportFragmentManager.findFragmentByTag("search_bottom_sheet") as? com.google.android.material.bottomsheet.BottomSheetDialogFragment
                        fragment?.dismiss()
                    }
                }
            }
        }
    }

    private fun applyFullScreen(fullScreen: Boolean) {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        if (fullScreen) {
            toolbar.animate()
                .alpha(0f)
                .setDuration(FULLSCREEN_ANIM_MS)
                .withEndAction { toolbar.visibility = View.GONE }
                .start()
            pageCounter.animate()
                .alpha(0f)
                .setDuration(FULLSCREEN_ANIM_MS)
                .start()
            controller.hide(WindowInsetsCompat.Type.statusBars())
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            toolbar.visibility = View.VISIBLE
            toolbar.animate()
                .alpha(1f)
                .setDuration(FULLSCREEN_ANIM_MS)
                .withEndAction(null)
                .start()
            pageCounter.animate()
                .alpha(1f)
                .setDuration(FULLSCREEN_ANIM_MS)
                .start()
            controller.show(WindowInsetsCompat.Type.statusBars())
        }
    }

    // --- Page counter ---

    private fun observePageCounter() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.pageInfo.collect { (page, total) ->
                    if (total > 0) {
                        pageCounter.text = getString(R.string.pdf_reader_page_counter, page + 1, total)
                        if (pageCounter.visibility != View.VISIBLE) {
                            pageCounter.visibility = View.VISIBLE
                            pageCounter.alpha = if (viewModel.isFullScreen.value) 0f else 1f
                        }
                    }
                }
            }
        }
    }

    // --- Reading state persistence ---

    private fun persistReadingState(sync: Boolean = false) {
        if (documentId.isBlank()) return

        val currentPage = getCurrentPageFromFragment()
        viewModel.persistReadingState(
            documentId = documentId,
            currentPage = currentPage,
            totalPages = totalPages,
            isReadOnly = false,
            sync = sync
        )
    }

    @OptIn(ExperimentalPdfApi::class)
    private fun getCurrentPageFromFragment(): Int {
        val fragment = supportFragmentManager
            .findFragmentByTag(TAG_PDF_FRAGMENT) as? ReaderPdfViewerFragment
        return fragment?.currentVisiblePage ?: initialPage
    }

    private fun startPeriodicPagePersistence() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.RESUMED) {
                while (true) {
                    delay(PERSIST_INTERVAL_MS)
                    persistReadingState(sync = false)
                }
            }
        }
    }

    private fun resolvePageCount(uri: Uri): Int {
        return try {
            contentResolver.openFileDescriptor(uri, "r")?.use { fd ->
                PdfRenderer(fd).use { renderer ->
                    renderer.pageCount
                }
            } ?: 0
        } catch (_: Exception) {
            0
        }
    }

    companion object {
        private const val EXTRA_DOCUMENT_ID = "document_id"
        private const val EXTRA_INITIAL_PAGE = "initial_page"
        private const val TAG_PDF_FRAGMENT = "pdf_viewer"
        private const val PERSIST_INTERVAL_MS = 5_000L
        private const val FULLSCREEN_ANIM_MS = 200L

        fun newIntent(
            context: Context,
            documentId: String,
            uri: Uri,
            initialPage: Int
        ): Intent {
            return Intent(context, AndroidxPdfReaderActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = uri
                putExtra(EXTRA_DOCUMENT_ID, documentId)
                putExtra(EXTRA_INITIAL_PAGE, initialPage)
            }
        }
    }
}
