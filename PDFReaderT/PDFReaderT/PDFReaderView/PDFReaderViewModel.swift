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
    
    var saveFlusher: SaveFlusher?
    
    private var pageSaveTimer: Timer?
    private let recentFilesStore: RecentFilesStoring
    
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
    
    private static func localizedString(for key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key))
    }
    
    func onSelectedPDFURLChanged(_ newURL: URL?) {
        if let url = newURL {
            currentPage = 0
            currentFileId = nil
            initialPage = nil
            saveRecentFile(url)
        }
    }
    
    func onDidEnterBackground() {
        saveCurrentPage()
        saveFlusher?.flushSync()
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
        
        let recentFile = RecentFile(
            id: UUID(),
            name: fileName,
            bookmarkData: bookmarkData,
            dateAdded: Date(),
            fileSize: fileSize,
            lastPageNumber: 0,
            totalPages: totalPages
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
            isSavingBeforeClose: isSavingBeforeClose
        )
    }
}
