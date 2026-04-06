//
//  PDFReaderViewModel.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import Foundation
import OSLog
import PDFKit
import SwiftUI

private let log = AppLog.viewModel

struct PDFReaderViewUIModel {
    let selectedPDFURL: URL?
    let recentFiles: [RecentFile]
    let currentPage: Int
    let totalPages: Int
    let initialPage: Int?
    let showingDocumentPicker: Bool
    let selectedPDFURLBinding: Binding<URL?>
    let showingDocumentPickerBinding: Binding<Bool>
    let currentPageBinding: Binding<Int>
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
    
    private var pageSaveTimer: Timer?
    private let recentFilesStore: RecentFilesStoring
    
    init(recentFilesStore: RecentFilesStoring = UserDefaultsRecentFilesStore()) {
        self.recentFilesStore = recentFilesStore
    }
    
    func onAppear() {
        loadRecentFiles()
    }
    
    func onSelectedPDFURLChanged(_ newURL: URL?) {
        if let url = newURL {
            currentPage = 0
            currentFileId = nil
            initialPage = nil
            saveRecentFile(url)
        }
    }
    
    func onScenePhaseChanged(_ newPhase: ScenePhase) {
        if newPhase == .background {
            saveCurrentPage()
        }
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
            return
        }
        initialPage = file.lastPageNumber
        currentFileId = file.id
        selectedPDFURL = url
    }
    
    func closePDFReader() {
        saveCurrentPage()
        selectedPDFURL = nil
        currentFileId = nil
        initialPage = nil
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
            selectedPDFURLBinding: Binding(
                get: { self.selectedPDFURL },
                set: { self.selectedPDFURL = $0 }
            ),
            showingDocumentPickerBinding: Binding(
                get: { self.showingDocumentPicker },
                set: { self.showingDocumentPicker = $0 }
            ),
            currentPageBinding: Binding(
                get: { self.currentPage },
                set: { self.currentPage = $0 }
            )
        )
    }
}
