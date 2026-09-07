package com.example.taher144.pdfreaderlite.ui.reader

import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import com.example.taher144.pdfreaderlite.app.appContainer
import com.example.taher144.pdfreaderlite.data.model.ReaderSessionState
import com.example.taher144.pdfreaderlite.data.repository.ReadingPositionRepository
import com.example.taher144.pdfreaderlite.data.repository.RecentFilesRepository
import com.example.taher144.pdfreaderlite.reader.PdfSaveCoordinator
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class ReaderViewModel(
    application: Application,
    private val readingPositionRepository: ReadingPositionRepository,
    private val recentFilesRepository: RecentFilesRepository,
    private val saveCoordinator: PdfSaveCoordinator,
    private val elapsedRealtime: () -> Long,
) : AndroidViewModel(application) {

    /**
     * Required by [androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory]
     * (`viewModels()` / `activityViewModels()`). Kotlin default args alone do not emit this JVM ctor.
     */
    constructor(application: Application) : this(
        application,
        application.applicationContext.appContainer.readingPositionRepository,
        application.applicationContext.appContainer.recentFilesRepository,
        PdfSaveCoordinator(),
        { SystemClock.elapsedRealtime() },
    )

    // --- Reading time session tracking ---
    private var sessionDocumentId: String? = null
    private var sessionStartElapsed: Long = -1L

    // --- Page counter ---
    private val _pageInfo = MutableStateFlow(0 to 0)
    val pageInfo: StateFlow<Pair<Int, Int>> = _pageInfo

    fun updatePageInfo(page: Int, totalPages: Int) {
        _pageInfo.value = page to totalPages
    }

    // --- Full-screen mode ---
    private val _isFullScreen = MutableStateFlow(false)
    val isFullScreen: StateFlow<Boolean> = _isFullScreen

    // --- Search ---
    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching

    private val _searchText = MutableStateFlow("")
    val searchText: StateFlow<String> = _searchText

    private val _searchResults = MutableStateFlow<List<PdfSearchResult>>(emptyList())
    val searchResults: StateFlow<List<PdfSearchResult>> = _searchResults

    private val _searchNavigation = MutableStateFlow<SearchNavigationRequest?>(null)
    val searchNavigation: StateFlow<SearchNavigationRequest?> = _searchNavigation

    fun setIsSearching(searching: Boolean) {
        _isSearching.value = searching
    }

    fun setSearchText(text: String) {
        _searchText.value = text
    }

    fun setSearchResults(results: List<PdfSearchResult>) {
        _searchResults.value = results
    }

    fun navigateToSearchResult(result: PdfSearchResult) {
        _searchNavigation.value = SearchNavigationRequest(
            pageIndex = result.pageIndex,
            matchIndex = result.matchIndex,
            matchLength = result.matchLength
        )
        setIsSearching(false)
    }

    fun clearSearchNavigation() {
        _searchNavigation.value = null
    }

    fun resetSearchState() {
        _isSearching.value = false
        _searchText.value = ""
        _searchResults.value = emptyList()
        _searchNavigation.value = null
    }

    fun beginReadingSession(documentId: String) {
        if (documentId.isBlank()) return
        sessionDocumentId = documentId
        sessionStartElapsed = elapsedRealtime()
    }

    fun commitReadingTimeIfNeeded() {
        val docId = sessionDocumentId ?: return
        val start = sessionStartElapsed
        if (start < 0 || docId.isBlank()) return

        val elapsed = elapsedRealtime() - start
        val deltaSeconds = elapsed / 1_000L
        sessionStartElapsed = -1L
        sessionDocumentId = null

        if (deltaSeconds <= 0) return

        saveCoordinator.enqueueSave {
            recentFilesRepository.updateReadingTime(docId, deltaSeconds)
        }
    }

    fun setFullScreen(enabled: Boolean) {
        _isFullScreen.value = enabled
    }

    fun toggleFullScreen() {
        _isFullScreen.value = !_isFullScreen.value
    }

    fun resetFullScreen() {
        _isFullScreen.value = false
    }

    fun persistReadingState(
        documentId: String,
        currentPage: Int,
        totalPages: Int,
        isReadOnly: Boolean,
        sync: Boolean = false
    ) {
        if (documentId.isBlank()) {
            return
        }

        saveCoordinator.enqueueSave {
            readingPositionRepository.update(
                ReaderSessionState(
                    documentId = documentId,
                    currentPage = currentPage,
                    isSaving = false,
                    isReadOnly = isReadOnly,
                    pendingSaveCount = saveCoordinator.pendingSaveCount()
                )
            )
            recentFilesRepository.updateReadingProgress(
                documentId = documentId,
                currentPage = currentPage,
                totalPages = totalPages
            )
        }

        if (sync) {
            saveCoordinator.flushBlocking()
        }
    }

    fun closeCoordinator() {
        saveCoordinator.close()
    }
}
