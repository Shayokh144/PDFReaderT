package com.example.taher144.pdfreaderlite.readaloud

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat as MediaNotificationCompat
import androidx.pdf.PdfDocument
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.reader.AndroidxPdfReaderActivity
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

class ReadAloudService : Service() {

    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(serviceJob + Dispatchers.Main.immediate)

    private lateinit var extractor: PdfTextExtractor
    private lateinit var positionStore: ReadAloudPositionStore
    private lateinit var speechRateStore: ReadAloudSpeechRateStore
    private lateinit var audioManager: AudioManager
    private lateinit var notificationManager: NotificationManager

    private var tts: TextToSpeech? = null
    private var mediaSession: MediaSessionCompat? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var speechRate: Float = ReadAloudSpeechRateStore.DEFAULT_RATE

    private var pdfDocument: PdfDocument? = null
    private var documentId: String = ""
    private var documentUri: Uri? = null
    private var documentTitle: String = ""
    private var totalPages: Int = 0
    private var maxSpeechLength: Int = DEFAULT_MAX_SPEECH_LENGTH

    private var pageChunks: List<ReadAloudChunk> = emptyList()
    private var currentPageIndex: Int = 0
    private var currentChunkIndex: Int = 0
    private var isPaused: Boolean = false
    private var isStopping: Boolean = false
    private var hasAudioFocus: Boolean = false
    /** Only callbacks for this utterance id are honored; cleared on pause/stop to ignore TTS stop races. */
    private var activeUtteranceId: String? = null

