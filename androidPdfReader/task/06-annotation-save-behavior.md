# Task 06: Annotation Save Behavior

## Goal
Make PDF annotation saving reliable, non-overlapping, and safe across app lifecycle events.

## What to build
- Create a dedicated save coordinator responsible for writing PDF annotation changes.
- Debounce or coalesce rapid save requests so overlapping writes do not happen.
- Trigger save attempts whenever highlights change.
- Flush pending saves when the reader is closed.
- Flush pending saves when the app goes to background.
- Show a saving-progress indicator when close-time flushing takes noticeable time.
- Show a user-facing error if a save fails.

## Implementation notes
- Keep save logic separate from UI controller or screen classes.
- Use a single-threaded queue, mutex, or coroutine dispatcher to serialize writes.
- Do not block the main thread during normal save requests.
- For close and background flows, define when saves must be awaited versus fire-and-forget.
- If Android background execution limits affect long writes, use the appropriate lifecycle-aware mechanism to finish the save safely.
- Ensure the reader screen can be destroyed without losing the final save result.

## Acceptance criteria
- Rapid highlight edits do not start overlapping PDF writes.
- Highlight changes eventually persist to disk.
- Closing the reader waits for pending critical saves before fully exiting.
- Backgrounding the app preserves pending highlight changes.
- Save failures show clear feedback to the user.
