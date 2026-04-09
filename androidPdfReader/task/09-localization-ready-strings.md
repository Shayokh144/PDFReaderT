# Task 09: Localization-Ready Strings

## Goal
Make the Android app ready for localization by removing hardcoded user-facing text.

## What to build
- Move all visible UI strings into Android string resources.
- Use resource keys consistently across screens, dialogs, menus, and error messages.
- Provide an English default string set for the current implementation.

## Implementation notes
- Cover home screen, reader screen, empty state, context menu labels, alerts, buttons, and validation messages.
- Avoid hardcoded text in Compose code, XML, and helper classes.
- Use naming that scales well for future translations.
- Keep reusable text centralized to avoid duplicate string keys.

## Acceptance criteria
- No user-facing text is hardcoded in implementation code.
- All visible strings resolve from Android resources.
- The app can be translated later without structural refactoring.
