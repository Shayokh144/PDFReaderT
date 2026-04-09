package com.example.taher144.pdfreaderlite.app

import android.content.Context
import com.example.taher144.pdfreaderlite.data.repository.PersistedUriHelper
import com.example.taher144.pdfreaderlite.data.repository.ReadingPositionRepository
import com.example.taher144.pdfreaderlite.data.repository.RecentFilesRepository
import com.example.taher144.pdfreaderlite.data.repository.UserPrefsReadingPositionRepository
import com.example.taher144.pdfreaderlite.data.repository.UserPrefsRecentFilesRepository
import com.example.taher144.pdfreaderlite.reader.AndroidxPdfEngine
import com.example.taher144.pdfreaderlite.reader.PdfEngine

class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    val persistedUriHelper: PersistedUriHelper by lazy {
        PersistedUriHelper(appContext)
    }

    val recentFilesRepository: RecentFilesRepository by lazy {
        UserPrefsRecentFilesRepository(appContext)
    }

    val readingPositionRepository: ReadingPositionRepository by lazy {
        UserPrefsReadingPositionRepository(appContext)
    }

    val pdfEngine: PdfEngine by lazy {
        AndroidxPdfEngine(appContext, persistedUriHelper)
    }
}
