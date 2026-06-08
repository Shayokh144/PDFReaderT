//
//  PDFSearchResult.swift
//  PDFReaderT
//

import PDFKit

struct PDFSearchResult: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let snippet: String
    let matchIndex: Int
    let selection: PDFSelection
}

struct SearchNavigationRequest: Equatable {
    let searchText: String
    let matchIndex: Int
    
    static func == (lhs: SearchNavigationRequest, rhs: SearchNavigationRequest) -> Bool {
        lhs.searchText == rhs.searchText && lhs.matchIndex == rhs.matchIndex
    }
}
