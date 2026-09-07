//
//  PDFReaderViewModelTests.swift
//  PDFReaderTTests
//

import Combine
import PDFKit
import XCTest
@testable import PDFReaderT

@MainActor
final class PDFReaderViewModelTests: XCTestCase {

    private var store: MockRecentFilesStore!
    private var insights: InMemoryInsightsStorage!
    private var sut: PDFReaderViewModel!
    private var tempPDFURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        store = MockRecentFilesStore()
        insights = InMemoryInsightsStorage()
        sut = PDFReaderViewModel(recentFilesStore: store, insightsStorage: insights)
        sut.toastDurationNanoseconds = 50_000_000
        sut.searchDebounceNanoseconds = 20_000_000
        tempPDFURL = try TestPDFFactory.makePDF()
    }

    override func tearDown() async throws {
        sut.stopPageSaveTimer()
        sut = nil
        store = nil
        insights = nil
        if let tempPDFURL {
            try? FileManager.default.removeItem(at: tempPDFURL.deletingLastPathComponent())
        }
        tempPDFURL = nil
        try await super.tearDown()
    }

    // MARK: - onAppear / loading

    func testOnAppear_noStoredData_leavesRecentFilesEmpty() {
        store.loadResult = .noStoredData
        sut.onAppear()
        XCTAssertTrue(sut.recentFiles.isEmpty)
        XCTAssertTrue(sut.dailyStats.isEmpty)
        XCTAssertTrue(sut.recentSessions.isEmpty)
    }

    func testOnAppear_loadsRecentFilesAndInsights() {
        let file = RecentFile(
            id: UUID(),
            name: "a.pdf",
            bookmarkData: Data([1, 2, 3]),
            dateAdded: Date(),
            fileSize: "1 KB",
            lastPageNumber: 2,
            totalPages: 10,
            readingTimeSeconds: 30
        )
        store.loadResult = .loaded([file])
        insights.sessions = [
            ReadingSession(
                id: UUID(),
                documentId: file.id,
                documentName: file.name,
                startTime: Date(),
                endTime: Date(),
                startPage: 1,
                endPage: 3,
                durationSeconds: 10
            )
        ]
        insights.dailyStats = [
            DailyReadingStats(dateString: DailyReadingStats.todayString(), minutesRead: 1, pagesRead: 2, documentIds: [file.id])
        ]

        sut.onAppear()

        XCTAssertEqual(sut.recentFiles.count, 1)
        XCTAssertEqual(sut.recentFiles.first?.name, "a.pdf")
        XCTAssertEqual(sut.recentSessions.count, 1)
        XCTAssertEqual(sut.dailyStats.count, 1)
    }

    func testOnAppear_decodeFailed_leavesRecentFilesEmpty() {
        store.loadResult = .decodeFailed(NSError(domain: "test", code: 9))
        sut.onAppear()
        XCTAssertTrue(sut.recentFiles.isEmpty)
    }

    // MARK: - Alerts / UI toggles

    func testPresentAndDismissOKOnlyAlert() {
        sut.presentOKOnlyAlert(title: "T", message: "M")
        XCTAssertEqual(sut.okOnlyAlert?.title, "T")
        XCTAssertEqual(sut.okOnlyAlert?.message, "M")

        sut.dismissOKOnlyAlert()
        XCTAssertNil(sut.okOnlyAlert)
    }

    func testPresentOKOnlyAlert_withLocalizationKeys() {
        sut.presentOKOnlyAlert(
            titleKey: "pdf_reader.deleted_recent_alert_title",
            messageKey: "pdf_reader.deleted_recent_alert_message"
        )
        XCTAssertNotNil(sut.okOnlyAlert)
        XCTAssertFalse(sut.okOnlyAlert?.title.isEmpty ?? true)
        XCTAssertFalse(sut.okOnlyAlert?.message.isEmpty ?? true)
    }

    func testToggleFullScreen() {
        XCTAssertFalse(sut.isFullScreen)
        sut.toggleFullScreen()
        XCTAssertTrue(sut.isFullScreen)
        sut.toggleFullScreen()
        XCTAssertFalse(sut.isFullScreen)
    }

    func testRequestGoToBookmark() {
        XCTAssertFalse(sut.goToBookmarkRequest)
        sut.requestGoToBookmark()
        XCTAssertTrue(sut.goToBookmarkRequest)
    }

    func testShowBookmarkMissingToast_setsAndClearsMessage() async {
        sut.showBookmarkMissingToast()
        XCTAssertNotNil(sut.toastMessage)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(sut.toastMessage)
    }

    func testShowBookmarkMissingToast_cancelledWhenReplaced() async {
        sut.toastDurationNanoseconds = 200_000_000
        sut.showBookmarkMissingToast()
        let first = sut.toastMessage
        XCTAssertNotNil(first)

        sut.toastDurationNanoseconds = 50_000_000
        sut.showBookmarkMissingToast()
        XCTAssertNotNil(sut.toastMessage)

        try? await Task.sleep(nanoseconds: 100_000_000)
        // Second toast should have cleared; first cancel path was exercised.
        XCTAssertNil(sut.toastMessage)
    }

    func testUIModel_reflectsPublishedState() {
        sut.currentPage = 3
        sut.totalPages = 10
        sut.showingDocumentPicker = true
        sut.isSearching = true
        let model = sut.uiModel
        XCTAssertEqual(model.currentPage, 3)
        XCTAssertEqual(model.totalPages, 10)
        XCTAssertTrue(model.showingDocumentPicker)
        XCTAssertTrue(model.isSearching)
    }

    // MARK: - Recent files CRUD

    func testSaveRecentFile_addsFileAndPreservesReadingTimeOnReSave() throws {
        sut.saveRecentFile(tempPDFURL)
        XCTAssertEqual(sut.recentFiles.count, 1)
        XCTAssertEqual(sut.recentFiles.first?.name, tempPDFURL.lastPathComponent)
        XCTAssertNotNil(sut.currentFileId)
        XCTAssertGreaterThan(sut.totalPages, 0)
        XCTAssertFalse(store.savedFiles.isEmpty)

        sut.recentFiles[0].readingTimeSeconds = 42
        sut.saveRecentFile(tempPDFURL)
        XCTAssertEqual(sut.recentFiles.count, 1)
        XCTAssertEqual(sut.recentFiles.first?.readingTimeSeconds, 42)
    }

    func testSaveRecentFile_missingFile_doesNothing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).pdf")
        sut.saveRecentFile(missing)
        XCTAssertTrue(sut.recentFiles.isEmpty)
        XCTAssertNil(sut.currentFileId)
    }

    func testDeleteFile_removesAndPersists() throws {
        sut.saveRecentFile(tempPDFURL)
        XCTAssertEqual(sut.recentFiles.count, 1)
        sut.deleteFile(at: IndexSet(integer: 0))
        XCTAssertTrue(sut.recentFiles.isEmpty)
        XCTAssertEqual(store.savedFiles.last?.count, 0)
    }

    func testOpenRecentFile_success_setsInitialPageAndURL() throws {
        let file = try TestPDFFactory.makeRecentFile(from: tempPDFURL, lastPage: 1)
        sut.recentFiles = [file]
        sut.openRecentFile(file)
        XCTAssertEqual(sut.currentFileId, file.id)
        XCTAssertEqual(sut.initialPage, 1)
        XCTAssertEqual(sut.selectedPDFURL, URL.resolveBookmark(file.bookmarkData))
    }

    func testOpenRecentFile_updatesLastOpenedAtWithoutChangingDateAdded() throws {
        let added = Date(timeIntervalSinceNow: -3600)
        let older = try TestPDFFactory.makeRecentFile(from: tempPDFURL, lastPage: 1)
        let file = RecentFile(
            id: older.id,
            name: older.name,
            bookmarkData: older.bookmarkData,
            dateAdded: added,
            lastOpenedAt: added,
            fileSize: older.fileSize,
            lastPageNumber: older.lastPageNumber,
            totalPages: older.totalPages
        )
        let other = RecentFile(
            id: UUID(),
            name: "other.pdf",
            bookmarkData: Data([1]),
            dateAdded: Date(),
            fileSize: "1 KB",
            lastPageNumber: 0,
            totalPages: 1
        )
        sut.recentFiles = [other, file]
        let beforeOpen = Date()
        sut.openRecentFile(file)

        XCTAssertEqual(sut.recentFiles.first?.id, file.id)
        XCTAssertEqual(sut.recentFiles.first?.dateAdded, added)
        XCTAssertGreaterThanOrEqual(sut.recentFiles.first?.lastOpenedAt ?? .distantPast, beforeOpen)
        XCTAssertFalse(store.savedFiles.isEmpty)
    }

    func testOpenRecentFile_invalidBookmark_removesFileAndShowsAlert() {
        let file = RecentFile(
            id: UUID(),
            name: "gone.pdf",
            bookmarkData: Data([0xFF, 0x00, 0xAB]),
            dateAdded: Date(),
            fileSize: "1 KB",
            lastPageNumber: 0,
            totalPages: 1
        )
        sut.recentFiles = [file]
        sut.openRecentFile(file)
        XCTAssertTrue(sut.recentFiles.isEmpty)
        XCTAssertNotNil(sut.okOnlyAlert)
        XCTAssertNil(sut.selectedPDFURL)
    }

    // MARK: - Page save timer

    func testSaveCurrentPage_updatesMatchingFile() throws {
        sut.saveRecentFile(tempPDFURL)
        sut.currentPage = 1
        sut.saveCurrentPage()
        XCTAssertEqual(sut.recentFiles.first?.lastPageNumber, 1)
    }

    func testSaveCurrentPage_noMatchingFile_isNoOp() {
        sut.currentFileId = UUID()
        sut.currentPage = 5
        sut.saveCurrentPage()
        XCTAssertTrue(sut.recentFiles.isEmpty)
    }

    func testStartAndStopPageSaveTimer() {
        sut.startPageSaveTimer()
        sut.stopPageSaveTimer()
        // Stopping twice is safe.
        sut.stopPageSaveTimer()
    }

    func testPageSaveTimer_eventuallyPersistsPage() throws {
        sut.saveRecentFile(tempPDFURL)
        sut.currentPage = 1
        sut.pageSaveInterval = 0.05
        sut.startPageSaveTimer()

        let expectation = expectation(description: "timer saved page")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        sut.stopPageSaveTimer()
        XCTAssertEqual(sut.recentFiles.first?.lastPageNumber, 1)
    }

    // MARK: - Reading session / time

    func testBeginReadingSession_startsTrackingWithInitialPage() throws {
        sut.saveRecentFile(tempPDFURL)
        sut.initialPage = 1
        sut.currentPage = 0
        sut.beginReadingSession()
        // Second call while active readingSessionStart is set should no-op.
        sut.beginReadingSession()
        sut.onReaderInteraction()
        sut.currentPage = 1
    }

    func testBeginReadingSession_withoutCurrentFile_isNoOp() {
        sut.beginReadingSession()
        XCTAssertNil(sut.uiModel.selectedPDFURL)
    }

    func testCommitReadingTime_accumulatesSeconds() async throws {
        sut.saveRecentFile(tempPDFURL)
        sut.beginReadingSession()
        try await Task.sleep(nanoseconds: 50_000_000)
        sut.onDidEnterBackground()
        XCTAssertGreaterThan(sut.recentFiles.first?.readingTimeSeconds ?? 0, 0)
    }

    func testCommitReadingTime_withoutActiveSession_isNoOp() {
        sut.commitReadingTimeIfNeeded()
        XCTAssertTrue(store.savedFiles.isEmpty)
    }

    func testBeginReadingSession_resumesAfterBackgroundPause() async throws {
        sut.saveRecentFile(tempPDFURL)
        sut.beginReadingSession()
        try await Task.sleep(nanoseconds: 30_000_000)
        sut.commitReadingTimeIfNeeded()
        // Tracker still has active session; next begin resumes.
        sut.beginReadingSession()
        sut.onReaderInteraction()
    }

    func testOnSelectedPDFURLChanged_newDocument_registersRecentFile() {
        XCTAssertNil(sut.currentFileId)
        sut.onSelectedPDFURLChanged(tempPDFURL)
        XCTAssertEqual(sut.recentFiles.count, 1)
        XCTAssertNotNil(sut.currentFileId)
        XCTAssertEqual(sut.currentPage, 0)
        XCTAssertNil(sut.initialPage)
    }

    func testOnSelectedPDFURLChanged_whenOpeningRecent_skipsReRegister() throws {
        let file = try TestPDFFactory.makeRecentFile(from: tempPDFURL, lastPage: 1)
        sut.recentFiles = [file]
        sut.currentFileId = file.id
        sut.initialPage = 1
        sut.onSelectedPDFURLChanged(tempPDFURL)
        XCTAssertEqual(sut.recentFiles.count, 1)
        XCTAssertEqual(sut.currentFileId, file.id)
        XCTAssertEqual(sut.initialPage, 1)
    }

    func testOnSelectedPDFURLChanged_nil_endsSessionAndCommits() async throws {
        sut.saveRecentFile(tempPDFURL)
        sut.selectedPDFURL = tempPDFURL
        sut.beginReadingSession()
        try await Task.sleep(nanoseconds: 30_000_000)
        sut.onSelectedPDFURLChanged(nil)
        XCTAssertGreaterThan(sut.recentFiles.first?.readingTimeSeconds ?? 0, 0)
    }

    func testOnDidEnterBackground_flushesSaveFlusher() {
        var syncCalled = false
        sut.saveFlusher = SaveFlusher(
            asyncHandler: { $0() },
            syncHandler: { syncCalled = true }
        )
        sut.onDidEnterBackground()
        XCTAssertTrue(syncCalled)
    }

    // MARK: - Close

    func testClosePDFReader_withoutFlusher_clearsState() throws {
        sut.saveRecentFile(tempPDFURL)
        sut.selectedPDFURL = tempPDFURL
        sut.isFullScreen = true
        sut.isSearching = true
        sut.searchText = "x"
        sut.goToBookmarkRequest = true
        sut.beginReadingSession()

        sut.closePDFReader()

        XCTAssertNil(sut.selectedPDFURL)
        XCTAssertNil(sut.currentFileId)
        XCTAssertNil(sut.initialPage)
        XCTAssertNil(sut.saveFlusher)
        XCTAssertFalse(sut.isFullScreen)
        XCTAssertFalse(sut.isSearching)
        XCTAssertEqual(sut.searchText, "")
        XCTAssertTrue(sut.searchResults.isEmpty)
        XCTAssertNil(sut.searchNavigation)
        XCTAssertFalse(sut.goToBookmarkRequest)
        XCTAssertNil(sut.toastMessage)
    }

    func testClosePDFReader_withFlusher_waitsThenClears() {
        sut.selectedPDFURL = tempPDFURL
        var completion: (() -> Void)?
        sut.saveFlusher = SaveFlusher(
            asyncHandler: { completion = $0 },
            syncHandler: {}
        )

        sut.closePDFReader()
        XCTAssertTrue(sut.isSavingBeforeClose)
        XCTAssertNotNil(sut.selectedPDFURL)

        // Re-entrant close while saving is ignored.
        sut.closePDFReader()
        XCTAssertTrue(sut.isSavingBeforeClose)

        completion?()
        XCTAssertFalse(sut.isSavingBeforeClose)
        XCTAssertNil(sut.selectedPDFURL)
    }

    // MARK: - Search

    func testPerformSearch_emptyQuery_clearsResults() {
        sut.searchText = "   "
        sut.selectedPDFURL = tempPDFURL
        sut.performSearch()
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    func testPerformSearch_withoutURL_leavesResultsEmpty() {
        sut.searchText = "UniqueNeedleAlpha"
        sut.performSearch()
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    func testPerformSearch_findsMatchesAndBuildsSnippets() async {
        sut.selectedPDFURL = tempPDFURL
        sut.searchText = "UniqueNeedleAlpha"
        sut.performSearch()

        let expectation = expectation(description: "search results")
        var cancellable: AnyCancellable?
        cancellable = sut.$searchResults
            .dropFirst()
            .sink { results in
                if !results.isEmpty {
                    expectation.fulfill()
                }
            }
        await fulfillment(of: [expectation], timeout: 3)
        cancellable?.cancel()

        XCTAssertFalse(sut.searchResults.isEmpty)
        XCTAssertEqual(sut.searchResults.first?.pageIndex, 0)
        XCTAssertTrue(sut.searchResults.first?.snippet.contains("UniqueNeedleAlpha") ?? false)
        // Ellipsis branches from surrounding context.
        XCTAssertTrue(sut.searchResults.first?.snippet.contains("…") ?? false)
    }

    func testPerformSearch_cancelledDebounce_doesNotPublishStaleResults() async {
        sut.selectedPDFURL = tempPDFURL
        sut.searchDebounceNanoseconds = 200_000_000
        sut.searchText = "UniqueNeedleAlpha"
        sut.performSearch()
        sut.searchText = "   "
        sut.performSearch()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    func testPerformSearch_invalidPDFURL_returnsEmpty() async {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-pdf-\(UUID().uuidString).pdf")
        try? "not pdf".write(to: bogus, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: bogus) }

        sut.selectedPDFURL = bogus
        sut.searchText = "anything"
        sut.performSearch()

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    func testSelectSearchResult_setsNavigationAndClosesSearch() async throws {
        sut.selectedPDFURL = tempPDFURL
        sut.searchText = "UniqueNeedleBeta"
        sut.isSearching = true
        sut.performSearch()

        let expectation = expectation(description: "search ready")
        var cancellable: AnyCancellable?
        cancellable = sut.$searchResults
            .dropFirst()
            .sink { results in
                if !results.isEmpty { expectation.fulfill() }
            }
        await fulfillment(of: [expectation], timeout: 3)
        cancellable?.cancel()

        let result = try XCTUnwrap(sut.searchResults.first)
        sut.selectSearchResult(result)
        XCTAssertEqual(sut.searchNavigation?.searchText, "UniqueNeedleBeta")
        XCTAssertEqual(sut.searchNavigation?.matchIndex, result.matchIndex)
        XCTAssertFalse(sut.isSearching)
    }

    // MARK: - Page change → session tracker wiring

    func testCurrentPageChange_forwardsToSessionTrackerWithoutInflatingPages() async throws {
        sut.saveRecentFile(tempPDFURL)
        sut.initialPage = 0
        sut.beginReadingSession()
        // Simulate restore jump before user interaction.
        sut.currentPage = 0
        sut.currentPage = 1
        sut.onReaderInteraction()
        sut.currentPage = 1
        try await Task.sleep(nanoseconds: 1_100_000_000)
        sut.closePDFReader()

        let session = insights.sessions.last
        XCTAssertNotNil(session)
        // After lock at page 1, ending on 1 → 0 pages advanced (not inflated from 0).
        XCTAssertEqual(session?.pagesRead, 0)
    }

    // MARK: - Snippet builder

    func testBuildSnippet_nilOrEmptyMatch_returnsEmptyOrMatch() {
        XCTAssertEqual(PDFReaderViewModel.buildSnippet(matchText: nil, pageText: "abc", maxLength: 80), "")
        XCTAssertEqual(PDFReaderViewModel.buildSnippet(matchText: "", pageText: "abc", maxLength: 80), "")
        XCTAssertEqual(PDFReaderViewModel.buildSnippet(matchText: "x", pageText: nil, maxLength: 80), "x")
    }

    func testBuildSnippet_matchMissingFromPage_returnsPrefix() {
        let long = String(repeating: "m", count: 100)
        let snippet = PDFReaderViewModel.buildSnippet(matchText: long, pageText: "completely different", maxLength: 20)
        XCTAssertEqual(snippet, String(repeating: "m", count: 20))
    }

    func testBuildSnippet_matchAtStart_hasTrailingEllipsisOnly() {
        let page = "Needle " + String(repeating: "tail ", count: 40)
        let snippet = PDFReaderViewModel.buildSnippet(matchText: "Needle", pageText: page, maxLength: 40)
        XCTAssertFalse(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
    }

    func testBuildSnippet_matchAtEnd_hasLeadingEllipsisOnly() {
        let page = String(repeating: "head ", count: 40) + "Needle"
        let snippet = PDFReaderViewModel.buildSnippet(matchText: "Needle", pageText: page, maxLength: 40)
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertFalse(snippet.hasSuffix("…"))
    }

    // MARK: - Import edge cases

    func testSaveRecentFile_bookmarkFailure_doesNotAddFile() {
        sut.bookmarkDataProvider = { _ in nil }
        sut.saveRecentFile(tempPDFURL)
        XCTAssertTrue(sut.recentFiles.isEmpty)
        XCTAssertNil(sut.currentFileId)
    }

    func testSaveRecentFile_nonPDF_skipsPageCountButStillSaves() throws {
        let plain = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString).pdf")
        try "hello".write(to: plain, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: plain) }

        sut.totalPages = 99
        sut.saveRecentFile(plain)
        XCTAssertEqual(sut.recentFiles.count, 1)
        // PDFDocument fails → totalPages unchanged from prior value.
        XCTAssertEqual(sut.totalPages, 99)
    }

    func testGetFileSize_directory_returnsUnknown() {
        let size = sut.getFileSize(FileManager.default.temporaryDirectory)
        XCTAssertFalse(size.isEmpty)
    }

    func testGetFileSize_unsupportedURL_returnsUnknown() {
        let url = URL(string: "customscheme://host/file.pdf")!
        let size = sut.getFileSize(url)
        XCTAssertFalse(size.isEmpty)
    }

    func testGetFileSize_thrownError_returnsUnknown() {
        sut.fileSizeResourceValues = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }
        let size = sut.getFileSize(tempPDFURL)
        XCTAssertFalse(size.isEmpty)
    }

    func testSaveRecentFile_usesCustomFileSizeProvider() {
        sut.fileSizeProvider = { _ in "42 bytes" }
        sut.saveRecentFile(tempPDFURL)
        XCTAssertEqual(sut.recentFiles.first?.fileSize, "42 bytes")
    }

    func testRecentFile_missingLastOpenedAt_fallsBackToDateAdded() throws {
        let added = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "name": "legacy.pdf",
            "bookmarkData": Data([1, 2, 3]).base64EncodedString(),
            "dateAdded": ISO8601DateFormatter().string(from: added),
            "fileSize": "1 KB",
            "lastPageNumber": 0,
            "totalPages": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(RecentFile.self, from: data)
        XCTAssertEqual(file.lastOpenedAt, file.dateAdded)
    }
}
