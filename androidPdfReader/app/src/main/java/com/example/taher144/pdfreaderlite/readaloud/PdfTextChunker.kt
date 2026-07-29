package com.example.taher144.pdfreaderlite.readaloud

/**
 * Splits page text into TTS-safe chunks under [maxLength], preferring paragraph and sentence
 * boundaries so utterances are not cut mid-sentence.
 */
object PdfTextChunker {
    private val paragraphSplit = Regex("\\n\\s*\\n+")
    private val sentenceSplit = Regex("(?<=[.!?])\\s+")

    fun chunkPageText(
        pageIndex: Int,
        text: String,
        maxLength: Int
    ): List<ReadAloudChunk> {
        require(maxLength > 0) { "maxLength must be positive" }
        val normalized = text.replace("\r\n", "\n").trim()
        if (normalized.isEmpty()) return emptyList()

        val pieces = mutableListOf<String>()
        for (paragraph in normalized.split(paragraphSplit)) {
            val trimmedParagraph = paragraph.trim()
            if (trimmedParagraph.isEmpty()) continue
            if (trimmedParagraph.length <= maxLength) {
                pieces.add(trimmedParagraph)
            } else {
                pieces.addAll(splitLongParagraph(trimmedParagraph, maxLength))
            }
        }

        val merged = mergePieces(pieces, maxLength)
        return merged.mapIndexed { index, chunkText ->
            ReadAloudChunk(
                id = ReadAloudChunk.idFor(pageIndex, index),
                pageIndex = pageIndex,
                text = chunkText
            )
        }
    }

    private fun splitLongParagraph(paragraph: String, maxLength: Int): List<String> {
        val sentences = paragraph.split(sentenceSplit).map { it.trim() }.filter { it.isNotEmpty() }
        if (sentences.isEmpty()) return hardSplit(paragraph, maxLength)

        val result = mutableListOf<String>()
        for (sentence in sentences) {
            if (sentence.length <= maxLength) {
                result.add(sentence)
            } else {
                result.addAll(hardSplit(sentence, maxLength))
            }
        }
        return result
    }

    private fun mergePieces(pieces: List<String>, maxLength: Int): List<String> {
        if (pieces.isEmpty()) return emptyList()
        val merged = mutableListOf<String>()
        val builder = StringBuilder()

        fun flush() {
            if (builder.isNotEmpty()) {
                merged.add(builder.toString())
                builder.clear()
            }
        }

        for (piece in pieces) {
            when {
                builder.isEmpty() -> builder.append(piece)
                builder.length + 1 + piece.length <= maxLength -> {
                    builder.append(' ').append(piece)
                }
                else -> {
                    flush()
                    builder.append(piece)
                }
            }
        }
        flush()
        return merged
    }

    private fun hardSplit(text: String, maxLength: Int): List<String> {
        if (text.length <= maxLength) return listOf(text)
        val parts = mutableListOf<String>()
        var start = 0
        while (start < text.length) {
            var end = minOf(start + maxLength, text.length)
            if (end < text.length) {
                val space = text.lastIndexOf(' ', end - 1)
                if (space > start) {
                    end = space
                }
            }
            parts.add(text.substring(start, end).trim())
            start = if (end < text.length && text[end].isWhitespace()) end + 1 else end
        }
        return parts.filter { it.isNotEmpty() }
    }
}
