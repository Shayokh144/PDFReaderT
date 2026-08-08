package com.example.taher144.pdfreaderlite.data.repository

import android.net.Uri

/**
 * Abstraction over persistable URI permission and metadata lookups.
 * Keeps [PersistedUriHelper] swappable in ViewModel unit tests.
 */
interface PersistedUriAccess {
    fun takePersistableReadWritePermission(uri: Uri)
    fun canRead(uri: Uri): Boolean
    fun getDisplayName(uri: Uri): String?
    fun getFileSizeBytes(uri: Uri): Long?
}
