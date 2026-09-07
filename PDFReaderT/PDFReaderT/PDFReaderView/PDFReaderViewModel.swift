//
//  PDFReaderViewModel.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import Foundation
import Combine
import OSLog
import PDFKit

private let log = AppLog.viewModel

/// Content for a dismiss-only alert with a single **OK** action. Pass localized strings, or use `presentOKOnlyAlert(titleKey:messageKey:)`.
struct OKOnlyAlertContent: Equatable {
    let title: String
    let message: String
}

struct PDFReaderViewUIModel {
    let selectedPDFURL: URL?
    let recentFiles: [RecentFile]
    let currentPage: Int
    let totalPages: Int
    let initialPage: Int?
    let showingDocumentPicker: Bool
    let okOnlyAlert: OKOnlyAlertContent?
    let isSavingBeforeClose: Bool
    let isFullScreen: Bool
    let isSearching: Bool
    let searchResults: [PDFSearchResult]
    let searchNavigation: SearchNavigationRequest?
}

@MainActor
final class PDFReaderViewModel: ObservableObject {
    
    @Published var selectedPDFURL: URL?
    @Published var showingDocumentPicker = false
    @Published var recentFiles: [RecentFile] = []
    @Published var currentPage: Int = 0
    @Published var totalPages: Int = 0
    @Published var initialPage: Int? = nil
    @Published var currentFileId: UUID? = nil
    @Published private(set) var okOnlyAlert: OKOnlyAlertContent?
    @Published private(set) var isSavingBeforeClose = false
    @Published var isFullScreen = false
    @Published var isSearching = false
    @Published var showingStats = false
    @Published var searchText = ""
    @Published private(set) var searchResults: [PDFSearchResult] = []
    @Published var searchNavigation: SearchNavigationRequest?
    
    @Published var showingInsights = false
    @Published private(set) var dailyStats: [DailyReadingStats] = []
    @Published private(set) var recentSessions: [ReadingSession] = []
    @Published var goToBookmarkRequest = false
    @Published private(set) var toastMessage: String?

    var saveFlusher: SaveFlusher?
    private var toastDismissTask: Task<Void, Never>?
    
    private var pageSaveTimer: Timer?
    private var searchDebounceTask: Task<Void, Never>?
    private let recentFilesStore: RecentFilesStoring
    private let insightsStorage: ReadingInsightsStoring
    private let sessionTracker: ReadingSessionTracker
    private var pageChangeCancellable: AnyCancellable?

    private var readingSessionStart: Date?
    private var readingSessionFileId: UUID?

    /// Toast auto-dismiss delay. Overridable in tests.
    var toastDurationNanoseconds: UInt64 = 2_000_000_000
    /// Search debounce delay. Overridable in tests.
    var searchDebounceNanoseconds: UInt64 = 300_000_000
    /// Page autosave interval. Overridable in tests.
    var pageSaveInterval: TimeInterval = 5.0
    /// Creates bookmark data for a file URL. Overridable in tests.
    var bookmarkDataProvider: (URL) -> Data? = { $0.bookmarkData() }
    /// Resolves a human-readable file size. Overridable in tests.
    var fileSizeProvider: ((URL) -> String)?
    
