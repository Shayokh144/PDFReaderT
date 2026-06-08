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
    @Published var searchText = ""
    @Published private(set) var searchResults: [PDFSearchResult] = []
    @Published var searchNavigation: SearchNavigationRequest?
    
    var saveFlusher: SaveFlusher?
    
    private var pageSaveTimer: Timer?
    private var searchDebounceTask: Task<Void, Never>?
    private let recentFilesStore: RecentFilesStoring

    private var readingSessionStart: Date?
    private var readingSessionFileId: UUID?
    
    init(recentFilesStore: RecentFilesStoring = UserDefaultsRecentFilesStore()) {
        self.recentFilesStore = recentFilesStore
    }
    
    func onAppear() {
        loadRecentFiles()
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
            try? await Task.sleep(nanoseconds: 300_000_000)
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
                guard fileURL.startAccessingSecurityScopedResource() else {
                    continuation.resume(returning: [])
                    return
                }
                defer { fileURL.stopAccessingSecurityScopedResource() }
                
                guard let document = PDFDocument(url: fileURL) else {
                    continuation.resume(returning: [])
                    return
                }
                
                let selections = document.findString(query, withOptions: [.caseInsensitive])
                
                let results: [PDFSearchResult] = selections.enumerated().compactMap { index, selection in
                    guard let page = selection.pages.first else { return nil }
                    let pageIndex = document.index(for: page)
                    let snippet = buildSnippet(from: selection, on: page, maxLength: 80)
                    return PDFSearchResult(pageIndex: pageIndex, snippet: snippet, matchIndex: index, selection: selection)
                }
                
                continuation.resume(returning: results)
            }
        }
    }
    
    private nonisolated static func buildSnippet(from selection: PDFSelection, on page: PDFPage, maxLength: Int) -> String {
        guard let matchText = selection.string, !matchText.isEmpty,
              let pageText = page.string else {
            return selection.string ?? ""
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
        commitReadingTimeIfNeeded()
        if let url = newURL {
            currentPage = 0
            currentFileId = nil
            initialPage = nil
            saveRecentFile(url)
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
        log.debug("\(AppLog.scopePrefix(for: Self.self)) saved reading time +\(delta, privacy: .public)s for file \(updatedFile.name)")
    }
    
    func deleteFile(at offsets: IndexSet) {
        recentFiles.remove(atOffsets: offsets)
        saveRecentFilesToUserDefaults()
    }
    
    func startPageSaveTimer() {
        pageSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
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
        log.debug("\(AppLog.scopePrefix(for: Self.self)) saved current page \(self.currentPage) for file \(updatedFile.name)")
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
        initialPage = file.lastPageNumber
        currentFileId = file.id
        selectedPDFURL = url
    }
    
    func closePDFReader() {
        guard !isSavingBeforeClose else { return }

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
        searchDebounceTask?.cancel()
    }
    
    func saveRecentFile(_ url: URL) {
        log.debug("\(AppLog.scopePrefix(for: Self.self)) attempting to save recent file at path \(url.path, privacy: .private)")
        
        guard url.startAccessingSecurityScopedResource() else {
            log.error("\(AppLog.scopePrefix(for: Self.self)) failed to access security-scoped resource")
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            log.error("\(AppLog.scopePrefix(for: Self.self)) file does not exist at path \(url.path, privacy: .private)")
            return
        }
        
        guard let bookmarkData = url.bookmarkData() else {
            log.error("\(AppLog.scopePrefix(for: Self.self)) could not create bookmark data for selected file")
            return
        }
        if let document = PDFDocument(url: url) {
            totalPages = document.pageCount
        }
        
        let fileName = url.lastPathComponent
        let fileSize = getFileSize(url)
        let preservedReadingTime = recentFiles.first(where: { $0.name == fileName })?.readingTimeSeconds ?? 0

        let recentFile = RecentFile(
            id: UUID(),
            name: fileName,
            bookmarkData: bookmarkData,
            dateAdded: Date(),
            fileSize: fileSize,
            lastPageNumber: 0,
            totalPages: totalPages,
            readingTimeSeconds: preservedReadingTime
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
    
    private func getFileSize(_ url: URL) -> String {
        do {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
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
                recentFiles = files
            case .decodeFailed(let error):
                log.error("\(AppLog.scopePrefix(for: Self.self)) error loading recent files: \(error.localizedDescription)")
        }
    }
    
    private func saveRecentFilesToUserDefaults() {
        recentFilesStore.saveRecentFiles(recentFiles)
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
