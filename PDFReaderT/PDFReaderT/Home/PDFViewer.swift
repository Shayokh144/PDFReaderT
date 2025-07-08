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
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
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
        }
    }
}
