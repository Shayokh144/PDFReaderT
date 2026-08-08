package com.example.taher144.pdfreaderlite.ui.home

import android.app.Application
import android.net.Uri
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.data.model.ReaderSessionState
import com.example.taher144.pdfreaderlite.data.model.RecentPdfRecord
import com.example.taher144.pdfreaderlite.reader.PdfEngineDocument
import com.example.taher144.pdfreaderlite.ui.FakePdfEngine
import com.example.taher144.pdfreaderlite.ui.FakePersistedUriAccess
import com.example.taher144.pdfreaderlite.ui.FakeReadingPositionRepository
import com.example.taher144.pdfreaderlite.ui.FakeRecentFilesRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HomeViewModelTest {

    private val dispatcher = StandardTestDispatcher()
    private lateinit var application: Application
    private lateinit var recentFiles: FakeRecentFilesRepository
    private lateinit var positions: FakeReadingPositionRepository
    private lateinit var uriAccess: FakePersistedUriAccess
    private lateinit var pdfEngine: FakePdfEngine
    private lateinit var viewModel: HomeViewModel

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        application = RuntimeEnvironment.getApplication()
        recentFiles = FakeRecentFilesRepository()
        positions = FakeReadingPositionRepository()
        uriAccess = FakePersistedUriAccess()
        pdfEngine = FakePdfEngine()
        viewModel = HomeViewModel(
            application = application,
            recentFilesRepository = recentFiles,
            readingPositionRepository = positions,
            persistedUriHelper = uriAccess,
            pdfEngine = pdfEngine,
            unknownFileNameProvider = { "Unknown.pdf" }
        )
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun TestScope.collectUiState() {
        backgroundScope.launch(dispatcher) { viewModel.uiState.collect { } }
    }

    private fun TestScope.collectEvents(): MutableList<HomeEvent> {
        val events = mutableListOf<HomeEvent>()
        backgroundScope.launch(dispatcher) { viewModel.events.collect { events += it } }
        return events
    }

    @Test
    fun onPdfPicked_success_upsertsAndOpensReader() = runTest(dispatcher) {
        collectUiState()
        val events = collectEvents()
        val uri = Uri.parse("content://docs/sample.pdf")
        positions.states["doc-1"] = ReaderSessionState(documentId = "doc-1", currentPage = 3)
        pdfEngine.document = PdfEngineDocument(
            documentId = "doc-1",
            uri = uri,
            pageCount = 12,
            supportsTextSelection = true,
            supportsAnnotations = true,
            isReadOnlyForAnnotations = false
        )

        viewModel.onPdfPicked(uri)
        advanceUntilIdle()

        assertEquals(1, recentFiles.upsertCalls.size)
        assertEquals("doc-1", recentFiles.upsertCalls.first().id)
        assertEquals("sample.pdf", recentFiles.upsertCalls.first().displayName)
        assertEquals(3, recentFiles.upsertCalls.first().lastPage)
        assertEquals(12, recentFiles.upsertCalls.first().totalPages)
        assertEquals(listOf(uri), uriAccess.permissionUris)
        assertFalse(viewModel.uiState.value.isOpeningDocument)

        val open = events.filterIsInstance<HomeEvent.OpenReader>().single()
        assertEquals("doc-1", open.request.documentId)
        assertEquals(3, open.request.initialPage)
        assertEquals(uri, open.request.uri)
    }

    @Test
    fun onPdfPicked_preservesExistingReadingTime() = runTest(dispatcher) {
        recentFiles.records.value = listOf(
            RecentPdfRecord(
                id = "doc-1",
                displayName = "old.pdf",
                persistedUri = "content://old",
                dateAdded = 1L,
                lastOpenedAt = 1L,
                fileSizeBytes = 1L,
                lastPage = 0,
                totalPages = 5,
                readingTimeSeconds = 42L
            )
        )
        collectUiState()
        collectEvents()
        advanceUntilIdle()

        viewModel.onPdfPicked(Uri.parse("content://docs/sample.pdf"))
        advanceUntilIdle()

        assertEquals(42L, recentFiles.upsertCalls.last().readingTimeSeconds)
    }

    @Test
    fun onPdfPicked_usesUnknownNameWhenMetadataMissing() = runTest(dispatcher) {
        collectUiState()
        collectEvents()
        uriAccess.displayName = null
        // Uri with no lastPathSegment
        val uri = Uri.parse("content://authority")

        viewModel.onPdfPicked(uri)
        advanceUntilIdle()

        assertEquals("Unknown.pdf", recentFiles.upsertCalls.single().displayName)
    }

    @Test
    fun onPdfPicked_failure_emitsOpenError() = runTest(dispatcher) {
        collectUiState()
        val events = collectEvents()
        pdfEngine.throwOnOpen = IllegalStateException("boom")

        viewModel.onPdfPicked(Uri.parse("content://docs/bad.pdf"))
        advanceUntilIdle()

        assertTrue(recentFiles.upsertCalls.isEmpty())
        val message = events.filterIsInstance<HomeEvent.ShowMessage>().single()
        assertEquals(R.string.pdf_reader_open_error_message, message.messageResId)
        assertFalse(viewModel.uiState.value.isOpeningDocument)
    }

    @Test
    fun onRecentFileSelected_success_opensWithStoredPage() = runTest(dispatcher) {
        collectUiState()
        val events = collectEvents()
        val record = RecentPdfRecord(
            id = "doc-9",
            displayName = "book.pdf",
            persistedUri = "content://docs/book.pdf",
            dateAdded = 10L,
            lastOpenedAt = 10L,
            fileSizeBytes = 100L,
            lastPage = 2,
            totalPages = 8
        )
        positions.states["doc-9"] = ReaderSessionState(documentId = "doc-9", currentPage = 5)
        pdfEngine.document = PdfEngineDocument(
            documentId = "doc-9",
            uri = Uri.parse(record.persistedUri),
            pageCount = 20,
            supportsTextSelection = true,
            supportsAnnotations = true,
            isReadOnlyForAnnotations = false
        )

        viewModel.onRecentFileSelected(record)
        advanceUntilIdle()

        assertEquals(20, recentFiles.upsertCalls.single().totalPages)
        val open = events.filterIsInstance<HomeEvent.OpenReader>().single()
        assertEquals("doc-9", open.request.documentId)
        assertEquals(5, open.request.initialPage)
    }

    @Test
    fun onRecentFileSelected_unreadable_deletesAndShowsMessage() = runTest(dispatcher) {
        collectUiState()
        val events = collectEvents()
        uriAccess.canReadResult = false
        val record = RecentPdfRecord(
            id = "gone",
            displayName = "gone.pdf",
            persistedUri = "content://docs/gone.pdf",
            dateAdded = 1L,
            lastOpenedAt = 1L,
            fileSizeBytes = null,
            lastPage = 0,
            totalPages = 1
        )

        viewModel.onRecentFileSelected(record)
        advanceUntilIdle()

        assertEquals(listOf("gone"), recentFiles.deletedIds)
        assertEquals(
            R.string.pdf_reader_recent_file_unavailable,
            events.filterIsInstance<HomeEvent.ShowMessage>().single().messageResId
        )
    }

    @Test
    fun onRecentFileSelected_openThrows_deletesAndShowsMessage() = runTest(dispatcher) {
        collectUiState()
        val events = collectEvents()
        pdfEngine.throwOnOpen = RuntimeException("missing")
        val record = RecentPdfRecord(
            id = "bad",
            displayName = "bad.pdf",
            persistedUri = "content://docs/bad.pdf",
            dateAdded = 1L,
            lastOpenedAt = 1L,
            fileSizeBytes = null,
            lastPage = 0,
            totalPages = 1
        )

        viewModel.onRecentFileSelected(record)
        advanceUntilIdle()

        assertEquals(listOf("bad"), recentFiles.deletedIds)
        assertEquals(
            R.string.pdf_reader_recent_file_unavailable,
            events.filterIsInstance<HomeEvent.ShowMessage>().single().messageResId
        )
    }

    @Test
    fun onRecentFileDeleted_removesFromRepository() = runTest(dispatcher) {
        viewModel.onRecentFileDeleted("doc-x")
        advanceUntilIdle()
        assertEquals(listOf("doc-x"), recentFiles.deletedIds)
    }

    @Test
    fun uiState_reflectsRecentFilesAndOpeningFlag() = runTest(dispatcher) {
        collectUiState()
        recentFiles.records.value = listOf(
            RecentPdfRecord(
                id = "a",
                displayName = "a.pdf",
                persistedUri = "content://a",
                dateAdded = 1L,
                lastOpenedAt = 1L,
                fileSizeBytes = 1L,
                lastPage = 0,
                totalPages = 1
            )
        )
        advanceUntilIdle()
        assertEquals(1, viewModel.uiState.first { it.recentFiles.size == 1 }.recentFiles.size)
    }
}
