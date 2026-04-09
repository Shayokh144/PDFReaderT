package com.example.taher144.pdfreaderlite.reader

import android.content.Context
import android.content.Intent
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Bundle
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.pdf.ExperimentalPdfApi
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.ui.reader.ReaderViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class AndroidxPdfReaderActivity : AppCompatActivity() {

    private val viewModel: ReaderViewModel by viewModels()

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
        setContentView(R.layout.activity_androidx_pdf_reader)

        val toolbar = findViewById<androidx.appcompat.widget.Toolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = ""
        toolbar.setNavigationOnClickListener { finish() }

        val uri = documentUri
        if (uri == null) {
            finish()
            return
        }

        totalPages = resolvePageCount(uri)

        if (savedInstanceState == null) {
            val fragment = ReaderPdfViewerFragment.newInstance(uri, initialPage)
            supportFragmentManager.beginTransaction()
                .replace(R.id.pdf_fragment_container, fragment, TAG_PDF_FRAGMENT)
                .commit()
        }

        startPeriodicPagePersistence()
    }

    override fun onPause() {
        super.onPause()
        persistReadingState()
    }

    override fun onDestroy() {
        persistReadingState()
        viewModel.closeCoordinator()
        super.onDestroy()
    }

    private fun persistReadingState() {
        if (documentId.isBlank()) return

        val currentPage = getCurrentPageFromFragment()
        viewModel.persistReadingState(
            documentId = documentId,
            currentPage = currentPage,
            totalPages = totalPages,
            isReadOnly = false
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
                    persistReadingState()
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
