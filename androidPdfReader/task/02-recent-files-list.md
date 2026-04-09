# Task 02: Recent Files List

## Goal
Show a recent-files list on the home screen so the user can quickly reopen PDFs.

## What to build
- Display a list of recently opened PDFs on the home or empty-state screen.
- Each item must show:
- file name
- file size
- relative opened/added time
- last read page and total pages in `Page X of Y` format
- Let the user tap an item to reopen that PDF.
- Let the user delete an item from the list.

## Implementation notes
- Build the list from locally persisted recent-file records.
- Sort recent items by most recently opened or added.
- When reopening, verify the stored URI is still accessible.
- If a file has been moved, deleted, or permission is lost, remove the invalid item and show an alert or snackbar.
- Use efficient list rendering so the home screen remains responsive.

## Acceptance criteria
- Opening a PDF adds it to the recent-files list.
- Tapping a recent item reopens the correct file.
- Deleting an item removes it from both UI and local storage.
- Invalid recent entries are cleaned up and user feedback is shown.
- Each visible recent item displays all required metadata.
