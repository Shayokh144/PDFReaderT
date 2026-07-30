# Task 15: PDF Bookmark (double-tap flag)

## Goal
Let the user place a single in-document bookmark by double-tapping the PDF, see a yellow flag at that point, remove it with a long-press, and jump back to it from the reader overflow menu. Pinch-zoom still works; double-tap must **not** zoom.

## What to build
- **Double-tap** on the page places (or replaces) one bookmark at that **page + (x, y)** PDF coordinate.
- Show a **yellow 16×16 flag** icon at the tap point; reposition it on scroll/zoom while the page is visible.
- **Long-press** the flag removes the bookmark immediately (no confirm dialog).
- Persist the bookmark in app storage by `documentId` (same id as highlights / reading position) so it survives reopen.
- Overflow menu item **Go to bookmark** (near Reading speed) scrolls to the bookmarked page/position; if none exists, show a short toast.
- **Single tap** continues to toggle full-screen (toolbar hidden/shown); do not break immersive mode when wiring double-tap.

## Implementation notes

### Gestures
- `androidx.pdf.view.PdfView` has no public API to disable double-tap zoom. Setting `PdfView.setOnTouchListener` **replaces** `PdfViewerFragment`’s listener that drives immersive mode — combine both in one listener:
  - `onSingleTapConfirmed` → toggle full-screen via `ReaderViewModel`
  - `onDoubleTap` → place bookmark; consume the second-tap stream so PdfView does not zoom
- Pinch / scroll / text selection must still reach PdfView when not suppressing a double-tap.

### Coordinates and overlay
- Place: `pdfView.viewToPdfPoint(x, y)` → `PdfBookmark(documentId, pageIndex, x, y)`.
- Draw: overlay `ImageView` (sibling of `PdfView` in its parent), not `setHighlights` (highlights are rect fills).
- Update position on viewport changes with `pdfView.pdfToViewPoint(PdfPoint(...))` (offset by `pdfView.left` / `top` if needed).
- Hide the flag when the point is off-screen / null.
- Go to bookmark: prefer `scrollToPosition(PdfPoint)`; fall back to `scrollToPage`.

### Persistence
- Mirror highlights DataStore pattern: map `documentId → { page, x, y }` (at most one entry per document).
- Suggested key: `user_pdf_bookmarks_by_document_v1`.
- Register repository on `AppContainer`; load on document success / resume (never `runBlocking` on main for DataStore).

### Localization
- `pdf_reader_go_to_bookmark` — “Go to bookmark”
- `pdf_reader_bookmark_missing` — “No bookmark yet. Double-tap the page to add one.”
- `pdf_reader_bookmark_flag` — content description for the flag

### Interaction with other features
- Full-screen (task 12): single-tap toggle must keep working after the custom touch listener.
- Read Aloud scroll-lock overlay (task 14) may block flag long-press while Playing — acceptable; unlock on Pause.
- Search / highlights are independent; bookmark is not written into the PDF file.

## Acceptance criteria
- Double-tap places a yellow 16×16 flag at the tap location and does not zoom.
- A second double-tap moves/replaces the only bookmark for that PDF.
- Long-press on the flag removes it immediately.
- Bookmark survives app restart and reopen of the same document.
- **Go to bookmark** navigates to the saved page/position; toast if missing.
- Single tap still toggles full-screen; toolbar reappears when exiting full-screen.
- Pinch-zoom and scrolling still work.

## Depends on
- Task 01 (open PDF) / existing `AndroidxPdfReaderActivity` + `ReaderPdfViewerFragment`
- Task 08 / DataStore patterns (same as highlights)
- Task 12 (full-screen single-tap behavior must remain intact)

## Out of scope
- Multiple bookmarks per PDF / bookmark list UI
- Writing bookmarks as PDF annotations into the file
- Syncing bookmarks with iOS
