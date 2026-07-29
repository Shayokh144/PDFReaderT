package com.example.taher144.pdfreaderlite.readaloud

data class ReadAloudChunk(
    val id: String,
    val pageIndex: Int,
    val text: String
) {
    companion object {
        fun idFor(pageIndex: Int, chunkIndex: Int): String = "${pageIndex}_$chunkIndex"
    }
}
