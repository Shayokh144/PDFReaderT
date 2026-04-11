package com.example.taher144.pdfreaderlite.ui.home

import android.app.Application
import android.net.Uri
import androidx.annotation.StringRes
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.app.appContainer
import com.example.taher144.pdfreaderlite.data.model.RecentPdfRecord
import com.example.taher144.pdfreaderlite.reader.ReaderLaunchRequest
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class HomeUiState(
    val recentFiles: List<RecentPdfRecord> = emptyList(),
    val isOpeningDocument: Boolean = false
)

sealed interface HomeEvent {
    data class OpenReader(val request: ReaderLaunchRequest) : HomeEvent
    data class ShowMessage(@StringRes val messageResId: Int) : HomeEvent
}

class HomeViewModel(
    application: Application
) : AndroidViewModel(application) {
    private val appContainer = application.applicationContext.appContainer
    private val recentFilesRepository = appContainer.recentFilesRepository
    private val readingPositionRepository = appContainer.readingPositionRepository
    private val persistedUriHelper = appContainer.persistedUriHelper
    private val pdfEngine = appContainer.pdfEngine

    private val isOpeningDocument = MutableStateFlow(false)
    private val _events = MutableSharedFlow<HomeEvent>()
    val events = _events.asSharedFlow()

    val uiState = combine(
        recentFilesRepository.recentFiles,
        isOpeningDocument
    ) { recentFiles, isOpening ->
        HomeUiState(
            recentFiles = recentFiles,
            isOpeningDocument = isOpening
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = HomeUiState()
    )

    fun onPdfPicked(uri: Uri) {
        viewModelScope.launch {
            isOpeningDocument.value = true
            try {
                persistedUriHelper.takePersistableReadWritePermission(uri)
                val document = pdfEngine.openDocument(uri)
                val now = System.currentTimeMillis()
                val displayName = persistedUriHelper.getDisplayName(uri)
                    ?: uri.lastPathSegment
                    ?: getApplication<Application>().getString(R.string.pdf_reader_unknown_file_name)
                val fileSizeBytes = persistedUriHelper.getFileSizeBytes(uri)
                val lastPage = readingPositionRepository.get(document.documentId)?.currentPage ?: 0

                recentFilesRepository.upsert(
                    RecentPdfRecord(
                        id = document.documentId,
                        displayName = displayName,
                        persistedUri = uri.toString(),
                        dateAdded = now,
                        lastOpenedAt = now,
                        fileSizeBytes = fileSizeBytes,
                        lastPage = lastPage,
                        totalPages = document.pageCount
                    )
                )

                _events.emit(
                    HomeEvent.OpenReader(
                        ReaderLaunchRequest(
                            documentId = document.documentId,
                            uri = uri,
                            initialPage = lastPage
                        )
                    )
                )
            } catch (_: Throwable) {
                _events.emit(HomeEvent.ShowMessage(R.string.pdf_reader_open_error_message))
            } finally {
                isOpeningDocument.value = false
            }
        }
    }

    fun onRecentFileSelected(record: RecentPdfRecord) {
        viewModelScope.launch {
            isOpeningDocument.value = true
            try {
                val uri = Uri.parse(record.persistedUri)
                if (!persistedUriHelper.canRead(uri)) {
                    recentFilesRepository.delete(record.id)
                    _events.emit(HomeEvent.ShowMessage(R.string.pdf_reader_recent_file_unavailable))
                    return@launch
                }

                persistedUriHelper.takePersistableReadWritePermission(uri)

                val document = pdfEngine.openDocument(uri)
                val lastPage = readingPositionRepository.get(record.id)?.currentPage ?: record.lastPage
                recentFilesRepository.upsert(
                    record.copy(
                        lastOpenedAt = System.currentTimeMillis(),
                        totalPages = document.pageCount
                    )
                )
                _events.emit(
                    HomeEvent.OpenReader(
                        ReaderLaunchRequest(
                            documentId = record.id,
                            uri = uri,
                            initialPage = lastPage
                        )
                    )
                )
            } catch (_: Throwable) {
                recentFilesRepository.delete(record.id)
                _events.emit(HomeEvent.ShowMessage(R.string.pdf_reader_recent_file_unavailable))
            } finally {
                isOpeningDocument.value = false
            }
        }
    }

    fun onRecentFileDeleted(documentId: String) {
        viewModelScope.launch {
            recentFilesRepository.delete(documentId)
        }
    }
}
