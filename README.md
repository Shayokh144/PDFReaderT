# PDFReaderT

PDFReaderT is a focused PDF reading app with recent-file memory, page resume, and in-document highlighting.

## Core Feature List (Platform-Agnostic)

Use this list as the baseline scope for building an Android version with equivalent behavior.

### 1) Open PDF From Device Storage
- User can pick exactly one `.pdf` file from the system file picker.
- The app opens the selected file in an embedded PDF reader screen.
- If no file is selected yet, show an empty state with a clear "Select PDF" CTA.

### 2) Recent Files List
- Show a list of recently opened PDFs on the home/empty state.
- Each recent item stores and displays:
  - file name
  - file size
  - time since added/opened (relative time style)
  - last read page + total pages (`Page X of Y`)
- Tapping a recent item reopens that PDF.
- User can delete items from recent files list.
- If a recent entry is no longer valid (file deleted/moved), remove it and show an alert.

### 3) Resume Reading Position
- Track current page while reading.
- Persist current page for the active file:
  - periodically (every ~5 seconds)
  - when app goes to background
  - when reader is closed
  - when reader view disappears
- Reopening a recent file starts at the last saved page.

### 4) PDF Reader Experience
- Continuous vertical scrolling page mode.
- Auto-scale pages to fit screen.
- Supports both portrait and landscape orientations.
- Show live page indicator overlay in reader (`current/total`).
- Reader has a "Close" action to return to home state.

### 5) Text Selection + Highlight Annotation
- User selects text in PDF and sees a consistent context menu: **Copy, Select All, Highlight**.
- System-default actions like "Look Up" are suppressed; PDFKit's competing internal edit menus are stripped so the app's menu always wins.
- Menu includes a custom "Highlight" action with a highlighter icon.
- Highlighting is applied line-by-line for multi-line selections.
- Highlights are saved directly into the PDF as annotation data.
- Copy selected text is supported.

### 6) Annotation Save Behavior
- Save is coalesced/debounced on a dedicated serial queue to avoid overlapping writes during rapid edits.
- The save pipeline is extracted into a standalone `PDFSaveCoordinator` that holds no back-reference to the view coordinator, so the coordinator can be deallocated freely while a long write finishes in the background.
- A `UIBackgroundTask` is registered before each save is dispatched, ensuring the system keeps the app alive while the write is queued and executing.
- Highlight changes trigger save attempts.
- On close, the app flushes all pending saves on a background thread before removing the reader view. A saving-progress spinner is displayed while the flush runs, keeping the UI responsive.
- When the app enters the background, pending saves are flushed synchronously so highlights are guaranteed to be persisted before a force-quit is possible.
- Save also occurs as a non-blocking safety net on reader teardown.
- If save fails, show user-facing error alert.

### 7) Read-Only PDF Handling
- Detect when document does not allow commenting/annotations.
- Prevent highlight write in that state.
- Show a clear alert: file is read-only and highlights cannot be saved.

### 8) Local Persistence
- Persist recent-file metadata locally (lightweight key-value storage).
- Persist file access reference/token needed for reopening externally picked files.
- Store recent-file model fields:
  - unique id
  - file name
  - persistent file reference/token
  - date added
  - file size label
  - last page number
  - total pages

### 9) Localization-Ready Strings
- All visible text uses localization keys (not hardcoded UI copy).
- Current implementation includes English strings; architecture is localization-ready.

### 10) Basic Reliability/Observability
- Structured app logging for key domains:
  - UI
  - ViewModel / business logic
  - storage
  - file reference/bookmark handling

## Android Mapping Notes (Suggested Equivalents)

- File picker: `ACTION_OPEN_DOCUMENT` with `application/pdf`.
- Persistent file access: URI permission + persisted URI permissions.
- PDF rendering: `PdfRenderer`, Android PDF SDK, or third-party PDF engine with annotation support.
- Recent files storage: `DataStore` or Room (simple list can use DataStore JSON).
- Background/foreground lifecycle save hooks: Activity/Process lifecycle observers.
- Annotation capability check: map to document permissions from your chosen PDF engine.

## Out-of-Scope (Current iOS Implementation)

- Search inside PDF.
- Bookmarks/table of contents navigation.
- Drawing/ink annotations, text notes, or shape annotations.
- Cloud sync or account-based history sync.