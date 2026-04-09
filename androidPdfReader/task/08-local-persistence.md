# Task 08: Local Persistence

## Goal
Persist recent-file data and file access details needed to reopen user-selected PDFs.

## What to build
- Create a local persistence layer for recent-file metadata.
- Persist the file access reference needed to reopen external PDFs later.
- Store at least these fields per recent item:
- unique id
- file name
- persistent URI or token
- date added
- file size label
- last page number
- total pages

## Implementation notes
- Prefer `DataStore` for a lightweight implementation, or `Room` if you want stronger query and migration support.
- Persist Android URI permissions with `takePersistableUriPermission` when supported.
- Keep the storage model separate from UI models.
- Add mapping logic for converting persisted data into recent-list display models.
- Handle corrupted or stale records defensively.

## Acceptance criteria
- Recent-file records survive app restart.
- Persisted file access lets the app reopen previously chosen PDFs.
- Stored metadata is enough to render the recent-files list.
- Invalid persisted entries can be detected and cleaned up safely.
