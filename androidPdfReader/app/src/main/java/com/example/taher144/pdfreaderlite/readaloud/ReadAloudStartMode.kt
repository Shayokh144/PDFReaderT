package com.example.taher144.pdfreaderlite.readaloud

/**
 * Where Read Aloud should begin when the user starts playback.
 */
enum class ReadAloudStartMode {
    /** Start at the page currently visible in the reader. */
    CURRENT_PAGE,

    /** Start at the first page of the document. */
    BEGINNING,

    /** Resume from the last persisted read-aloud position for this document. */
    SAVED
}
