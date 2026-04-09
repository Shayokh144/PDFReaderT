# Task 01: Open PDF From Device Storage

## Goal
Let the user choose exactly one PDF from device storage and open it in the Android reader screen.

## What to build
- Add a home or empty-state screen with a clear `Select PDF` call-to-action.
- Launch the Android system picker with `ACTION_OPEN_DOCUMENT`.
- Restrict selection to `application/pdf`.
- Allow only a single file selection.
- Open the selected file in the app's embedded PDF reader flow.

## Implementation notes
- Use the Storage Access Framework, not direct file paths.
- Persist URI permission after selection so the file can be reopened later.
- Handle the case where the user cancels the picker without crashing or clearing the current UI state.
- If no document has been opened yet, keep the empty state visible.
- Validate the returned URI before navigating to the reader screen.

## Acceptance criteria
- Tapping `Select PDF` opens the system file picker.
- Only PDF documents can be selected.
- Choosing a PDF opens the reader screen successfully.
- Canceling the picker keeps the app stable and returns to the previous screen.
- First launch with no document shows a clear empty state.
