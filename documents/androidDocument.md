# Android reader features (`androidPdfReader`)

This document describes implemented reader features in the Android module `androidPdfReader`. It started as the highlight deep-dive and now also covers **bookmarks** (and briefly points at other shipped work).

---

# Highlights

Based on `ReaderPdfSelectionConfigurator.kt`, `PdfHighlightPersistence.kt`, `UserPdfHighlightsRepository.kt`, and `ReaderPdfViewerFragment.kt`.

## Overview

The highlight feature has these main parts:

1. Text selection is handled by AndroidX **`PdfView`** (Jetpack PDF viewer); the app customizes the selection context menu.
2. **`ReaderPdfSelectionConfigurator`** adds a **`Highlight`** action next to **`Copy`** and **`Select All`**, and removes classifier “smart actions” for a consistent menu.
3. Highlights are shown **immediately** via **`PdfView.setHighlights`** (overlay `Highlight` objects with `PdfRect` + color).
4. **Persistence is two-layered**:
   - **App storage (primary for reopening):** rectangles are appended per **`documentId`** in **DataStore** (`UserPrefsUserPdfHighlightsRepository`).
   - **PDF file (when possible):** **`EditablePdfDocument.applyEdits`** inserts real highlight annotations, then **`PdfWriteHandle.writeTo`** writes bytes back to the **`Uri`**—only if **`ContentResolver.openFileDescriptor(uri, "rw")`** succeeds.

5. On document load, saved overlays are **restored** from DataStore and applied with **`setHighlights`** again (never **`runBlocking`** on the main thread for DataStore; that can deadlock).

## Text selection and menu behavior

- **`PdfView`** exposes text selection; the current selection is a **`Selection`**, which for text is **`TextSelection`** (`text` + **`bounds`**: a list of **`PdfRect`**, typically one rect per line).
- The viewer builds default menu items (copy, select all, and optional smart actions from **`TextClassifier`**).
- The app registers a **`PdfView.SelectionMenuItemPreparer`** that:
  - Removes items whose key is **`PdfSelectionMenuKeys.SmartActionKey`**.
  - Appends a **`SelectionMenuComponent`** for **`Highlight`** (custom key object), with label/description from **`strings.xml`**.

The built-in **`PdfViewerFragment`** annotation **toolbox (pen FAB)** is hidden by overriding **`onRequestImmersiveMode`** and **`onLoadDocumentSuccess`** to keep **`isToolboxVisible = false`**, so highlights are driven from the text menu only—not the separate system “annotate” intent flow.

## Applying highlights (immediate feedback)

When the user taps **Highlight**:

1. Read **`pdfView.currentSelection`** as **`TextSelection`** (if not text, only **`close()`** the menu).
2. For each bound in **`selection.bounds`**, append **`Highlight(PdfRect, colorArgb)`** to a **session list** shared with the fragment.
3. Call **`pdfView.setHighlights(sessionHighlights.toList())`** on the **main thread** so the yellow overlay appears in the same gesture.
4. **`close()`** the selection menu session and **`pdfView.clearCurrentSelection()`** so handles disappear; overlay rectangles remain.

Default color is **`PdfHighlightPersistence.DefaultHighlightColorArgb`** (translucent yellow).

## Saving highlights

### A. App-local storage (always attempted in background)

On a **background dispatcher**, after the overlay:

- **`UserPdfHighlightsRepository.appendFromTextSelection(documentId, selection, colorArgb)`** loads the JSON blob from DataStore, appends one JSON object per **`PdfRect`** (page, left, top, right, bottom, color), and writes back.

**`documentId`** matches **`ReaderLaunchRequest.documentId`** (same id used for reading position and recents). It is passed into **`ReaderPdfViewerFragment`** via fragment arguments and into **`AndroidxPdfReaderActivity`** from the reader intent.

This path **does not require** write access to the PDF file, so highlights **survive app restarts** and **read-only URIs** as long as the same logical document id is used.

### B. Writing into the PDF file (best effort)

If **`pdfView.pdfDocument`** is an **`EditablePdfDocument`**:

- **`PdfHighlightPersistence.applyHighlightAndSave`** (on **IO**):
  - Builds **`MutableEditsDraft`**, groups **`selection.bounds`** by **`pageNum`**, and **`insert`s** one **`HighlightAnnotation`** per page with a list of **`RectF`** for that page.
  - Calls **`document.applyEdits(draft.toEditsDraft())`**.
  - Opens **`openFileDescriptor(uri, "rw")`**, then **`createWriteHandle().use { it.writeTo(pfd) }`** to flush the updated PDF to the **`Uri`**.

If the document is not editable, or **`openFileDescriptor`** fails, a **Snackbar** explains that highlights are still saved **in the app** but not necessarily **inside the PDF file**.

The picker uses **`OpenPdfDocumentContract`** (read + write + persistable flags where the system allows), and **`PersistedUriHelper.takePersistableReadWritePermission`** is used when opening files so long-term write is more likely.

## Retrieving highlights when reopening

In **`ReaderPdfViewerFragment.onLoadDocumentSuccess`**:

- A coroutine on **`viewLifecycleOwner.lifecycleScope`** loads **`getHighlights(documentId)`** on **IO** (wrapped in **`runCatching`** so corrupt DataStore data does not crash the reader).
- On success, it **replaces** the in-memory session list, then **`pdfViewRef?.setHighlights(...)`** so previous sessions’ marks reappear.

