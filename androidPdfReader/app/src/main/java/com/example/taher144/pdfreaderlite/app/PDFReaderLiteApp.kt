package com.example.taher144.pdfreaderlite.app

import android.app.Application
import android.content.Context

class PDFReaderLiteApp : Application() {
    val appContainer: AppContainer by lazy { AppContainer(this) }
}

val Context.appContainer: AppContainer
    get() = (applicationContext as PDFReaderLiteApp).appContainer
