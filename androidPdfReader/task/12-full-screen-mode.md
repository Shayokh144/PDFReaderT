# Task 12: Full-Screen Mode

## Goal
Let the user immerse in the PDF by hiding all chrome (toolbar, status bar, and page counter) with a single tap, and restoring it with another tap. Matches the iOS full-screen behavior from commit `c52c576`.

## What to build
- Add a single-tap gesture on the PDF viewer that toggles full-screen mode.
- When full-screen is active, hide the top app bar (toolbar with search and close buttons), the system status bar, and the page counter overlay.
- When the user taps again, restore all chrome.
- Animate the transitions smoothly (fade/slide).
- Ensure the PDF content does not jump or re-scale when toggling (layout stability).

## Implementation notes
- Add an `isFullScreen` state to the ViewModel (default `false`) with a `toggleFullScreen()` method.
- The single-tap detector must not conflict with double-tap-to-zoom or pinch-to-zoom gestures. Use `GestureDetector` with appropriate conflict resolution (e.g. require double-tap to fail before single-tap fires).
- For hiding the system status bar, use `WindowInsetsController` or immersive mode APIs (`BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SNAPPING` or similar).
- The PDF view should always fill the full screen area (draw behind the toolbar). The toolbar overlays on top. This prevents layout jumps when the toolbar hides/shows.
- Use `AnimatedVisibility` or alpha animation for the page counter fade.
- Reset `isFullScreen = false` when the PDF is closed so the next opened file starts in normal mode.

## Interaction with other features
- The search button lives in the toolbar, so it is naturally inaccessible during full-screen mode.
- If the search bottom sheet is open and the user taps to enter full screen, the sheet can remain as-is (it is presented independently).

## Acceptance criteria
- Single tap on the PDF toggles full-screen mode.
- In full-screen mode: toolbar, status bar, and page counter are hidden.
- Another single tap restores all UI chrome.
- Double-tap-to-zoom still works without accidentally toggling full screen.
- The PDF content does not jump, re-scale, or blink during the transition.
- Full-screen resets when the reader is closed.
- Transitions are animated (not abrupt).