    init(
        recentFilesStore: RecentFilesStoring = UserDefaultsRecentFilesStore(),
        insightsStorage: ReadingInsightsStoring = ReadingInsightsStorage()
    ) {
        self.recentFilesStore = recentFilesStore
        self.insightsStorage = insightsStorage
        self.sessionTracker = ReadingSessionTracker(storage: insightsStorage)

        sessionTracker.onSessionRecorded = { [weak self] in
            self?.reloadInsightsData()
        }

        pageChangeCancellable = $currentPage
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] page in
                // Page changes alone must not lock startPage — restore-to-last-page
                // would otherwise count the jump from 0 as "pages read".
                self?.sessionTracker.onPageChanged(currentPage: page)
            }
    }
    
    func onAppear() {
        loadRecentFiles()
        reloadInsightsData()
    }
    
    /// Shows an informational alert with **OK** only. Use for errors that need no follow-up action.
    func presentOKOnlyAlert(title: String, message: String) {
        okOnlyAlert = OKOnlyAlertContent(title: title, message: message)
    }
    
    /// Same as `presentOKOnlyAlert(title:message:)`, using `Localizable.xcstrings` keys.
    func presentOKOnlyAlert(titleKey: String, messageKey: String) {
        presentOKOnlyAlert(
            title: Self.localizedString(for: titleKey),
            message: Self.localizedString(for: messageKey)
        )
    }
    
    func dismissOKOnlyAlert() {
        okOnlyAlert = nil
    }
    
    func toggleFullScreen() {
        isFullScreen.toggle()
    }

    /// Called by PDFViewer on any touch/scroll/pinch interaction.
    func onReaderInteraction() {
        sessionTracker.onUserInteraction(currentPage: currentPage)
    }

    /// Asks the PDF viewer to scroll to the saved bookmark (or toast if none).
    func requestGoToBookmark() {
        goToBookmarkRequest = true
    }

    func showBookmarkMissingToast() {
        showToast(Self.localizedString(for: "pdf_reader.bookmark_missing"))
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: toastDurationNanoseconds)
            guard !Task.isCancelled else { return }
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
    
    // MARK: - Search
    
    func performSearch() {
        searchDebounceTask?.cancel()
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        guard let url = selectedPDFURL else { return }
        
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: searchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            
            let results = await Self.findMatches(query: query, fileURL: url)
            guard !Task.isCancelled else { return }
            
            self.searchResults = results
        }
    }
    
    func selectSearchResult(_ result: PDFSearchResult) {
        searchNavigation = SearchNavigationRequest(
            searchText: searchText,
            matchIndex: result.matchIndex
        )
        isSearching = false
    }
    
    private nonisolated static func findMatches(query: String, fileURL: URL) async -> [PDFSearchResult] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Non-security-scoped URLs (e.g. app temp files) return false; still readable.
                let accessed = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                }
                
                guard let document = PDFDocument(url: fileURL) else {
                    continuation.resume(returning: [])
                    return
                }
                
                let selections = document.findString(query, withOptions: [.caseInsensitive])
                
                let results: [PDFSearchResult] = selections.enumerated().compactMap { index, selection in
                    guard let page = selection.pages.first else { return nil }
                    let pageIndex = document.index(for: page)
                    let snippet = Self.buildSnippet(
                        matchText: selection.string,
                        pageText: page.string,
                        maxLength: 80
                    )
                    return PDFSearchResult(pageIndex: pageIndex, snippet: snippet, matchIndex: index, selection: selection)
                }
                
                continuation.resume(returning: results)
            }
        }
    }
    
    /// Builds a short search snippet. Visible for unit tests.
    nonisolated static func buildSnippet(matchText: String?, pageText: String?, maxLength: Int) -> String {
        guard let matchText, !matchText.isEmpty, let pageText else {
            return matchText ?? ""
        }
        
        let flatPageText = pageText.replacingOccurrences(of: "\n", with: " ")
        let flatMatch = matchText.replacingOccurrences(of: "\n", with: " ")
        
        guard let matchRange = flatPageText.range(of: flatMatch, options: .caseInsensitive) else {
            return String(flatMatch.prefix(maxLength))
        }
        
        let contextChars = (maxLength - flatMatch.count) / 2
        let snippetStart = flatPageText.index(matchRange.lowerBound, offsetBy: -contextChars, limitedBy: flatPageText.startIndex) ?? flatPageText.startIndex
        let snippetEnd = flatPageText.index(matchRange.upperBound, offsetBy: contextChars, limitedBy: flatPageText.endIndex) ?? flatPageText.endIndex
        
        var snippet = String(flatPageText[snippetStart..<snippetEnd])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        if snippetStart > flatPageText.startIndex { snippet = "…" + snippet }
        if snippetEnd < flatPageText.endIndex { snippet = snippet + "…" }
        
        return snippet
    }
    
    private static func localizedString(for key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key))
    }
    
    func onSelectedPDFURLChanged(_ newURL: URL?) {
        if sessionTracker.hasActiveSession {
            sessionTracker.endSession(currentPage: currentPage)
        }
        commitReadingTimeIfNeeded()
        if let url = newURL {
            // `openRecentFile` sets `currentFileId` before the URL; skip re-registering
            // so the same document id (and last page / bookmark) is preserved.
            if currentFileId == nil {
                currentPage = 0
                initialPage = nil
                saveRecentFile(url)
            }
        }
    }
    
    func onDidEnterBackground() {
        commitReadingTimeIfNeeded()
        saveCurrentPage()
        saveFlusher?.flushSync()
    }

    /// Call when the PDF viewer becomes visible while the app is active.
    func beginReadingSession() {
        guard let fid = currentFileId, readingSessionStart == nil else { return }
        readingSessionStart = Date()
        readingSessionFileId = fid

        if !sessionTracker.hasActiveSession,
           let file = recentFiles.first(where: { $0.id == fid }) {
            // Prefer initialPage: currentPage is often still 0 until PDFView restores.
            let page = initialPage ?? currentPage
            sessionTracker.startSession(documentId: fid, documentName: file.name, page: page)
        } else {
            sessionTracker.resumeFromForeground()
        }
    }

    /// Pauses tracking (e.g. leaving the reader or app background) and persists elapsed time for the session file.
    func commitReadingTimeIfNeeded() {
        guard let fid = readingSessionFileId,
              let start = readingSessionStart,
              let index = recentFiles.firstIndex(where: { $0.id == fid }) else {
            readingSessionStart = nil
            readingSessionFileId = nil
            return
        }

        let delta = Date().timeIntervalSince(start)
        readingSessionStart = nil
        readingSessionFileId = nil

        guard delta > 0 else { return }

        var updatedFile = recentFiles[index]
        updatedFile.readingTimeSeconds += delta
        recentFiles[index] = updatedFile
        saveRecentFilesToUserDefaults()
        log.info("\(AppLog.scopePrefix(for: Self.self)) saved reading time +\(delta)s for file \(updatedFile.name)")

        sessionTracker.pauseForBackground(currentPage: currentPage)
    }
    
    func deleteFile(at offsets: IndexSet) {
        recentFiles.remove(atOffsets: offsets)
        saveRecentFilesToUserDefaults()
    }
    
    func startPageSaveTimer() {
        pageSaveTimer = Timer.scheduledTimer(withTimeInterval: pageSaveInterval, repeats: true) { _ in
            Task { @MainActor in
                self.saveCurrentPage()
            }
        }
    }
    
    func stopPageSaveTimer() {
        pageSaveTimer?.invalidate()
        pageSaveTimer = nil
    }
    
    func saveCurrentPage() {
        guard let fileId = currentFileId,
              let index = recentFiles.firstIndex(where: { $0.id == fileId }) else {
            log.warning("\(AppLog.scopePrefix(for: Self.self)) no matching recent file for current file id")
            return
        }
        
        var updatedFile = recentFiles[index]
        updatedFile.lastPageNumber = currentPage
        recentFiles[index] = updatedFile
        
        saveRecentFilesToUserDefaults()
        log.info("\(AppLog.scopePrefix(for: Self.self)) saved current page \(self.currentPage) for file \(updatedFile.name)")
    }
    
    func openRecentFile(_ file: RecentFile) {
        guard let url = URL.resolveBookmark(file.bookmarkData) else {
            removeRecentFile(file)
            presentOKOnlyAlert(
                titleKey: "pdf_reader.deleted_recent_alert_title",
                messageKey: "pdf_reader.deleted_recent_alert_message"
            )
            return
        }
        markFileOpened(file.id)
        initialPage = file.lastPageNumber
        currentFileId = file.id
        selectedPDFURL = url
    }

    private func markFileOpened(_ fileId: UUID) {
        guard let index = recentFiles.firstIndex(where: { $0.id == fileId }) else { return }
        var updatedFile = recentFiles[index]
        updatedFile.lastOpenedAt = Date()
        recentFiles.remove(at: index)
        recentFiles.insert(updatedFile, at: 0)
        saveRecentFilesToUserDefaults()
    }
    
    func closePDFReader() {
        guard !isSavingBeforeClose else { return }

        sessionTracker.endSession(currentPage: currentPage)
        commitReadingTimeIfNeeded()
        saveCurrentPage()
        
        guard let saveFlusher else {
            performClose()
            return
        }
        
        isSavingBeforeClose = true
        saveFlusher.flush { [weak self] in
            guard let self else { return }
            self.isSavingBeforeClose = false
            self.performClose()
        }
    }
    
    private func performClose() {
        selectedPDFURL = nil
        currentFileId = nil
        initialPage = nil
        saveFlusher = nil
        isFullScreen = false
        isSearching = false
        searchText = ""
        searchResults = []
        searchNavigation = nil
        goToBookmarkRequest = false
        toastMessage = nil
        toastDismissTask?.cancel()
        searchDebounceTask?.cancel()
    }
    
    func saveRecentFile(_ url: URL) {
        log.info("\(AppLog.scopePrefix(for: Self.self)) attempting to save recent file at path \(url.path)")

        // Non-security-scoped URLs return false; the file may still be readable.
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            log.error("\(AppLog.scopePrefix(for: Self.self)) file does not exist at path \(url.path)")
            return
        }
        
        guard let bookmarkData = bookmarkDataProvider(url) else {
            log.error("\(AppLog.scopePrefix(for: Self.self)) could not create bookmark data for selected file")
            return
        }
        if let document = PDFDocument(url: url) {
            totalPages = document.pageCount
        }
        
        let fileName = url.lastPathComponent
        let fileSize = fileSizeProvider?(url) ?? getFileSize(url)
        let existing = recentFiles.first(where: { $0.name == fileName })
        let now = Date()

        let recentFile = RecentFile(
            id: UUID(),
            name: fileName,
            bookmarkData: bookmarkData,
            dateAdded: existing?.dateAdded ?? now,
            lastOpenedAt: now,
            fileSize: fileSize,
            lastPageNumber: 0,
            totalPages: totalPages,
            readingTimeSeconds: existing?.readingTimeSeconds ?? 0
        )
        
        currentFileId = recentFile.id
        recentFiles.removeAll { $0.name == fileName }
        
        recentFiles.insert(recentFile, at: 0)
        
        //        // Keep only the last 10 files
        //        if recentFiles.count > 10 {
        //            recentFiles = Array(recentFiles.prefix(10))
        //        }
        
        saveRecentFilesToUserDefaults()
        
        log.info("\(AppLog.scopePrefix(for: Self.self)) saved recent file \(fileName)")
    }
    
    private func removeRecentFile(_ file: RecentFile) {
        recentFiles.removeAll { $0.id == file.id }
        saveRecentFilesToUserDefaults()
    }
    
    /// Resolves file-size resource values. Overridable in tests to force failures.
    var fileSizeResourceValues: (URL) throws -> URLResourceValues = {
        try $0.resourceValues(forKeys: [.fileSizeKey])
    }

    /// Visible for unit tests covering size lookup failure paths.
    func getFileSize(_ url: URL) -> String {
        do {
            let resources = try fileSizeResourceValues(url)
            if let fileSize = resources.fileSize {
                return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
            }
        } catch {
            log.error("\(AppLog.scopePrefix(for: Self.self)) error getting file size: \(error.localizedDescription)")
        }
        return String(localized: "pdf_reader.file_size_unknown")
    }
    
    private func loadRecentFiles() {
        switch recentFilesStore.loadRecentFiles() {
            case .noStoredData:
                break
            case .loaded(let files):
                recentFiles = files.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            case .decodeFailed(let error):
                log.error("\(AppLog.scopePrefix(for: Self.self)) error loading recent files: \(error.localizedDescription)")
        }
    }
    
    private func saveRecentFilesToUserDefaults() {
        recentFilesStore.saveRecentFiles(recentFiles)
    }

    private func reloadInsightsData() {
        dailyStats = insightsStorage.loadDailyStats()
        recentSessions = insightsStorage.loadSessions()
    }
    
    var uiModel: PDFReaderViewUIModel {
        PDFReaderViewUIModel(
            selectedPDFURL: selectedPDFURL,
            recentFiles: recentFiles,
            currentPage: currentPage,
            totalPages: totalPages,
            initialPage: initialPage,
            showingDocumentPicker: showingDocumentPicker,
            okOnlyAlert: okOnlyAlert,
            isSavingBeforeClose: isSavingBeforeClose,
            isFullScreen: isFullScreen,
            isSearching: isSearching,
            searchResults: searchResults,
            searchNavigation: searchNavigation
        )
    }
}
