# Task 03: Resume Reading Position

## Goal
Remember the user's last read page for each PDF and reopen the document at that page.

## What to build
- Track the currently visible page while the user reads.
- Persist the current page for the active PDF:
- on a repeating interval of about 5 seconds
- when the app goes to background
- when the reader is closed
- when the reader screen is removed
- Restore the saved page when the user reopens the same document.

## Implementation notes
- Store reading position using the same document identity used by recent files.
- Avoid writing too frequently if the page has not changed.
- Hook into Activity, Process, or navigation lifecycle events for background and close handling.
- Make sure the saved page is clamped to a valid page range if document page count changes.
- Keep persistence async where possible, but guarantee the latest page is not lost during normal app transitions.

## Acceptance criteria
- Reading position is updated as the user changes pages.
- Reopening the same PDF resumes from the last saved page.
- Backgrounding the app preserves the latest reading position.
- Closing the reader and reopening later resumes correctly.
- No crashes occur if the saved page is out of range.
