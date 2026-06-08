//
//  PDFSearchSheet.swift
//  PDFReaderT
//

import SwiftUI

struct PDFSearchSheet: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                resultsList
            }
            .navigationTitle(String(localized: "pdf_reader.search_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "pdf_reader.close")) {
                        viewModel.isSearching = false
                    }
                }
            }
        }
    }
    
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "pdf_reader.search_placeholder"),
                text: $viewModel.searchText
            )
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.performSearch()
            }
            
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    viewModel.performSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
    }
    
    private var resultsList: some View {
        Group {
            if viewModel.searchResults.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView(
                    String(localized: "pdf_reader.search_no_results"),
                    systemImage: "magnifyingglass"
                )
            } else {
                List(viewModel.searchResults) { result in
                    Button {
                        viewModel.selectSearchResult(result)
                    } label: {
                        searchResultRow(result)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func searchResultRow(_ result: PDFSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                String(
                    format: String(localized: "pdf_reader.search_result_page"),
                    result.pageIndex + 1
                )
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            
            Text(highlightedSnippet(result.snippet))
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }
    
    private func highlightedSnippet(_ snippet: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return attributed }
        
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let range = attributed[searchRange].range(of: query, options: .caseInsensitive) {
            attributed[range].font = .subheadline.bold()
            attributed[range].foregroundColor = .accentColor
            searchRange = range.upperBound..<attributed.endIndex
        }
        
        return attributed
    }
}
