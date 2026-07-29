# Task 14: PDF Read Aloud

## Goal
Add a **Read Aloud** control to the existing PDF reader. Tapping it reads the open PDF’s text (English) with Android’s built-in `TextToSpeech` engine, supports **pause / resume / stop**, and keeps reading **in the background** (screen off, app minimized) for long PDFs (100+ pages).

No LLM, no network calls, no subscription — everything runs on-device.

## What to build
- Add a “Read Aloud” action to the PDF reader toolbar (`menu_pdf_reader.xml` / `AndroidxPdfReaderActivity`).
- Tapping it starts on-device TTS for the currently open document.
- Support pause, resume, and stop from both the in-app UI and a persistent media notification (lock screen / status bar).
- Playback continues when the screen is off or the app is backgrounded, via a foreground service.
- Show reading progress (e.g. “Page 12 / 40”) in the UI and notification.
- Handle PDFs with no extractable text (scanned/image-only) with a clear message — no silent failure.

## Architecture overview

```
AndroidxPdfReaderActivity (UI)
   │  tap "Read Aloud"
   ▼
ReadAloudService (Foreground Service)
   │  owns TextToSpeech instance + MediaSession
   │  extracts text, chunks it, feeds TTS queue
   ▼
Notification (lock screen / status bar: pause / resume / stop)
```

Key principle: **the Activity only sends commands** (start / pause / resume / stop) to the Service. The Service owns the TTS/audio lifecycle so playback survives navigation, backgrounding, and screen lock.

## Implementation notes

### Permissions & Manifest
- Add `POST_NOTIFICATIONS` (Android 13+ / API 33+) and request it at runtime before starting playback.
- Add `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` in `AndroidManifest.xml`.
- Declare `ReadAloudService` with `android:foregroundServiceType="mediaPlayback"`.
- Add `WAKE_LOCK` (recommended for long PDFs so the CPU does not deep-sleep mid-sentence when the screen is off).

### Text extraction from PDF
- Reuse the open document `Uri` already available in the reader (`AndroidxPdfReaderActivity` / `ReaderViewModel`).
- Extract text per page using the existing androidx.pdf document APIs where possible (same stack as search in task 13 / `ReaderPdfViewerFragment.searchDocument`). If page text access is insufficient, add a dedicated extraction path (e.g. PdfBox-Android) rather than blocking the UI thread.
- Detect empty extraction for a page/document and show a message such as “This page has no readable text”.
- Cache extracted text in memory (or a temp file for very large PDFs) so pause/resume does not re-parse the whole document.

### Chunking strategy (critical for long PDFs)
Android TTS has a per-utterance character limit (`TextToSpeech.getMaxSpeechInputLength()`, ~4000 chars on most devices) — do **not** pass the entire PDF as one utterance.

- Split extracted text into TTS-safe chunks:
  - Prefer paragraph/sentence boundaries (avoid cutting mid-sentence).
  - Merge small chunks up to just under the max length.
- Assign each chunk a stable ID (e.g. `pageIndex_chunkIndex`) for precise resume.
- Queue with `TextToSpeech.speak(text, QUEUE_ADD, params, utteranceId)`.
- Track the current chunk index as the playback position.

### ReadAloudService (foreground service)
- Create `ReadAloudService : Service()`.
- On start, call `startForeground()` immediately with a persistent notification (required within a few seconds on modern Android).
- Initialize `TextToSpeech` inside the service (not the Activity).
- Set language to `Locale.ENGLISH` / `Locale.US`; handle `LANG_MISSING_DATA` / `LANG_NOT_SUPPORTED` and prompt to install a voice pack if needed.
- Implement `UtteranceProgressListener`:
  - `onStart` → update currently reading chunk state
  - `onDone` → advance to next chunk, update progress
  - `onError` → skip chunk gracefully, log, continue if possible
- Handle commands via Intent actions (or a bound interface):
  - `ACTION_START` (PDF reference + starting page/chunk)
  - `ACTION_PAUSE` → `tts.stop()` (no native pause — see below)
  - `ACTION_RESUME` → re-queue from last known chunk index
  - `ACTION_STOP` → `tts.stop()`, clear queue, `stopForeground()`, `stopSelf()`
- Acquire a **partial WakeLock** while speaking; release on pause/stop.
- Call `tts.shutdown()` in `onDestroy()`.

### Pause / resume / stop
Android TTS has no true pause — only `stop()`, which clears the queue:

- **Pause** = `tts.stop()` but **keep** the current chunk index; notification shows play.
- **Resume** = re-queue from the saved chunk index; notification shows pause.
- **Stop** = `tts.stop()`, reset/discard position, dismiss notification, stop the service.
- Persist last chunk index + PDF identifier (e.g. SharedPreferences) so if the OS kills the service, the user can resume roughly where they left off.

