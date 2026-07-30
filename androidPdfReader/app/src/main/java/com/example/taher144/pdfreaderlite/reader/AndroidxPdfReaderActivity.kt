package com.example.taher144.pdfreaderlite.reader

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import android.view.GestureDetector
import android.view.Menu
import android.view.MotionEvent
import android.view.View
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.pdf.ExperimentalPdfApi
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.readaloud.ReadAloudPlaybackState
import com.example.taher144.pdfreaderlite.readaloud.ReadAloudPositionStore
import com.example.taher144.pdfreaderlite.readaloud.ReadAloudService
import com.example.taher144.pdfreaderlite.readaloud.ReadAloudSpeechRateStore
import com.example.taher144.pdfreaderlite.readaloud.ReadAloudStartMode
import com.example.taher144.pdfreaderlite.ui.reader.ReaderViewModel
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import kotlin.math.abs
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class AndroidxPdfReaderActivity : AppCompatActivity(), ReaderResumeLoadingController {

    private val viewModel: ReaderViewModel by viewModels()
    private val positionStore by lazy { ReadAloudPositionStore(this) }
    private val speechRateStore by lazy { ReadAloudSpeechRateStore(this) }

    private lateinit var readerResumeLoadingOverlay: View
    private lateinit var readAloudScrollLockOverlay: View
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
    private var lastFollowedReadAloudPage: Int = -1
    private var pendingStartAfterPermission: Boolean = false
    private var lastHandledErrorKey: String? = null
    private var startChooserDialog: androidx.appcompat.app.AlertDialog? = null

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                if (pendingStartAfterPermission) {
                    pendingStartAfterPermission = false
                    showReadAloudStartChooser()
                }
            } else {
                pendingStartAfterPermission = false
                Toast.makeText(
                    this,
                    R.string.pdf_reader_read_aloud_notification_permission,
                    Toast.LENGTH_LONG
                ).show()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        setContentView(R.layout.activity_androidx_pdf_reader)

        readerResumeLoadingOverlay = findViewById(R.id.reader_resume_loading_overlay)
        readAloudScrollLockOverlay = findViewById(R.id.read_aloud_scroll_lock_overlay)
        setupScrollLockOverlay()
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
        observeReadAloudState()
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.menu_pdf_reader, menu)
        bindReadAloudMenu(menu, ReadAloudService.playbackState.value)
        return true
    }

    override fun onPrepareOptionsMenu(menu: Menu): Boolean {
        bindReadAloudMenu(menu, ReadAloudService.playbackState.value)
        return super.onPrepareOptionsMenu(menu)
    }

    override fun onOptionsItemSelected(item: android.view.MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_search -> {
                viewModel.setIsSearching(true)
                true
            }
            R.id.action_read_aloud -> {
                onReadAloudMenuClicked()
                true
            }
            R.id.action_stop_read_aloud -> {
                ReadAloudService.stop(this)
                true
            }
            R.id.action_read_aloud_speed -> {
                showReadAloudSpeedChooser()
                true
            }
            R.id.action_go_to_bookmark -> {
                val fragment = supportFragmentManager
                    .findFragmentByTag(TAG_PDF_FRAGMENT) as? ReaderPdfViewerFragment
                fragment?.goToBookmark()
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
        startChooserDialog?.dismiss()
        startChooserDialog = null
        viewModel.commitReadingTimeIfNeeded()
        persistReadingState(sync = true)
        viewModel.resetFullScreen()
        viewModel.resetSearchState()
        viewModel.closeCoordinator()
        super.onDestroy()
    }

    private fun setupScrollLockOverlay() {
        val detector = GestureDetector(
            this,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onDown(e: MotionEvent): Boolean = true

                override fun onSingleTapUp(e: MotionEvent): Boolean {
                    viewModel.toggleFullScreen()
                    return true
                }
            }
        )
        readAloudScrollLockOverlay.setOnTouchListener { _, event ->
            detector.onTouchEvent(event)
            true
        }
    }

    private fun setScrollLocked(locked: Boolean) {
        readAloudScrollLockOverlay.visibility = if (locked) View.VISIBLE else View.GONE
    }

    private fun observeReadAloudState() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                ReadAloudService.playbackState.collect { state ->
                    invalidateOptionsMenu()
                    handleReadAloudError(state)
                    followReadAloudPage(state)
                    val lockScroll = state is ReadAloudPlaybackState.Playing &&
                        state.documentId == documentId
                    setScrollLocked(lockScroll)
                }
            }
        }
    }

    private fun bindReadAloudMenu(menu: Menu, state: ReadAloudPlaybackState) {
        val readItem = menu.findItem(R.id.action_read_aloud) ?: return
        val stopItem = menu.findItem(R.id.action_stop_read_aloud)
        val activeForThisDoc = state.documentIdOrNull == documentId && state.isActive

        when {
            activeForThisDoc && state is ReadAloudPlaybackState.Playing -> {
                readItem.title = getString(R.string.pdf_reader_read_aloud_pause)
                readItem.setIcon(android.R.drawable.ic_media_pause)
                stopItem?.isVisible = true
            }
            activeForThisDoc && state is ReadAloudPlaybackState.Paused -> {
                readItem.title = getString(R.string.pdf_reader_read_aloud_resume)
                readItem.setIcon(android.R.drawable.ic_media_play)
                stopItem?.isVisible = true
            }
            activeForThisDoc && state is ReadAloudPlaybackState.Preparing -> {
                readItem.title = getString(R.string.pdf_reader_read_aloud_preparing)
                readItem.setIcon(android.R.drawable.ic_btn_speak_now)
                stopItem?.isVisible = true
            }
            else -> {
                readItem.title = getString(R.string.pdf_reader_read_aloud)
                readItem.setIcon(android.R.drawable.ic_btn_speak_now)
                stopItem?.isVisible = false
            }
        }
    }

    private fun onReadAloudMenuClicked() {
        val state = ReadAloudService.playbackState.value
        when {
            state is ReadAloudPlaybackState.Playing && state.documentId == documentId -> {
                ReadAloudService.pause(this)
            }
            state is ReadAloudPlaybackState.Paused && state.documentId == documentId -> {
                ReadAloudService.resume(this)
            }
            state is ReadAloudPlaybackState.Preparing && state.documentId == documentId -> {
                // Still preparing — ignore duplicate taps.
            }
            state.isActive && state.documentIdOrNull != documentId -> {
                MaterialAlertDialogBuilder(this)
                    .setMessage(R.string.pdf_reader_read_aloud_switch_document)
                    .setPositiveButton(android.R.string.ok) { _, _ ->
                        requestNotificationPermissionThenStart()
                    }
                    .setNegativeButton(android.R.string.cancel, null)
                    .show()
            }
            else -> requestNotificationPermissionThenStart()
        }
    }

    private fun requestNotificationPermissionThenStart() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                pendingStartAfterPermission = true
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                return
            }
        }
        showReadAloudStartChooser()
    }

    private fun showReadAloudStartChooser() {
        if (isFinishing || isDestroyed) return
        startChooserDialog?.dismiss()

        val currentPage = getCurrentPageFromFragment()
        val saved = positionStore.load(documentId)

        val labels = mutableListOf<String>()
        val modes = mutableListOf<ReadAloudStartMode>()

        labels.add(getString(R.string.pdf_reader_read_aloud_start_current_page, currentPage + 1))
        modes.add(ReadAloudStartMode.CURRENT_PAGE)

        labels.add(getString(R.string.pdf_reader_read_aloud_start_beginning))
        modes.add(ReadAloudStartMode.BEGINNING)

        if (saved != null) {
            labels.add(getString(R.string.pdf_reader_read_aloud_start_saved, saved.first + 1))
            modes.add(ReadAloudStartMode.SAVED)
        }

        startChooserDialog = MaterialAlertDialogBuilder(this)
            .setTitle(R.string.pdf_reader_read_aloud_start_title)
            .setItems(labels.toTypedArray()) { _, which ->
                startReadAloudInternal(modes[which], currentPage)
            }
            .setNegativeButton(R.string.pdf_reader_read_aloud_cancel, null)
            .show()
    }

    private fun showReadAloudSpeedChooser() {
        if (isFinishing || isDestroyed) return
        val rates = ReadAloudSpeechRateStore.PRESET_RATES
        val current = speechRateStore.getRate()
        var selectedIndex = rates.indexOfFirst { abs(it - current) < 0.001f }
        if (selectedIndex < 0) selectedIndex = rates.indexOfFirst {
            abs(it - ReadAloudSpeechRateStore.DEFAULT_RATE) < 0.001f
        }.coerceAtLeast(0)

        val labels = rates.map { rate ->
            if (abs(rate - ReadAloudSpeechRateStore.DEFAULT_RATE) < 0.001f) {
                getString(R.string.pdf_reader_read_aloud_speed_option_default, rate)
            } else {
                getString(R.string.pdf_reader_read_aloud_speed_option, rate)
            }
        }.toTypedArray()

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.pdf_reader_read_aloud_speed)
            .setSingleChoiceItems(labels, selectedIndex) { dialog, which ->
                ReadAloudService.setSpeechRate(this, rates[which])
                dialog.dismiss()
            }
            .setNegativeButton(R.string.pdf_reader_read_aloud_cancel, null)
            .show()
    }

    private fun startReadAloudInternal(startMode: ReadAloudStartMode, startPage: Int) {
        val uri = documentUri ?: return
        ReadAloudService.start(
            context = this,
            documentId = documentId,
            uri = uri,
            title = resolveDisplayName(uri),
            startPage = startPage,
            startMode = startMode
        )
    }

    private fun handleReadAloudError(state: ReadAloudPlaybackState) {
        if (state !is ReadAloudPlaybackState.Error) return
        if (state.documentId != null && state.documentId != documentId) return

        val errorKey = "${state.reason}:${state.documentId}"
        if (errorKey == lastHandledErrorKey) return
        lastHandledErrorKey = errorKey

        val messageRes = when (state.reason) {
            ReadAloudPlaybackState.Error.Reason.NO_TEXT ->
                R.string.pdf_reader_read_aloud_no_text
            ReadAloudPlaybackState.Error.Reason.TTS_UNAVAILABLE ->
                R.string.pdf_reader_read_aloud_tts_unavailable
            ReadAloudPlaybackState.Error.Reason.LANGUAGE_UNSUPPORTED ->
                R.string.pdf_reader_read_aloud_language_unsupported
            ReadAloudPlaybackState.Error.Reason.OPEN_FAILED ->
                R.string.pdf_reader_read_aloud_open_failed
        }

        if (state.reason == ReadAloudPlaybackState.Error.Reason.TTS_UNAVAILABLE ||
            state.reason == ReadAloudPlaybackState.Error.Reason.LANGUAGE_UNSUPPORTED
        ) {
            MaterialAlertDialogBuilder(this)
                .setMessage(messageRes)
                .setPositiveButton(android.R.string.ok) { _, _ ->
                    runCatching {
                        startActivity(Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA))
                    }
                }
                .setNegativeButton(android.R.string.cancel, null)
                .show()
        } else {
            Toast.makeText(this, messageRes, Toast.LENGTH_LONG).show()
        }
    }

    private fun followReadAloudPage(state: ReadAloudPlaybackState) {
        // Only auto-follow while actively playing; when paused the user may scroll freely.
        val page = when (state) {
            is ReadAloudPlaybackState.Playing -> state.currentPage
            else -> {
                if (state !is ReadAloudPlaybackState.Paused) {
                    lastFollowedReadAloudPage = -1
                }
                return
            }
        }
        if (state.documentId != documentId) return
        if (page == lastFollowedReadAloudPage) return
        lastFollowedReadAloudPage = page
        val fragment = supportFragmentManager
            .findFragmentByTag(TAG_PDF_FRAGMENT) as? ReaderPdfViewerFragment
        fragment?.scrollToPage(page)
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
            toolbar.animate().cancel()
            pageCounter.animate().cancel()
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
            toolbar.animate().cancel()
            pageCounter.animate().cancel()
            toolbar.visibility = View.VISIBLE
            toolbar.animate()
                .alpha(1f)
                .setDuration(FULLSCREEN_ANIM_MS)
                .withEndAction(null)
                .start()
            if (pageCounter.visibility == View.VISIBLE) {
                pageCounter.animate()
                    .alpha(1f)
                    .setDuration(FULLSCREEN_ANIM_MS)
                    .start()
            }
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

    private fun resolveDisplayName(uri: Uri): String? {
        return runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
                }
        }.getOrNull()
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
