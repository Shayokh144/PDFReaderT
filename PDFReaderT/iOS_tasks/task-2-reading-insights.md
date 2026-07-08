# Task: Reading Insights / Trends (requires new data tracking)

## Goal
Show users their reading habits over time — how much they've read this week vs last week, daily breakdown, streaks, and which book they've spent the most time on. Builds on top of Task 1 by adding temporal tracking. Goal is to make reading time visible and build a habit loop, similar to fitness/screen-time trackers.

## Prerequisite
Task 1 (Reading Stats) should be completed first. This task extends the stats card and full stats screen with time-based insights.

## New data to track

### Reading session log
For every reading session, capture:
- `documentId` — ties back to the `RecentFile`
- `documentName` — file name for display without lookup
- `startTime`, `endTime` — session boundaries
- `startPage`, `endPage` — pages at session start and end
- `duration` — computed from `endTime - startTime` minus idle gaps

**Session lifecycle:**
- Session starts when a PDF is opened or the app returns to foreground with a PDF active.
- Session ends when the PDF is closed, a different PDF is opened, or the app enters background.
- If the user is idle for ≥ 60 seconds (no page changes, no taps), automatically pause the session. Resume on next interaction. This prevents inflated stats from leaving the app open.

### Daily stats aggregate
Roll up sessions into a per-day record:
- `date` — calendar day
- `minutesRead` — total reading minutes that day
- `pagesRead` — total pages read that day
- `documentsOpened` — unique documents opened that day

The UI reads from this aggregate, not raw session logs.

### Storage
- Store session logs and daily aggregates as JSON in UserDefaults (separate keys from recent files), or migrate to a lightweight local store (e.g. a JSON file in Application Support) if the data grows.
- Keep at least 90 days of daily aggregates. Session logs can be pruned more aggressively (e.g. keep 30 days).
- The `RecentFilesStoring` protocol pattern can be extended for the new stores.

## Core metrics (on the Insights screen)
- **This week vs last week** — total reading time with percentage change (e.g. "3h 12m this week, +18% vs last week")
- **Daily breakdown** — bar chart for the current week (Mon–Sun), each bar showing minutes read
- **Reading streak** — consecutive days with ≥ 1 minute of reading
- **Daily average** — average minutes per day for the current week
- **Top book this week** — the book with the most reading time in the current week

## Where it appears in the app

### A — Enhanced stats card on the home screen
Extends the Task 1 stats card with time-based info:
- This week's total reading time and trend vs last week (e.g. "+18%")
- Current streak count (e.g. "4-day streak")
- Tapping opens the full Insights screen.
- Card is collapsible/dismissible to a single line.

### B — Chart icon in the top bar
A chart icon next to the "PDF Reader" title. Always visible regardless of card state. Tapping opens the full Insights screen.

### Full Insights screen
- **This week vs last week** — side-by-side stat cards with totals and % change
- **Daily minutes bar chart** — Mon–Sun for the current week
- **Streak count** — with a flame or similar icon
- **Daily average** for the week
- **Top book this week** — name and time spent
- **Per-book breakdown** — list of books read this week with time and pages

## Open decisions (to finalize before build)
- Week boundary: Mon–Sun vs Sun–Sat
- Minimum daily threshold to count toward a streak (1 min vs 5 min)
- Whether to show insights immediately or wait until 2+ days of data exist
- Idle timeout: 60 seconds is the starting point, may need tuning

## Implementation notes
- Add a `ReadingSession` model (`Codable`).
- Add a `DailyReadingStats` model (`Codable`).
- Add a `ReadingSessionTracker` that hooks into the existing reading-time lifecycle (appear/disappear, foreground/background) but captures richer data.
- Add an idle timer — reset on `PDFViewPageChanged` notifications and touch events. Fire after 60s to pause the session.
- Aggregate sessions into daily stats on session end (or lazily when the insights screen is opened).
- The existing `readingTimeSeconds` on `RecentFile` should remain as-is for backward compatibility. The new session tracking runs in parallel.
- Bar chart can be built with SwiftUI shapes — no need for a charting library. iOS 16+ Swift Charts is also an option if the deployment target allows it.

## Acceptance criteria
- Reading sessions are logged with start/end time and pages.
- Sessions auto-pause after 60s of inactivity.
- Daily aggregates are computed and stored.
- Insights screen shows this week vs last week, daily bar chart, streak, and top book.
- Stats card on home screen shows weekly summary and streak.
- Chart icon in top bar opens the insights screen.
- Data persists across app launches.
- At least 90 days of daily stats are retained.
- Existing reading time tracking (`readingTimeSeconds`) continues to work unchanged.

## v2 / future ideas
- Monthly heatmap (GitHub-style contribution grid)
- Per-book pace estimate ("at this rate you'll finish in 6 days")
- Daily reading goal setting (e.g. 30 min/day) with progress indicator
