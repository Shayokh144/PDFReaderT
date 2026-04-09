package com.example.taher144.pdfreaderlite.reader

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicInteger

class PdfSaveCoordinator {
    private val mutex = Mutex()
    private val pendingSaves = AtomicInteger(0)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile
    private var latestSave = CompletableDeferred(Unit)

    fun enqueueSave(saveBlock: suspend () -> Unit) {
        val nextSave = CompletableDeferred(Unit)
        val previousSave = latestSave
        latestSave = nextSave
        pendingSaves.incrementAndGet()

        scope.launch {
            try {
                previousSave.await()
                mutex.withLock {
                    saveBlock()
                }
            } finally {
                pendingSaves.decrementAndGet()
                nextSave.complete(Unit)
            }
        }
    }

    suspend fun flush() {
        latestSave.await()
    }

    fun flushBlocking() {
        runBlocking {
            flush()
        }
    }

    fun pendingSaveCount(): Int = pendingSaves.get()

    fun close() {
        scope.cancel()
    }
}