### UI: PDF reader screen
Suggested touchpoints:
- `menu_pdf_reader.xml` — add Read Aloud / pause / stop items (alongside search)
- `AndroidxPdfReaderActivity` — wire menu actions and observe playback state
- `ReaderViewModel` — expose reading state (`Idle` / `Reading` / `Paused`, current page) for the toolbar

Button behavior:
- Not reading → “Read Aloud” → start service with current PDF
- Reading → “Pause” → send pause
- Paused → “Resume” → send resume
- Add a “Stop” control once reading has started (menu item or small playback bar)

Bind to the service (or shared Flow / LiveData) so button labels stay in sync if the user returns mid-playback.

Optional nice-to-have: auto-scroll the PDF view to the page currently being read.

### Notification controls (background / lock screen)
- `NotificationCompat.Builder`:
  - Title: PDF file name
  - Content: e.g. “Reading page 12 of 40”
  - Actions: pause/resume toggle and stop
- Integrate `MediaSessionCompat` + `PlaybackStateCompat` for lock-screen / media widgets and headset / Bluetooth play-pause.
- Notification actions send matching `ACTION_*` Intents back into the service.

### Long PDF handling
- Extract/chunk off the main thread (coroutine); show a brief loading indicator on first tap if needed.
- Prefer lazy page-by-page extraction as reading approaches a page if memory is a concern.
- Show progress in UI and notification.
- Validate with a long PDF (200+ pages): no ANR, service survives 30+ minutes with screen off, memory does not balloon.

### Edge cases
- User swipes away the app while reading → foreground service keeps running until Stop.
- User opens a **different** PDF while one is being read → stop current playback (or confirm) before starting the new one.
- TTS engine missing → clear message + path to install via Settings.
- Request audio focus on start; release on stop; on interruption (e.g. phone call) pause and do **not** auto-resume after.
- Optional / lower priority: OEM battery whitelist prompt if playback dies unexpectedly (Xiaomi, Samsung, etc.).

### Localization
Add string resources in `strings.xml` (see task 09 conventions), e.g.:
- `pdf_reader_read_aloud` — “Read Aloud”
- `pdf_reader_read_aloud_pause` — “Pause”
- `pdf_reader_read_aloud_resume` — “Resume”
- `pdf_reader_read_aloud_stop` — “Stop”
- `pdf_reader_read_aloud_progress` — “Reading page %1$d of %2$d”
- `pdf_reader_read_aloud_no_text` — “This PDF has no readable text”
- `pdf_reader_read_aloud_tts_unavailable` — message for missing TTS engine

### Interaction with other features
- Full-screen mode (task 12): Read Aloud lives in the toolbar, which is hidden in full screen — user exits full screen to start/control from the menu; notification controls still work in full screen / background.
- Search (task 13): independent; reading can continue while search is unused. Opening a different document stops (or confirms stop of) current read-aloud.

## Suggested build order
1. Text extraction + chunking (log output only) — verify correctness first.
2. Basic `ReadAloudService` with start/stop and foreground notification.
3. Wire toolbar “Read Aloud” in `AndroidxPdfReaderActivity` to start/stop.
4. Pause/resume via chunk-index tracking.
5. MediaSession + notification action buttons.
6. Wake lock + long-PDF / lazy extraction.
7. Polish: progress display, optional page auto-scroll, edge cases.

## Acceptance criteria
- A Read Aloud control appears in the reader toolbar when a PDF is open.
- Tapping it starts English TTS for the open document’s extractable text.
- Pause / resume / stop work from both in-app controls and the notification.
- Audio continues with the screen locked or the app backgrounded.
- Progress (page X of Y) appears in the notification (and preferably in the UI).
- Scanned / no-text PDFs show a graceful message with no crash.
- Starting Read Aloud on a different PDF stops (or confirms stop of) the previous playback.
- Service stops and notification dismisses after Stop; verified via `adb shell dumpsys activity services` if needed.
- Long (200+ page) PDF does not ANR during extraction and remains stable for extended playback.
- Missing TTS / unsupported language is handled with a clear user message.

## Depends on
- Task 01 (open PDF from device storage)
- Existing reader shell: `AndroidxPdfReaderActivity`, `ReaderPdfViewerFragment`, `ReaderViewModel`
- Task 09 (localization-ready strings) for string resource conventions
- Task 13 helpful for text/search patterns on `PdfDocument`, but not strictly required

## Out of scope
- Non-English PDFs / language auto-detection
- Custom / AI neural voices (device built-in TTS only)
- Highlighting text as it is spoken (nice future enhancement)
- Cross-platform sync of read-aloud position with iOS
