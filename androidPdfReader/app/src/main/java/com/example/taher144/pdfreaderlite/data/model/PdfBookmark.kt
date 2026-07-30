package com.example.taher144.pdfreaderlite.data.model

/**
 * Single in-document reading bookmark. Coordinates are in PDF page space
 * (origin at top-left of the page), matching [androidx.pdf.PdfPoint].
 */
data class PdfBookmark(
    val documentId: String,
    val pageIndex: Int,
    val x: Float,
    val y: Float,
)
