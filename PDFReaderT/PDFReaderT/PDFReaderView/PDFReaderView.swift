//
//  PDFReaderView.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import PDFKit
import SwiftUI

struct PDFReaderView: View {
    
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var viewModel : PDFReaderViewModel
    
    var body: some View {
        let uiModel = viewModel.uiModel
        NavigationView {
            VStack {
                if uiModel.selectedPDFURL != nil {
                    pdfDocumentView(uiModel: uiModel)
                } else {
                    emptyStateView(uiModel: uiModel)
                }
                if uiModel.selectedPDFURL == nil {
                    selectPDFButton(uiModel: uiModel)
                }
            }
            .navigationTitle(String(localized: "pdf_reader.navigation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if uiModel.selectedPDFURL != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized: "pdf_reader.close")) {
                            viewModel.closePDFReader()
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingDocumentPicker) {
                DocumentPicker(
                    selectedURL: $viewModel.selectedPDFURL,
                    isPresented: $viewModel.showingDocumentPicker
                )
            }
            .onAppear {
                viewModel.onAppear()
            }
            .onChange(of: uiModel.selectedPDFURL) { _, newURL in
                viewModel.onSelectedPDFURLChanged(newURL)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    viewModel.onDidEnterBackground()
                }
            }
            .alert(
                Text(uiModel.okOnlyAlert?.title ?? ""),
                isPresented: Binding(
                    get: { viewModel.okOnlyAlert != nil },
                    set: { if !$0 { viewModel.dismissOKOnlyAlert() } }
                )
            ) {
                Button(String(localized: "pdf_reader.ok"), role: .cancel) {
                    viewModel.dismissOKOnlyAlert()
                }
            } message: {
                if let message = uiModel.okOnlyAlert?.message {
                    Text(message)
                }
            }
        }
    }
    
    @ViewBuilder
    private func emptyStateView(uiModel: PDFReaderViewUIModel) -> some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                String(localized: "pdf_reader.empty_title"),
                systemImage: "doc.text",
                description: Text("pdf_reader.empty_description")
            )
            
            if !uiModel.recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("pdf_reader.recent_files")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    List {
                        ForEach(uiModel.recentFiles) { file in
                            RecentFileRow(file: file) {
                                viewModel.openRecentFile(file)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .padding(.horizontal)
                            .padding(.vertical, 4.0)
                        }
                        .onDelete(perform: viewModel.deleteFile)
                    }
                    .listStyle(PlainListStyle())
                }
            }
        }
    }
    
    @ViewBuilder
    private func selectPDFButton(uiModel: PDFReaderViewUIModel) -> some View {
        Button(String(localized: "pdf_reader.select_pdf")) {
            viewModel.showingDocumentPicker = true
        }
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(.black)
        .frame(height: 40.0)
        .frame(maxWidth: .infinity)
        .background(Color.green)
        .cornerRadius(8.0)
        .padding()
    }
    
    @ViewBuilder
    private func pdfDocumentView(uiModel: PDFReaderViewUIModel) -> some View {
        if let url = uiModel.selectedPDFURL {
            PDFViewer(
                url: url,
                initialPage: uiModel.initialPage,
                currentPage: $viewModel.currentPage
            )
            .overlay(alignment: .bottomTrailing) {
                Text(
                    String(
                        format: String(localized: "pdf_reader.page_counter"),
                        uiModel.currentPage + 1,
                        uiModel.totalPages
                    )
                )
                .padding(8.0)
                .background(Color.gray.opacity(0.7))
                .cornerRadius(8.0)
                .padding(8.0)
            }
            .onAppear {
                viewModel.startPageSaveTimer()
            }
            .onDisappear {
                viewModel.stopPageSaveTimer()
                viewModel.saveCurrentPage()
            }
        }
    }
    
    init() {
        _viewModel = StateObject(wrappedValue: PDFReaderViewModel())
    }
}
