# Task 05: Text Selection and Highlight Annotation

## Goal
Let the user select PDF text, copy it, or create highlight annotations from a controlled context menu.

## What to build
- Enable text selection inside the PDF reader.
- Show a consistent context menu with:
- `Copy`
- `Select All`
- `Highlight`
- Add a custom `Highlight` action with an appropriate icon if the chosen PDF engine allows it.
- Apply highlights line by line when the selection spans multiple lines.
- Save highlights into the PDF as real annotation data.

## Implementation notes
- Choose a PDF engine that supports both text extraction/selection and annotation writing.
- Suppress or replace default text actions that conflict with the app's menu, as much as Android and the PDF engine allow.
- Keep copy behavior working for selected text.
- Handle multi-line selections carefully so highlight rectangles align with the rendered text.
- Keep selection state predictable after highlighting.

## Acceptance criteria
- The user can select text inside the PDF.
- The app exposes `Copy`, `Select All`, and `Highlight` actions.
- Copy works correctly for selected text.
- Highlighting creates visible highlight annotations.
- Multi-line selections are highlighted across all selected lines.