    override fun onCreate() {
        super.onCreate()
        extractor = PdfTextExtractor(this)
        positionStore = ReadAloudPositionStore(this)
        speechRateStore = ReadAloudSpeechRateStore(this)
        speechRate = speechRateStore.getRate()
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        ensureNotificationChannel()
        mediaSession = MediaSessionCompat(this, MEDIA_SESSION_TAG).apply {
            setCallback(mediaSessionCallback)
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val uri = intent.data
                val id = intent.getStringExtra(EXTRA_DOCUMENT_ID).orEmpty()
                val title = intent.getStringExtra(EXTRA_TITLE)
                    ?: uri?.let { resolveDisplayName(it) }
                    ?: getString(R.string.pdf_reader_unknown_file_name)
                val startPage = intent.getIntExtra(EXTRA_START_PAGE, 0).coerceAtLeast(0)
                val startMode = intent.getStringExtra(EXTRA_START_MODE)
                    ?.let { runCatching { ReadAloudStartMode.valueOf(it) }.getOrNull() }
                    ?: ReadAloudStartMode.CURRENT_PAGE
                if (uri == null || id.isBlank()) {
                    stopSelfSafely()
                    return START_NOT_STICKY
                }
                startReading(uri, id, title, startPage, startMode)
            }
            ACTION_PAUSE -> {
                ensureForegroundForCommand()
                pauseReading()
            }
            ACTION_RESUME -> {
                ensureForegroundForCommand()
                resumeReading()
            }
            ACTION_STOP -> stopReading()
            ACTION_SET_SPEECH_RATE -> {
                val rate = intent.getFloatExtra(
                    EXTRA_SPEECH_RATE,
                    ReadAloudSpeechRateStore.DEFAULT_RATE
                )
                applySpeechRate(rate, restartCurrentChunk = true)
            }
            ACTION_TOGGLE -> {
                ensureForegroundForCommand()
                when (_playbackState.value) {
                    is ReadAloudPlaybackState.Playing -> pauseReading()
                    is ReadAloudPlaybackState.Paused -> resumeReading()
                    else -> Unit
                }
            }
            else -> {
                if (!isForegroundStarted()) {
                    startForegroundWithState(
                        ReadAloudPlaybackState.Preparing(
                            documentId = documentId.ifBlank { "unknown" },
                            title = documentTitle.ifBlank { getString(R.string.app_name) }
                        )
                    )
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isStopping = true
        serviceScope.cancel()
        releaseWakeLock()
        abandonAudioFocus()
        shutdownTts()
        closeDocument()
        mediaSession?.release()
        mediaSession = null
        if (_playbackState.value !is ReadAloudPlaybackState.Error) {
            publishState(ReadAloudPlaybackState.Idle)
        }
        super.onDestroy()
    }

    private fun startReading(
        uri: Uri,
        id: String,
        title: String,
        startPage: Int,
        startMode: ReadAloudStartMode
    ) {
        // Restart if a different document is already active.
        if (_playbackState.value.isActive && documentId.isNotBlank() && documentId != id) {
            resetPlaybackInternal(keepForeground = true)
        }

        documentUri = uri
        documentId = id
        documentTitle = title
        isPaused = false
        isStopping = false
        currentPageIndex = 0
        currentChunkIndex = 0

        val preparing = ReadAloudPlaybackState.Preparing(documentId = id, title = title)
        publishState(preparing)
        startForegroundWithState(preparing)

        serviceScope.launch {
            val ttsReady = ensureTtsReady()
            if (!ttsReady) {
                failAndStop(ReadAloudPlaybackState.Error.Reason.TTS_UNAVAILABLE, id)
                return@launch
            }

            val languageOk = configureLanguage()
            if (!languageOk) {
                failAndStop(ReadAloudPlaybackState.Error.Reason.LANGUAGE_UNSUPPORTED, id)
                return@launch
            }

            maxSpeechLength = (TextToSpeech.getMaxSpeechInputLength() - 100)
                .coerceAtLeast(MIN_CHUNK_LENGTH)

            val opened = runCatching { extractor.open(uri) }.getOrNull()
            if (opened == null) {
                failAndStop(ReadAloudPlaybackState.Error.Reason.OPEN_FAILED, id)
                return@launch
            }
            pdfDocument = opened
            totalPages = opened.pageCount
            val lastPageIndex = (totalPages - 1).coerceAtLeast(0)

            when (startMode) {
                ReadAloudStartMode.BEGINNING -> {
                    currentPageIndex = 0
                    currentChunkIndex = 0
                }
                ReadAloudStartMode.CURRENT_PAGE -> {
                    currentPageIndex = startPage.coerceIn(0, lastPageIndex)
                    currentChunkIndex = 0
                }
                ReadAloudStartMode.SAVED -> {
                    val saved = positionStore.load(id)
                    if (saved != null) {
                        currentPageIndex = saved.first.coerceIn(0, lastPageIndex)
                        currentChunkIndex = saved.second.coerceAtLeast(0)
                    } else {
                        currentPageIndex = startPage.coerceIn(0, lastPageIndex)
                        currentChunkIndex = 0
                    }
                }
            }

            val hasText = extractor.hasAnyReadableText(opened, currentPageIndex)
            if (!hasText) {
                failAndStop(ReadAloudPlaybackState.Error.Reason.NO_TEXT, id)
                return@launch
            }

            if (!ensureAudioFocus()) {
                failAndStop(ReadAloudPlaybackState.Error.Reason.TTS_UNAVAILABLE, id)
                return@launch
            }

            val loaded = loadChunksForPage(currentPageIndex)
            if (!loaded) {
                val advanced = advanceToNextReadablePage()
                if (!advanced) {
                    failAndStop(ReadAloudPlaybackState.Error.Reason.NO_TEXT, id)
                    return@launch
                }
            }
            if (currentChunkIndex >= pageChunks.size) {
                currentChunkIndex = 0
            }

            isPaused = false
            acquireWakeLock()
            speakCurrentChunk()
        }
    }

    private fun pauseReading() {
        if (_playbackState.value !is ReadAloudPlaybackState.Playing) return
        isPaused = true
        // Invalidate before stop() so async onDone/onError from the interrupted utterance are ignored.
        activeUtteranceId = null
        tts?.stop()
        releaseWakeLock()
        positionStore.save(documentId, currentPageIndex, currentChunkIndex)
        val paused = ReadAloudPlaybackState.Paused(
            documentId = documentId,
            title = documentTitle,
            currentPage = currentPageIndex,
            totalPages = totalPages
        )
        publishState(paused)
        updateNotification(paused)
        updateMediaSession(paused)
    }

    private fun resumeReading() {
        if (_playbackState.value !is ReadAloudPlaybackState.Paused) return
        isPaused = false
        isStopping = false
        serviceScope.launch {
            if (!ensureAudioFocus()) {
                // Keep paused UI if we cannot get audio focus.
                isPaused = true
                return@launch
            }
            if (tts == null && !ensureTtsReady()) {
                failAndStop(ReadAloudPlaybackState.Error.Reason.TTS_UNAVAILABLE, documentId)
                return@launch
            }
            if (pageChunks.isEmpty()) {
                val loaded = loadChunksForPage(currentPageIndex)
                if (!loaded && !advanceToNextReadablePage()) {
                    failAndStop(ReadAloudPlaybackState.Error.Reason.NO_TEXT, documentId)
                    return@launch
                }
            }
            if (currentChunkIndex >= pageChunks.size) {
                currentChunkIndex = 0
            }
            acquireWakeLock()
            speakCurrentChunk()
        }
    }

    private fun stopReading() {
        isStopping = true
        isPaused = false
        activeUtteranceId = null
        tts?.stop()
        positionStore.clear()
        resetPlaybackInternal(keepForeground = false)
        publishState(ReadAloudPlaybackState.Idle)
        stopSelfSafely()
    }

    private fun resetPlaybackInternal(keepForeground: Boolean) {
        tts?.stop()
        releaseWakeLock()
        abandonAudioFocus()
        closeDocument()
        pageChunks = emptyList()
        currentChunkIndex = 0
        if (!keepForeground) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        }
    }

    private suspend fun ensureTtsReady(): Boolean {
        if (tts != null) return true
        return suspendCancellableCoroutine { cont ->
            var completed = false
            lateinit var engine: TextToSpeech
            engine = TextToSpeech(applicationContext) { status ->
                if (completed) return@TextToSpeech
                completed = true
                if (status == TextToSpeech.SUCCESS) {
                    engine.setOnUtteranceProgressListener(utteranceListener)
                    tts = engine
                    cont.resume(true)
                } else {
                    runCatching { engine.shutdown() }
                    tts = null
                    cont.resume(false)
                }
            }
            cont.invokeOnCancellation {
                runCatching {
                    engine.stop()
                    engine.shutdown()
                }
                tts = null
            }
        }
    }

    private fun configureLanguage(): Boolean {
        val engine = tts ?: return false
        val result = engine.setLanguage(Locale.US)
        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
            return false
        }
        speechRate = speechRateStore.getRate()
        engine.setSpeechRate(speechRate)
        return true
    }

