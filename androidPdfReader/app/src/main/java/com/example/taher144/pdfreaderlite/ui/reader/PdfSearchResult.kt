package com.example.taher144.pdfreaderlite.ui.reader

data class PdfSearchResult(
    val pageIndex: Int,
    val snippet: String,
    val matchIndex: Int,
    val matchLength: Int,
    val snippetMatchStartIndex: Int
)

data class SearchNavigationRequest(
    val pageIndex: Int,
    val matchIndex: Int,
    val matchLength: Int,
    val id: Long = System.currentTimeMillis()
)
