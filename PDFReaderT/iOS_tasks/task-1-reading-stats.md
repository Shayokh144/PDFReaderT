# Task: Reading Stats (using existing data)

## Goal
Give users a snapshot of their reading activity using data the app already collects — no new tracking required. This ships value immediately while the full insights feature (Task 2) is built separately.

## Available data (per `RecentFile`)
- `readingTimeSeconds` — cumulative foreground reading time
- `lastPageNumber` — last viewed page (0-based index)
- `totalPages` — total page count
- `name` — file name
- `dateAdded` — when the file was added to recents
- `fileSize` — human-readable file size

## What to show

### Stats card on the home screen
A compact card placed between the hero section and the "Recent Files" list. Shows a quick summary at a glance:

- **Total reading time** — sum of `readingTimeSeconds` across all books, formatted as hours/minutes (e.g. "12h 34m total reading time")
- **Books opened** — count of recent files
- **Pages read** — sum of all `lastPageNumber + 1` values (best approximation with current data)
- **Average time per book** — total time / number of books

The card only appears once there is at least 1 recent file with reading time > 0.

### Per-book progress in the Recent Files list
Enhance each `RecentFileRow` to show:

- **Progress bar** — `lastPageNumber / totalPages` as a visual indicator (e.g. a thin bar under the file name)
- **Percentage label** — e.g. "45% complete"
- **Completion badge** — if progress is ≥ 95%, show a "Finished" or checkmark indicator

### Full Stats screen (optional, tapping the card)
A dedicated screen with more detail:

- **Library overview** — total books, total reading time, total pages read
- **Top book** — the book with the highest `readingTimeSeconds`
- **Book list sorted by reading time** — each showing time spent and progress percentage
- **Completion summary** — X of Y books finished (≥ 95%)

## Implementation notes
- No new data models or storage needed — everything reads from the existing `[RecentFile]` array.
- Stats computation can live in the ViewModel or a small helper/extension — keep it simple.
- The stats card should feel lightweight — not a heavy dashboard. Think of it as a glanceable summary row.
- Progress percentage: `min(100, Int((Double(lastPageNumber + 1) / Double(totalPages)) * 100))`. Guard against `totalPages == 0`.
- Use SF Symbols for icons (e.g. `book.fill`, `clock.fill`, `chart.bar.fill`).
- The full stats screen is a nice-to-have for this task. The card + per-book progress are the core deliverables.

## Acceptance criteria
- Stats card appears on home screen when at least 1 file has been read.
- Card shows total reading time, books opened, and pages read.
- Each recent file row shows a progress bar and percentage.
- Books at ≥ 95% progress show a completion indicator.
- Tapping the stats card opens a full stats screen with per-book breakdown.
- Stats update live as the user reads (no app restart needed).
- Card is hidden when there are no recent files.