    private fun applySpeechRate(rate: Float, restartCurrentChunk: Boolean) {
        speechRate = rate.coerceIn(
            ReadAloudSpeechRateStore.MIN_RATE,
            ReadAloudSpeechRateStore.MAX_RATE
        )
        speechRateStore.setRate(speechRate)
        tts?.setSpeechRate(speechRate)
        // Re-speak the current chunk so the new rate applies immediately while playing.
        if (restartCurrentChunk &&
            !isPaused &&
            !isStopping &&
            _playbackState.value is ReadAloudPlaybackState.Playing
        ) {
            activeUtteranceId = null
            tts?.stop()
            speakCurrentChunk()
        }
    }

    private suspend fun loadChunksForPage(pageIndex: Int): Boolean {
        val document = pdfDocument ?: return false
        if (pageIndex !in 0 until totalPages) return false
        val text = extractor.extractPageText(document, pageIndex)
        pageChunks = PdfTextChunker.chunkPageText(pageIndex, text, maxSpeechLength)
        return pageChunks.isNotEmpty()
    }

    private suspend fun advanceToNextReadablePage(): Boolean {
        var page = currentPageIndex + 1
        while (page < totalPages) {
            currentPageIndex = page
            currentChunkIndex = 0
            if (loadChunksForPage(page)) return true
            page++
        }
        return false
    }

