# NOT NEEDED FOR ANDROID NOW
# Task 04: PDF Reader Experience

## Goal
Provide a comfortable Android PDF reading experience equivalent to the iOS app baseline.

## What to build
- Show the PDF in continuous vertical scrolling mode.
- Auto-scale pages to fit the available screen width.
- Support both portrait and landscape orientations.
- Display a live page indicator overlay in `current/total` format.
- Add a clear `Close` action that returns the user to the home screen.

## Implementation notes
- Choose a PDF engine that supports vertical scroll and future annotation support.
- Keep page indicator updates in sync with the visible page.
- Make overlay UI readable on light and dark PDF backgrounds.
- Preserve reader state during rotation.
- Make close behavior consistent whether the user entered from picker flow or recent files.

## Acceptance criteria
- The document scrolls vertically across pages.
- Pages scale to fit the screen reasonably without manual zoom on first load.
- Rotation works without losing the current reading context.
- A live `current/total` page indicator is visible while reading.
- The reader can be closed and returns to the home screen cleanly.
