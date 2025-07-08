//
//  PDFReaderView.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import SwiftUI

struct PDFReaderView: View {
    @State private var selectedPDFURL: URL?
    @State private var showingDocumentPicker = false
    @State private var recentFiles: [RecentFile] = []
    
    var body: some View {
        NavigationView {
            VStack {
                if let pdfURL = selectedPDFURL {
                    PDFViewer(url: pdfURL)
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
                    saveRecentFile(url)
                }
            }
        }
    }
    
    private func openRecentFile(_ file: RecentFile) {
        guard let url = URL.resolveBookmark(file.bookmarkData) else {
            // File is no longer accessible, remove from recent files
            removeRecentFile(file)
            return
        }
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
        
        let fileName = url.lastPathComponent
        let fileSize = getFileSize(url)
        
        let recentFile = RecentFile(
            id: UUID(),
            name: fileName,
            bookmarkData: bookmarkData,
            dateAdded: Date(),
            fileSize: fileSize
        )
        
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