    private fun speakCurrentChunk() {
        if (isStopping || isPaused) return
        val engine = tts ?: return
        val chunk = pageChunks.getOrNull(currentChunkIndex)
        if (chunk == null) {
            serviceScope.launch { onPageFinished() }
            return
        }

        val playing = ReadAloudPlaybackState.Playing(
            documentId = documentId,
            title = documentTitle,
            currentPage = chunk.pageIndex,
            totalPages = totalPages
        )
        publishState(playing)
        updateNotification(playing)
        updateMediaSession(playing)
        positionStore.save(documentId, chunk.pageIndex, currentChunkIndex)

        activeUtteranceId = chunk.id
        val params = BundleParams()
        engine.speak(chunk.text, TextToSpeech.QUEUE_FLUSH, params, chunk.id)
    }

    private suspend fun onPageFinished() {
        if (isStopping || isPaused) return
        val advanced = advanceToNextReadablePage()
        if (advanced) {
            speakCurrentChunk()
        } else {
            // Finished entire document.
            positionStore.clear()
            publishState(ReadAloudPlaybackState.Idle)
            stopSelfSafely()
        }
    }

    private fun onChunkDone(utteranceId: String?) {
        if (isStopping || isPaused) return
        // Ignore stale callbacks from tts.stop() during pause or from a previous utterance.
        if (utteranceId == null || utteranceId != activeUtteranceId) return
        activeUtteranceId = null
        currentChunkIndex++
        if (currentChunkIndex < pageChunks.size) {
            speakCurrentChunk()
        } else {
            serviceScope.launch { onPageFinished() }
        }
    }

    private fun onChunkError(utteranceId: String?) {
        if (isStopping || isPaused) return
        if (utteranceId == null || utteranceId != activeUtteranceId) return
        Log.w(TAG, "TTS error for utterance=$utteranceId — skipping chunk")
        activeUtteranceId = null
        currentChunkIndex++
        if (currentChunkIndex < pageChunks.size) {
            speakCurrentChunk()
        } else {
            serviceScope.launch { onPageFinished() }
        }
    }

