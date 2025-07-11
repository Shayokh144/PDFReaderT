//
//  PDFReaderView.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import PDFKit
import SwiftUI

struct PDFReaderView: View {
    @State private var selectedPDFURL: URL?
    @State private var showingDocumentPicker = false
    @State private var recentFiles: [RecentFile] = []
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @State private var initialPage: Int? = nil
    @State private var currentFileId: UUID? = nil
    @State private var pageSaveTimer: Timer?
    
    var body: some View {
        NavigationView {
            VStack {
                if let pdfURL = selectedPDFURL {
                    PDFViewer(
                        url: pdfURL,
                        initialPage: initialPage,
                        currentPage: $currentPage
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(currentPage)/\(totalPages)")
                            .padding(8.0)
                            .background(Color.gray.opacity(0.7))
                            .cornerRadius(8.0)
                            .padding(8.0)
                    }
                    .onAppear {
                        startPageSaveTimer()
                    }
                    .onDisappear {
                        stopPageSaveTimer()
                        saveCurrentPage()
                    }
                } else {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "No PDF Selected",
                            systemImage: "doc.text",
                            description: Text("Select a PDF file or choose from recent files")
                        )
                        
                        if !recentFiles.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Recent Files")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(recentFiles) { file in
                                            RecentFileRow(file: file) {
                                                openRecentFile(file)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .frame(maxHeight: 200)
                            }
                        }
                    }
                }
                if selectedPDFURL == nil {
                    Button("Select PDF") {
                        showingDocumentPicker = true
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(height: 40.0)
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .cornerRadius(8.0)
                    .padding()
                }
            }
            .navigationTitle("PDF Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedPDFURL != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            selectedPDFURL = nil
                            currentFileId = nil
                            initialPage = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(selectedURL: $selectedPDFURL, isPresented: $showingDocumentPicker)
            }
            .onAppear {
                loadRecentFiles()
            }
            .onChange(of: selectedPDFURL) { newURL in
                if let url = newURL {
                    currentPage = 0
                    initialPage = nil
                    currentFileId = nil
                    saveRecentFile(url)
                }
            }
        }
    }
    
    private func startPageSaveTimer() {
        pageSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            saveCurrentPage()
        }
    }
    
    private func stopPageSaveTimer() {
        pageSaveTimer?.invalidate()
        pageSaveTimer = nil
    }
    
    private func saveCurrentPage() {
        print("XYZ saveCurrentPage")

        guard let fileId = currentFileId,
              let index = recentFiles.firstIndex(where: { $0.id == fileId }) else {
            print("XYZ saveCurrentPage  not found")
            return
        }
        
        var updatedFile = recentFiles[index]
        updatedFile.lastPageNumber = currentPage
        recentFiles[index] = updatedFile
        
        saveRecentFilesToUserDefaults()
        print("XYZ Saved current page: \(currentPage) for file: \(updatedFile.name)")
    }

    
    private func openRecentFile(_ file: RecentFile) {
        guard let url = URL.resolveBookmark(file.bookmarkData) else {
            // File is no longer accessible, remove from recent files
            removeRecentFile(file)
            return
        }
        initialPage = file.lastPageNumber
        currentFileId = file.id
        selectedPDFURL = url
    }
    
    private func saveRecentFile(_ url: URL) {
        print("Attempting to save recent file: \(url.path)")
        
        // Ensure we have access to the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access security-scoped resource")
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        // Verify the file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("File does not exist at path: \(url.path)")
            return
        }
        
        // Create bookmark while we have access
        guard let bookmarkData = url.bookmarkData() else {
            print("XYZ NO BOOK MARK FOUND")
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
        // Remove existing entry if it exists
        recentFiles.removeAll { $0.name == fileName }
        
        // Add to beginning of array
        recentFiles.insert(recentFile, at: 0)
        
        // Keep only the last 10 files
        if recentFiles.count > 10 {
            recentFiles = Array(recentFiles.prefix(10))
        }
        
        // Save to UserDefaults
        saveRecentFilesToUserDefaults()
        
        print("xyz Successfully saved recent file: \(fileName)")
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
            print("Error getting file size: \(error)")
        }
        return "Unknown"
    }
    
    private func loadRecentFiles() {
        guard let data = UserDefaults.standard.data(forKey: "RecentPDFFiles") else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            recentFiles = try decoder.decode([RecentFile].self, from: data)
        } catch {
            print("Error loading recent files: \(error)")
        }
    }
    
    private func saveRecentFilesToUserDefaults() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recentFiles)
            UserDefaults.standard.set(data, forKey: "RecentPDFFiles")
        } catch {
            print("Error saving recent files: \(error)")
        }
    }
}