**Important:** Loading must **not** use **`runBlocking`** on the main thread with DataStore; that previously caused **deadlocks / instant crashes** with no obvious stack trace in Logcat.

## Relationship to the in-process PDF save coordinator

The module also has **`PdfSaveCoordinator`** used by **`ReaderViewModel`** for **reading-position / recent-files** persistence. Highlight **file** writes use **`PdfHighlightPersistence`** and **`EditablePdfDocument`** APIs instead; the coordinator is **not** wired into the highlight path today.

## Caveats and interactions

- **In-document search:** **`PdfViewerFragment`** / search UI may call **`setHighlights`** for temporary match marks, which can **replace** the overlay list managed for user highlights until merging is implemented.
- **PDF write success** does not remove DataStore entries; **display on reopen** is driven from **DataStore** for consistency when file embedding is unavailable or invisible in the viewer.

## Highlight flow diagram

```mermaid
flowchart TD
    A[User selects text in PdfView] --> B[Selection menu built + preparer runs]
    B --> C[Copy / Select All / Highlight]
    C --> D[User taps Highlight]
    D --> E[Append Highlight overlays + setHighlights on main thread]
    E --> F[close menu + clearCurrentSelection]
    F --> G[IO: append DataStore by documentId]
    G --> H{EditablePdfDocument?}
    H -->|No| I[Snackbar: in-app save only]
    H -->|Yes| J[applyEdits HighlightAnnotation per page]
    J --> K[openFileDescriptor rw + writeTo]
    K -->|failure| L[Snackbar: file not updated]
    M[Document loads later] --> N[IO: getHighlights from DataStore]
    N --> O[setHighlights restored list]
```

---

# Bookmarks (implemented)

Task: [15-pdf-bookmark.md](../androidPdfReader/task/15-pdf-bookmark.md)

Key types/files: `PdfBookmark`, `UserPdfBookmarkRepository` / `UserPrefsUserPdfBookmarkRepository`, `ReaderPdfViewerFragment` (flag overlay + gestures), `AndroidxPdfReaderActivity` (**Go to bookmark** menu), drawable `ic_bookmark_flag.xml`.

## Behavior

| Action | Result |
|--------|--------|
| **Double-tap** on page | Places/replaces the **only** bookmark for this PDF at **page + (x, y)** (PDF coords). Does **not** zoom. |
| **Long-press** yellow flag | Removes bookmark immediately. |
| Overflow **Go to bookmark** | `scrollToPosition` / `scrollToPage`; toast if none. |
| **Single tap** | Still toggles full-screen (toolbar on/off). |

Flag: **16×16** yellow vector overlay (`ImageView`), repositioned on viewport changes via **`pdfToViewPoint`**. Not stored as a PDF annotation and not using **`setHighlights`**.

## Persistence

- DataStore blob key: **`user_pdf_bookmarks_by_document_v1`**.
- Shape: map **`documentId` → `{ "page", "x", "y" }`** (overwrite on place; delete on clear).
- Same **`documentId`** as highlights / reading position (`uri.toString()` today).
- Restored on **`onLoadDocumentSuccess`** / **`onResume`** (IO coroutine; no main-thread **`runBlocking`**).

## Gesture wiring note

`PdfView.setOnTouchListener` **replaces** `PdfViewerFragment`’s listener that calls immersive mode on **`onSingleTapConfirmed`**. The app’s listener therefore handles both:

1. **`onSingleTapConfirmed`** → `ReaderViewModel.toggleFullScreen()`
2. **`onDoubleTap`** → place bookmark and temporarily consume the second-tap stream so PdfView does not zoom

Pinch, scroll, and text selection still reach PdfView when not suppressing a double-tap.

## Bookmark flow diagram

```mermaid
flowchart TD
    A[Double-tap on PdfView] --> B[viewToPdfPoint]
    B --> C[Overwrite PdfBookmark in memory]
    C --> D[Show/move yellow flag ImageView]
    D --> E[IO: setBookmark DataStore]
    F[Long-press flag] --> G[Hide flag + clearBookmark]
    H[Go to bookmark menu] --> I{Bookmark exists?}
    I -->|No| J[Toast]
    I -->|Yes| K[scrollToPosition / scrollToPage]
    L[Document loads] --> M[IO: getBookmark]
    M --> N[Show flag if present]
```

---

# Other implemented reader features (pointers)

These are covered by tasks under `androidPdfReader/task/` and are already in the codebase:

| Feature | Task | Primary hooks |
|---------|------|----------------|
| Open PDF / recents / resume page | 01–03, 08 | `AndroidxPdfEngine`, `RecentFilesRepository`, reading position |
| Highlights | 05–07 | See above |
| Full-screen single-tap | 12 | `ReaderViewModel.isFullScreen`, `onRequestImmersiveMode` / custom touch |
| Text search | 13 | Search bottom sheet, `searchDocument` / `getPageContent` |
| Reading time | 11 | `readingTimeSeconds` on recents |
| Read aloud (TTS, FGS, speed) | 14 | `readaloud/ReadAloudService`, start/speed dialogs |
| Bookmark flag | **15** | See **Bookmarks** section above |
