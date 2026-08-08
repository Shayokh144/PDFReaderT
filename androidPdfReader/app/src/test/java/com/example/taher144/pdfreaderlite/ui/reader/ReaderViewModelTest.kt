package com.example.taher144.pdfreaderlite.ui.reader

import android.app.Application
import com.example.taher144.pdfreaderlite.reader.PdfSaveCoordinator
import com.example.taher144.pdfreaderlite.ui.FakeElapsedClock
import com.example.taher144.pdfreaderlite.ui.FakeReadingPositionRepository
import com.example.taher144.pdfreaderlite.ui.FakeRecentFilesRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
class ReaderViewModelTest {

    private val dispatcher = StandardTestDispatcher()
    private lateinit var application: Application
    private lateinit var recentFiles: FakeRecentFilesRepository
    private lateinit var positions: FakeReadingPositionRepository
    private lateinit var clock: FakeElapsedClock
    private lateinit var saveCoordinator: PdfSaveCoordinator
    private lateinit var viewModel: ReaderViewModel

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        application = RuntimeEnvironment.getApplication()
        recentFiles = FakeRecentFilesRepository()
        positions = FakeReadingPositionRepository()
        clock = FakeElapsedClock(nowMs = 10_000L)
        saveCoordinator = PdfSaveCoordinator()
        viewModel = ReaderViewModel(
            application = application,
            readingPositionRepository = positions,
            recentFilesRepository = recentFiles,
            saveCoordinator = saveCoordinator,
            elapsedRealtime = clock::elapsedRealtime
        )
    }

    @After
    fun tearDown() {
        viewModel.closeCoordinator()
        Dispatchers.resetMain()
    }

    @Test
    fun updatePageInfo_exposesPageAndTotal() {
        viewModel.updatePageInfo(page = 4, totalPages = 20)
        assertEquals(4 to 20, viewModel.pageInfo.value)
    }

    @Test
    fun fullScreen_setToggleAndReset() {
        viewModel.setFullScreen(true)
        assertTrue(viewModel.isFullScreen.value)

        viewModel.toggleFullScreen()
        assertFalse(viewModel.isFullScreen.value)

        viewModel.setFullScreen(true)
        viewModel.resetFullScreen()
        assertFalse(viewModel.isFullScreen.value)
    }

    @Test
    fun searchState_navigateClearAndReset() {
        val result = PdfSearchResult(
            pageIndex = 2,
            snippet = "hello",
            matchIndex = 1,
            matchLength = 5,
            snippetMatchStartIndex = 0
        )
        viewModel.setIsSearching(true)
        viewModel.setSearchText("hello")
        viewModel.setSearchResults(listOf(result))

        viewModel.navigateToSearchResult(result)
        assertFalse(viewModel.isSearching.value)
        assertEquals(2, viewModel.searchNavigation.value?.pageIndex)
        assertEquals(1, viewModel.searchNavigation.value?.matchIndex)
        assertEquals(5, viewModel.searchNavigation.value?.matchLength)

        viewModel.clearSearchNavigation()
        assertNull(viewModel.searchNavigation.value)

        viewModel.setIsSearching(true)
        viewModel.setSearchText("x")
        viewModel.setSearchResults(listOf(result))
        viewModel.navigateToSearchResult(result)
        viewModel.resetSearchState()

        assertFalse(viewModel.isSearching.value)
        assertEquals("", viewModel.searchText.value)
        assertTrue(viewModel.searchResults.value.isEmpty())
        assertNull(viewModel.searchNavigation.value)
    }

    @Test
    fun beginReadingSession_blankId_isIgnored() {
        viewModel.beginReadingSession("  ")
        viewModel.beginReadingSession("")
        clock.nowMs = 20_000L
        viewModel.commitReadingTimeIfNeeded()
        saveCoordinator.flushBlocking()
        assertTrue(recentFiles.readingTimeUpdates.isEmpty())
    }

    @Test
    fun commitReadingTimeIfNeeded_withoutSession_isNoOp() {
        viewModel.commitReadingTimeIfNeeded()
        saveCoordinator.flushBlocking()
        assertTrue(recentFiles.readingTimeUpdates.isEmpty())
    }

    @Test
    fun commitReadingTimeIfNeeded_zeroDelta_doesNotPersist() {
        clock.nowMs = 1_000L
        viewModel.beginReadingSession("doc-1")
        // Same clock → 0 seconds
        viewModel.commitReadingTimeIfNeeded()
        saveCoordinator.flushBlocking()
        assertTrue(recentFiles.readingTimeUpdates.isEmpty())
    }

    @Test
    fun commitReadingTimeIfNeeded_persistsElapsedSeconds() = runTest(dispatcher) {
        clock.nowMs = 1_000L
        viewModel.beginReadingSession("doc-1")
        clock.nowMs = 6_500L // 5.5s → 5 seconds
        viewModel.commitReadingTimeIfNeeded()
        saveCoordinator.flushBlocking()
        advanceUntilIdle()

        assertEquals(listOf("doc-1" to 5L), recentFiles.readingTimeUpdates)

        // Session cleared — second commit is no-op
        clock.nowMs = 20_000L
        viewModel.commitReadingTimeIfNeeded()
        saveCoordinator.flushBlocking()
        assertEquals(1, recentFiles.readingTimeUpdates.size)
    }

    @Test
    fun persistReadingState_blankDocumentId_isNoOp() {
        viewModel.persistReadingState(
            documentId = "",
            currentPage = 1,
            totalPages = 10,
            isReadOnly = false,
            sync = true
        )
        assertTrue(positions.updates.isEmpty())
        assertTrue(recentFiles.progressUpdates.isEmpty())
    }

    @Test
    fun persistReadingState_sync_updatesRepositories() {
        viewModel.persistReadingState(
            documentId = "doc-2",
            currentPage = 7,
            totalPages = 30,
            isReadOnly = true,
            sync = true
        )

        assertEquals(1, positions.updates.size)
        assertEquals("doc-2", positions.updates.single().documentId)
        assertEquals(7, positions.updates.single().currentPage)
        assertTrue(positions.updates.single().isReadOnly)
        assertEquals(listOf(Triple("doc-2", 7, 30)), recentFiles.progressUpdates)
    }

    @Test
    fun persistReadingState_async_thenFlush() {
        viewModel.persistReadingState(
            documentId = "doc-3",
            currentPage = 1,
            totalPages = 2,
            isReadOnly = false,
            sync = false
        )
        saveCoordinator.flushBlocking()
        assertEquals("doc-3", positions.updates.single().documentId)
        assertEquals(Triple("doc-3", 1, 2), recentFiles.progressUpdates.single())
    }

    @Test
    fun closeCoordinator_isSafeToCall() {
        viewModel.closeCoordinator()
        // Calling again after close should not crash the VM API surface.
        viewModel.closeCoordinator()
    }
}
