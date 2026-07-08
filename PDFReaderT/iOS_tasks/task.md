# Reading Analytics — Task Overview

This feature has been split into two incremental tasks:

## Task 1: Reading Stats (no new data needed)
**File:** [task-1-reading-stats.md](task-1-reading-stats.md)

Uses existing `RecentFile` data (`readingTimeSeconds`, `lastPageNumber`, `totalPages`) to show a stats card on the home screen and per-book progress indicators. Ships immediately with zero data-layer changes.

## Task 2: Reading Insights / Trends (requires new tracking)
**File:** [task-2-reading-insights.md](task-2-reading-insights.md)

Adds per-session logging, daily aggregates, idle detection, and a full insights screen with weekly comparisons, bar charts, streaks, and top-book tracking. Builds on top of Task 1.
