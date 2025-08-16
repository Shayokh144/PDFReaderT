//
//  PDFViewer.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import PDFKit
import SwiftUI

struct PDFViewer: UIViewRepresentable {
    let url: URL
    let initialPage: Int?
    @Binding var currentPage: Int
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        // Set up page change notification
        NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { _ in
            if let currentPDFPage = pdfView.currentPage,
               let document = pdfView.document {
                let pageIndex = document.index(for: currentPDFPage)
                DispatchQueue.main.async {
                    self.currentPage = pageIndex
                }
            }
        }
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Only update if the document is not already loaded
        if pdfView.document == nil {
            loadDocument(into: pdfView)
        }
    }
    
    private func loadDocument(into pdfView: PDFView) {
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access security-scoped resource")
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            
            // Navigate to the initial page if specified
            if let initialPage = initialPage,
               initialPage < document.pageCount,
               let page = document.page(at: initialPage) {
                
                // Add a slight delay to ensure the document is fully loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pdfView.go(to: page)
                }
            }
        }
    }
}
