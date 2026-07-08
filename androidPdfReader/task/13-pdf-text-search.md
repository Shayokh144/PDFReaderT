# Task 13: PDF Text Search

## Goal
Let the user search for text within the currently opened PDF. Results are displayed in a scrollable bottom sheet, and tapping a result navigates to that location with a temporary yellow highlight. Matches the iOS search behavior from commit `c52c576`.

## What to build
- Add a search icon (magnifying glass) in the top toolbar, visible only when a PDF is open.
- Tapping the icon opens a bottom sheet (half-screen / full-screen draggable) with a search text field and results list.
- As the user types (debounced ~300ms), search the PDF and display matching results.
- Each result row shows the **page number** and a **text snippet** (~80 chars) with the matched portion bolded/highlighted.
- Tapping a result dismisses the bottom sheet, scrolls the PDF to the match, and adds a **temporary yellow highlight annotation** for 2 seconds.
- The temporary highlight annotation is removed after 2 seconds and is never persisted to disk.

## Implementation notes

### Search logic
- Use the PDF engine's text search API (e.g. `PdfDocument.findText()` or page-by-page `PdfPage.getText()` + string search).
- Run the search on a background coroutine/thread to keep the UI responsive on large PDFs.
- Debounce the search input by 300ms — cancel previous search when new input arrives.
- Store results as a list of data objects containing: `pageIndex`, `snippet`, `matchIndex`, and enough info to re-locate the match at navigation time.

### Snippet building
- For each match, extract surrounding context from the page text (~30 chars before and after).
- Replace newlines with spaces and trim whitespace.
- Add ellipsis (`…`) if the snippet is truncated at either end.

### Navigation and highlighting
- **Important**: The search may run against a separate document instance for thread safety. The resulting text positions/selections may not be directly usable with the displayed PDF view.
- At navigation time, re-locate the match in the displayed document (e.g. search again on the target page or use page index + character offset).
- Scroll the PDF view to the match location.
- Create a temporary highlight annotation (yellow, 50% opacity) covering the matched text bounds.
- Remove the annotation after 2 seconds using a coroutine delay or `Handler.postDelayed`.
- Track temporary annotations so rapid taps correctly remove the previous highlight before adding a new one.

### Bottom sheet UI
- Use `ModalBottomSheet` (Compose) or `BottomSheetDialogFragment` (View system).
- Include a `TextField` at the top with a clear button.
- Show a scrollable list of results below.
- Show an empty state ("No results found") when the query produces no matches.
- Bold/color the matched portion within each snippet (use `AnnotatedString` in Compose or `SpannableString` in Views).

### State management
- Add to the ViewModel:
  - `isSearching: Boolean` — controls bottom sheet visibility
  - `searchText: String` — bound to the text field
  - `searchResults: List<PdfSearchResult>` — populated by search
  - `searchNavigation: SearchNavigationRequest?` — triggers navigation in the PDF view
- Reset all search state when the PDF is closed.

### Localization
- Add string resources:
  - `pdf_reader_search_title` — "Search"
  - `pdf_reader_search_placeholder` — "Search in PDF"
  - `pdf_reader_search_no_results` — "No results found"
  - `pdf_reader_search_result_page` — "Page %d"

## Interaction with full-screen mode
- The search button is in the toolbar, which is hidden in full-screen mode — naturally inaccessible.
- User must exit full screen (single tap) before searching.

## Acceptance criteria
- A search icon appears in the toolbar when a PDF is open.
- Tapping it opens a bottom sheet with a search field.
- Typing a query shows matching results with page numbers and text snippets.
- The matched text within snippets is visually distinguished (bold/colored).
- Tapping a result closes the sheet and scrolls to the correct location in the PDF.
- A temporary yellow highlight appears on the matched text for ~2 seconds, then disappears.
- The highlight is never saved to the PDF file.
- Searching is responsive (no UI freezes on large PDFs).
- Empty state is shown when no results match.
- Search state resets when the PDF is closed.
