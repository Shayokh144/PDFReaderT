package com.example.taher144.pdfreaderlite.ui.reader

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.example.taher144.pdfreaderlite.app.appContainer
import com.example.taher144.pdfreaderlite.data.model.ReaderSessionState
import com.example.taher144.pdfreaderlite.reader.PdfSaveCoordinator

class ReaderViewModel(
    application: Application
) : AndroidViewModel(application) {
    private val appContainer = application.applicationContext.appContainer
    private val readingPositionRepository = appContainer.readingPositionRepository
    private val recentFilesRepository = appContainer.recentFilesRepository
    private val saveCoordinator = PdfSaveCoordinator()

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
