# Task 10: Basic Reliability and Observability

## Goal
Add structured logging so key Android app flows are easier to debug and monitor during development.

## What to build
- Add structured logging for these domains:
- UI
- view-model or business logic
- storage
- file access and persisted URI handling
- Log important lifecycle and failure events without exposing sensitive document contents.

## Implementation notes
- Use a consistent logging wrapper instead of scattered raw log calls.
- Include event names and lightweight metadata that helps diagnose failures.
- Log picker results, file reopen failures, invalid URI records, save attempts, save failures, and annotation-permission checks.
- Keep debug logs useful in development and easy to reduce or disable for release builds.

## Acceptance criteria
- Core flows emit useful logs with consistent structure.
- File open, reopen, save, and persistence failures are observable in logs.
- Logs avoid dumping full PDF contents or private user text selections.
- Logging approach is centralized enough to scale as features grow.
