package com.example.taher144.pdfreaderlite.data.model

data class RecentPdfRecord(
    val id: String,
    val displayName: String,
    val persistedUri: String,
    val dateAdded: Long,
    val lastOpenedAt: Long,
    val fileSizeBytes: Long?,
    val lastPage: Int,
    val totalPages: Int
)
