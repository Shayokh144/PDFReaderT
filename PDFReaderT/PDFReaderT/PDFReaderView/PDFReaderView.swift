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
        NavigationStack {
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height
                
                Group {
                    if uiModel.selectedPDFURL != nil {
                        pdfDocumentView(uiModel: uiModel)
                    } else {
                        emptyStateView(uiModel: uiModel, isLandscape: isLandscape)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaInset(edge: .bottom) {
                    if uiModel.selectedPDFURL == nil {
                        selectPDFButton(isLandscape: isLandscape)
                    }
                }
            }
            .navigationTitle(String(localized: "pdf_reader.navigation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if uiModel.selectedPDFURL != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "pdf_reader.close")) {
                            viewModel.closePDFReader()
                        }
                        .disabled(uiModel.isSavingBeforeClose)
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
    private func emptyStateView(uiModel: PDFReaderViewUIModel, isLandscape: Bool) -> some View {
        Group {
            if isLandscape && !uiModel.recentFiles.isEmpty {
                HStack(alignment: .top, spacing: 24) {
                    emptyStateCard()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    recentFilesSection(uiModel: uiModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                VStack(spacing: 24) {
                    emptyStateCard()
                    if !uiModel.recentFiles.isEmpty {
                        recentFilesSection(uiModel: uiModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLandscape ? .center : .top)
    }
    
    private func emptyStateCard() -> some View {
        ContentUnavailableView(
            String(localized: "pdf_reader.empty_title"),
            systemImage: "doc.text",
            description: Text("pdf_reader.empty_description")
        )
        .frame(maxWidth: .infinity)
    }
    
    private func recentFilesSection(uiModel: PDFReaderViewUIModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("pdf_reader.recent_files")
                .font(.headline)
            
            List {
                ForEach(uiModel.recentFiles) { file in
                    RecentFileRow(file: file) {
                        viewModel.openRecentFile(file)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 4.0)
                }
                .onDelete(perform: viewModel.deleteFile)
            }
            .listStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func selectPDFButton(isLandscape: Bool) -> some View {
        Button {
            viewModel.showingDocumentPicker = true
        } label: {
            Text(String(localized: "pdf_reader.select_pdf"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(height: 44.0)
                .frame(maxWidth: isLandscape ? 360.0 : .infinity)
                .background(Color.green)
                .cornerRadius(8.0)
        }
        .contentShape(Rectangle())
        .padding()
    }
    
    @ViewBuilder
    private func pdfDocumentView(uiModel: PDFReaderViewUIModel) -> some View {
        if let url = uiModel.selectedPDFURL {
            PDFViewer(
                url: url,
                initialPage: uiModel.initialPage,
                currentPage: $viewModel.currentPage,
                onReadOnlyPDF: {
                    viewModel.presentOKOnlyAlert(
                        titleKey: "pdf_reader.read_only_alert_title",
                        messageKey: "pdf_reader.read_only_alert_message"
                    )
                },
                onSaveFailed: {
                    viewModel.presentOKOnlyAlert(
                        titleKey: "pdf_reader.save_annotations_error_title",
                        messageKey: "pdf_reader.save_annotations_error_message"
                    )
                },
                onSaveFlusherReady: { flusher in
                    viewModel.saveFlusher = flusher
                }
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
            .overlay {
                if uiModel.isSavingBeforeClose {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView {
                                Text("pdf_reader.saving")
                            }
                            .controlSize(.regular)
                            .tint(.white)
                            .foregroundStyle(.white)
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }
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
