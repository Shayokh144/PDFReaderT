package com.example.taher144.pdfreaderlite

import org.junit.Test
import androidx.pdf.PdfDocument

class PdfDocumentReflectionTest {
    @Test
    fun dumpMethods() {
        val methods = PdfDocument::class.java.methods
        methods.forEach { println(it.name) }
    }
}
