# Task 11: Reading Time Tracking

## Goal
Track cumulative time the user spends reading each PDF while it is open in the Android reader, persist it with recent-file metadata, and show it in the recent-files list—matching the iOS behavior from commit `fbe150b7a88fe98f824f86b33079d371067ad71e`.

## What to build

### Data model and persistence
- Add `readingTimeSeconds` (cumulative, in seconds) to `RecentPdfRecord`.
- Persist the field in `UserPrefsRecentFilesRepository` JSON encode/decode.
- Default missing values to `0` when loading older stored records (backward compatible migration).
- Preserve existing `readingTimeSeconds` when upserting the same document (do not reset on reopen).

### Session tracking (reader)
- Count time only while the PDF reader is **in the foreground** (user is actively in `AndroidxPdfReaderActivity` and lifecycle is at least `RESUMED`).
- Do **not** accumulate time while the app is backgrounded or the reader activity is not resumed.
- Implement session bookkeeping similar to iOS:
  - store session start timestamp and document id for the active session
  - on commit, add elapsed seconds to the matching recent record and persist
- Commit reading time when:
  - the reader activity pauses (`onPause`)
  - the reader activity is destroyed (`onDestroy`)
  - the user closes the reader (same close path as today)
  - before opening a different document (if applicable)
- Restart a new session when the reader returns to `RESUMED` after a commit (e.g. user comes back from home/recents).

Suggested touchpoints:
- `ReaderViewModel` — commit/increment API and repository call
- `RecentFilesRepository` / `UserPrefsRecentFilesRepository` — `updateReadingTime(documentId, deltaSeconds)` or extend existing update helpers
- `AndroidxPdfReaderActivity` — lifecycle hooks alongside existing `persistReadingState` calls

### Recent-files UI
- Show reading time on each recent item in `RecentFileCard` (`HomeScreen.kt`), in the metadata row with file size and page summary.
- Format for display (match iOS):
  - if total reading time is **≤ 60 minutes**, show rounded **minutes** (e.g. `42 min`, `0 min`)
  - if total reading time is **> 60 minutes**, show **hours** — whole hours when exact (e.g. `2 h`), otherwise one decimal (e.g. `1.5 h`)
- Add localized string resources for minute/hour formats in `strings.xml` (see task 09 for naming conventions).

## Implementation notes

- Mirror iOS semantics: `readingTimeSeconds` is **cumulative per document**, not per session.
- Use monotonic elapsed time where possible (`SystemClock.elapsedRealtime()` for session deltas) to avoid wall-clock skew; store cumulative totals as seconds (`Long` or `Double`, consistent with JSON encoding).
- Keep session state in the reader layer (`ReaderViewModel` or activity-scoped holder), not in Compose home state.
- Avoid double-counting: clear session start/id after each commit; guard against duplicate commits on `onPause` + `onDestroy`.
- Hook into the same lifecycle patterns already used for page persistence in `AndroidxPdfReaderActivity` (`onPause`, `onDestroy`, `repeatOnLifecycle(Lifecycle.State.RESUMED)`).
- Home list relative “last opened” time already uses minute granularity via `DateUtils.getRelativeTimeSpanString`; no second-level ticker is required for reading time.
- Log debug events when reading time is committed (optional; aligns with task 10).

## iOS reference (commit `fbe150b7`)

| iOS | Android equivalent |
|-----|-------------------|
| `RecentFile.readingTimeSeconds` | `RecentPdfRecord.readingTimeSeconds` |
| `beginReadingSession()` / `commitReadingTimeIfNeeded()` | Session start/commit in reader activity / `ReaderViewModel` |
| PDF `onAppear` + scene `.active` | `Lifecycle.State.RESUMED` |
| Scene `.background` / close / URL change | `onPause`, `onDestroy`, document switch |
| `RecentFileRow.formattedReadingTime` | `RecentFileCard` formatter + `strings.xml` |
| Preserve time when re-adding same file name | Preserve on `upsert` for same `documentId` |

## Acceptance criteria

- Opening and reading a PDF increases that document’s stored `readingTimeSeconds`.
- Backgrounding the app or leaving the reader stops the timer; returning to the reader resumes counting in a new session segment.
- Cumulative time survives app restart and appears on the matching recent-files row.
- Recent list shows formatted reading time using the minutes / hours rules above.
- Older persisted recent records without `readingTimeSeconds` load with `0` and still decode successfully.
- Reopening the same PDF from recents does not reset previously accumulated reading time.
- No duplicate accumulation from normal pause/destroy lifecycle transitions.

## Depends on

- Task 02 (recent files list UI)
- Task 08 (recent-file persistence)
- Reader activity lifecycle from existing open/resume flow (tasks 01 / 03)

## Out of scope

- Cross-platform sync of reading time between iOS and Android
- Per-session analytics or server upload
- Showing reading time inside the reader screen overlay
