package com.example.taher144.pdfreaderlite.data.repository

import android.content.Context
import androidx.datastore.preferences.preferencesDataStore

val Context.pdfReaderDataStore by preferencesDataStore(name = "pdf_reader_preferences")
