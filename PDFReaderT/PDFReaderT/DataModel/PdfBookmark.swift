//
//  PdfBookmark.swift
//  PDFReaderT
//

import Foundation

/// Single in-document reading bookmark. Coordinates are in PDF page space
/// (origin at bottom-left of the page), matching PDFKit.
struct PdfBookmark: Equatable {
    let documentId: String
    let pageIndex: Int
    let x: Double
    let y: Double
}