    private val utteranceListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) = Unit

        override fun onDone(utteranceId: String?) {
            serviceScope.launch { onChunkDone(utteranceId) }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) {
            serviceScope.launch { onChunkError(utteranceId) }
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            serviceScope.launch { onChunkError(utteranceId) }
        }

        override fun onStop(utteranceId: String?, interrupted: Boolean) {
            // Interrupted by stop()/pause — do not advance. Clear only if it was the active one.
            if (interrupted) {
                serviceScope.launch {
                    if (utteranceId != null && utteranceId == activeUtteranceId) {
                        activeUtteranceId = null
                    }
                }
            } else {
                serviceScope.launch { onChunkDone(utteranceId) }
            }
        }
    }

    private val mediaSessionCallback = object : MediaSessionCompat.Callback() {
        override fun onPlay() = resumeReading()
        override fun onPause() = pauseReading()
        override fun onStop() = stopReading()
    }

    private fun failAndStop(reason: ReadAloudPlaybackState.Error.Reason, id: String?) {
        val error = ReadAloudPlaybackState.Error(reason = reason, documentId = id)
        publishState(error)
        resetPlaybackInternal(keepForeground = false)
        // Briefly keep service so UI can observe the error, then stop.
        stopSelfSafely()
    }

    private fun publishState(state: ReadAloudPlaybackState) {
        _playbackState.value = state
    }

    private fun startForegroundWithState(state: ReadAloudPlaybackState) {
        val notification = buildNotification(state)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(state: ReadAloudPlaybackState) {
        notificationManager.notify(NOTIFICATION_ID, buildNotification(state))
    }

    private fun buildNotification(state: ReadAloudPlaybackState): Notification {
        val title = when (state) {
            is ReadAloudPlaybackState.Preparing -> state.title
            is ReadAloudPlaybackState.Playing -> state.title
            is ReadAloudPlaybackState.Paused -> state.title
            else -> documentTitle.ifBlank { getString(R.string.app_name) }
        }
        val content = when (state) {
            is ReadAloudPlaybackState.Preparing -> getString(R.string.pdf_reader_read_aloud_preparing)
            is ReadAloudPlaybackState.Playing -> getString(
                R.string.pdf_reader_read_aloud_progress,
                state.currentPage + 1,
                state.totalPages
            )
            is ReadAloudPlaybackState.Paused -> getString(
                R.string.pdf_reader_read_aloud_progress,
                state.currentPage + 1,
                state.totalPages
            )
            else -> getString(R.string.pdf_reader_read_aloud)
        }

        val contentIntent = documentUri?.let { uri ->
            PendingIntent.getActivity(
                this,
                0,
                AndroidxPdfReaderActivity.newIntent(
                    context = this,
                    documentId = documentId,
                    uri = uri,
                    initialPage = currentPageIndex
                ),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(title)
            .setContentText(content)
            .setContentIntent(contentIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(state is ReadAloudPlaybackState.Playing || state is ReadAloudPlaybackState.Preparing)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setStyle(
                MediaNotificationCompat.MediaStyle()
                    .setMediaSession(mediaSession?.sessionToken)
                    .setShowActionsInCompactView(0, 1)
            )

        when (state) {
            is ReadAloudPlaybackState.Playing, is ReadAloudPlaybackState.Preparing -> {
                builder.addAction(
                    android.R.drawable.ic_media_pause,
                    getString(R.string.pdf_reader_read_aloud_pause),
                    actionPendingIntent(ACTION_PAUSE, 1)
                )
            }
            is ReadAloudPlaybackState.Paused -> {
                builder.addAction(
                    android.R.drawable.ic_media_play,
                    getString(R.string.pdf_reader_read_aloud_resume),
                    actionPendingIntent(ACTION_RESUME, 2)
                )
            }
            else -> Unit
        }
        builder.addAction(
            android.R.drawable.ic_menu_close_clear_cancel,
            getString(R.string.pdf_reader_read_aloud_stop),
            actionPendingIntent(ACTION_STOP, 3)
        )

        return builder.build()
    }

    private fun updateMediaSession(state: ReadAloudPlaybackState) {
        val session = mediaSession ?: return
        val (page, total, playing) = when (state) {
            is ReadAloudPlaybackState.Playing -> Triple(state.currentPage, state.totalPages, true)
            is ReadAloudPlaybackState.Paused -> Triple(state.currentPage, state.totalPages, false)
            is ReadAloudPlaybackState.Preparing -> Triple(currentPageIndex, totalPages, false)
            else -> return
        }
        session.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, documentTitle)
                .putString(
                    MediaMetadataCompat.METADATA_KEY_ARTIST,
                    getString(R.string.pdf_reader_read_aloud_progress, page + 1, total)
                )
                .build()
        )
        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_STOP or
            PlaybackStateCompat.ACTION_PLAY_PAUSE
        val playbackState = if (playing) {
            PlaybackStateCompat.STATE_PLAYING
        } else {
            PlaybackStateCompat.STATE_PAUSED
        }
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(playbackState, PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1f)
                .build()
        )
    }

    private fun actionPendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, ReadAloudService::class.java).setAction(action)
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun ensureNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.pdf_reader_read_aloud_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = getString(R.string.pdf_reader_read_aloud_channel_description)
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun ensureForegroundForCommand() {
        val state = _playbackState.value
        if (state.isActive) {
            startForegroundWithState(state)
        }
    }

    private fun ensureAudioFocus(): Boolean {
        if (hasAudioFocus && audioFocusRequest != null) return true
        return requestAudioFocus()
    }

    private fun requestAudioFocus(): Boolean {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attrs)
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener { change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                        // Pause on interruption; do not auto-resume. Ignore CAN_DUCK.
                        hasAudioFocus = false
                        pauseReading()
                    }
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        hasAudioFocus = true
                    }
                }
            }
            .build()
        audioFocusRequest = request
        val result = audioManager.requestAudioFocus(request)
        hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasAudioFocus
    }

    private fun abandonAudioFocus() {
        audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        audioFocusRequest = null
        hasAudioFocus = false
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "PDFReaderLite:ReadAloud"
        ).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun shutdownTts() {
        tts?.stop()
        tts?.shutdown()
        tts = null
    }

    private fun closeDocument() {
        runCatching { pdfDocument?.close() }
        pdfDocument = null
    }

    private fun stopSelfSafely() {
        releaseWakeLock()
        abandonAudioFocus()
        closeDocument()
        shutdownTts()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun isForegroundStarted(): Boolean = _playbackState.value.isActive

    private fun resolveDisplayName(uri: Uri): String? {
        return runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
                }
        }.getOrNull()
    }

    /** Bundle helper avoiding an extra import clash with android.os.Bundle in TTS speak. */
    private fun BundleParams(): android.os.Bundle = android.os.Bundle()

    companion object {
        private const val TAG = "ReadAloudService"
        private const val CHANNEL_ID = "read_aloud"
        private const val NOTIFICATION_ID = 1401
        private const val MEDIA_SESSION_TAG = "ReadAloud"
        private const val DEFAULT_MAX_SPEECH_LENGTH = 3900
        private const val MIN_CHUNK_LENGTH = 200
        private const val WAKE_LOCK_TIMEOUT_MS = 60 * 60 * 1000L

        const val ACTION_START = "com.example.taher144.pdfreaderlite.readaloud.START"
        const val ACTION_PAUSE = "com.example.taher144.pdfreaderlite.readaloud.PAUSE"
        const val ACTION_RESUME = "com.example.taher144.pdfreaderlite.readaloud.RESUME"
        const val ACTION_STOP = "com.example.taher144.pdfreaderlite.readaloud.STOP"
        const val ACTION_TOGGLE = "com.example.taher144.pdfreaderlite.readaloud.TOGGLE"
        const val ACTION_SET_SPEECH_RATE =
            "com.example.taher144.pdfreaderlite.readaloud.SET_SPEECH_RATE"

        const val EXTRA_DOCUMENT_ID = "document_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_START_PAGE = "start_page"
        const val EXTRA_START_MODE = "start_mode"
        const val EXTRA_SPEECH_RATE = "speech_rate"

        private val _playbackState =
            MutableStateFlow<ReadAloudPlaybackState>(ReadAloudPlaybackState.Idle)
        val playbackState: StateFlow<ReadAloudPlaybackState> = _playbackState.asStateFlow()

        fun start(
            context: Context,
            documentId: String,
            uri: Uri,
            title: String?,
            startPage: Int,
            startMode: ReadAloudStartMode = ReadAloudStartMode.CURRENT_PAGE
        ) {
            val intent = Intent(context, ReadAloudService::class.java).apply {
                action = ACTION_START
                data = uri
                putExtra(EXTRA_DOCUMENT_ID, documentId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_START_PAGE, startPage)
                putExtra(EXTRA_START_MODE, startMode.name)
            }
            context.startForegroundService(intent)
        }

        fun pause(context: Context) {
            sendCommand(context, ACTION_PAUSE)
        }

        fun resume(context: Context) {
            sendCommand(context, ACTION_RESUME)
        }

        fun stop(context: Context) {
            sendCommand(context, ACTION_STOP)
        }

        fun setSpeechRate(context: Context, rate: Float) {
            // Always persist so the next start uses the chosen rate.
            ReadAloudSpeechRateStore(context).setRate(rate)
            if (!_playbackState.value.isActive) return
            val appContext = context.applicationContext
            val intent = Intent(appContext, ReadAloudService::class.java).apply {
                action = ACTION_SET_SPEECH_RATE
                putExtra(EXTRA_SPEECH_RATE, rate)
            }
            runCatching { appContext.startService(intent) }
        }

        private fun sendCommand(context: Context, action: String) {
            val appContext = context.applicationContext
            val intent = Intent(appContext, ReadAloudService::class.java).setAction(action)
            // Prefer startService for an already-running FGS; fall back to startForegroundService.
            val started = runCatching { appContext.startService(intent) }.isSuccess
            if (!started) {
                runCatching { ContextCompat.startForegroundService(appContext, intent) }
            }
        }
    }
}
