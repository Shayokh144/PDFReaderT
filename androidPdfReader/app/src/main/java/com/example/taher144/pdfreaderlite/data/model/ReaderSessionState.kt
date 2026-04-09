package com.example.taher144.pdfreaderlite.data.model

data class ReaderSessionState(
    val documentId: String,
    val currentPage: Int,
    val isSaving: Boolean = false,
    val isReadOnly: Boolean = false,
    val pendingSaveCount: Int = 0
)
