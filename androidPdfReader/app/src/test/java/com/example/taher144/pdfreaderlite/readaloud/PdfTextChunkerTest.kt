package com.example.taher144.pdfreaderlite.readaloud

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PdfTextChunkerTest {

    @Test
    fun chunkPageText_keepsShortParagraphAsSingleChunk() {
        val chunks = PdfTextChunker.chunkPageText(
            pageIndex = 2,
            text = "Hello world. This is a short page.",
            maxLength = 4000
        )
        assertEquals(1, chunks.size)
        assertEquals("2_0", chunks[0].id)
        assertEquals(2, chunks[0].pageIndex)
        assertTrue(chunks[0].text.contains("Hello world"))
    }

    @Test
    fun chunkPageText_splitsOnParagraphBoundaries() {
        val text = buildString {
            append("A".repeat(100))
            append("\n\n")
            append("B".repeat(100))
        }
        val chunks = PdfTextChunker.chunkPageText(0, text, maxLength = 150)
        assertEquals(2, chunks.size)
        assertTrue(chunks[0].text.all { it == 'A' })
        assertTrue(chunks[1].text.all { it == 'B' })
    }

    @Test
    fun chunkPageText_respectsMaxLength() {
        val sentence = "This is a sentence that will be repeated. "
        val text = sentence.repeat(200)
        val maxLength = 500
        val chunks = PdfTextChunker.chunkPageText(1, text, maxLength)
        assertTrue(chunks.size > 1)
        chunks.forEach { chunk ->
            assertTrue(
                "Chunk exceeded maxLength: ${chunk.text.length}",
                chunk.text.length <= maxLength
            )
        }
    }

    @Test
    fun chunkPageText_emptyReturnsEmpty() {
        assertTrue(PdfTextChunker.chunkPageText(0, "   ", 1000).isEmpty())
    }
}
