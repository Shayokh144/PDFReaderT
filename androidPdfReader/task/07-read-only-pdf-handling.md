# Task 07: Read-Only PDF Handling

## Goal
Detect documents that do not allow annotations and prevent highlight writes for them.

## What to build
- Detect whether the opened PDF supports writing comments or annotations.
- Disable or block highlight creation when the document is read-only.
- Show a clear message that the file is read-only and highlights cannot be saved.

## Implementation notes
- Use the permission or capability APIs provided by the chosen PDF engine.
- Decide whether the UI should hide the `Highlight` action entirely or show it and explain why it is unavailable.
- Re-check capability when opening each document, not as a global app setting.
- Keep copy and read-only viewing available even when highlight writing is disabled.

## Acceptance criteria
- Read-only PDFs are detected correctly.
- Users cannot create unsavable highlight annotations on read-only files.
- The app explains why highlighting is unavailable.
- Normal readable PDFs still allow highlight creation.
