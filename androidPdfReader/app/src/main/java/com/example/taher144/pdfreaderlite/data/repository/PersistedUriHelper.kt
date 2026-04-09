package com.example.taher144.pdfreaderlite.data.repository

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns

class PersistedUriHelper(
    private val context: Context
) {
    fun takePersistableReadPermission(uri: Uri) {
        runCatching {
            context.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
    }

    fun canRead(uri: Uri): Boolean {
        return runCatching {
            context.contentResolver.openInputStream(uri)?.close()
            true
        }.getOrDefault(false)
    }

    fun getDisplayName(uri: Uri): String? {
        return queryDocumentColumn(uri, OpenableColumns.DISPLAY_NAME)
    }

    fun getFileSizeBytes(uri: Uri): Long? {
        return queryDocumentColumn(uri, OpenableColumns.SIZE)?.toLongOrNull()
    }

    private fun queryDocumentColumn(uri: Uri, columnName: String): String? {
        return runCatching {
            context.contentResolver.query(uri, arrayOf(columnName), null, null, null)?.use { cursor ->
                val columnIndex = cursor.getColumnIndex(columnName)
                if (columnIndex == -1 || !cursor.moveToFirst()) {
                    null
                } else {
                    cursor.getString(columnIndex)
                }
            }
        }.getOrNull()
    }
}
