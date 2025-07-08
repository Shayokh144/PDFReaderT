//
//  HomeScreen.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import SwiftUI

struct HomeScreen: View {
    
    @State private var selectedPDFURL: URL?
    @State private var showingDocumentPicker = false
    
    var body: some View {
        NavigationView {
            VStack {
                if let pdfURL = selectedPDFURL {
                    PDFViewer(url: pdfURL)
                } else {
                    ContentUnavailableView(
                        "No PDF Selected",
                        systemImage: "doc.text",
                        description: Text("Tap the button below to select a PDF file")
                    )
                }
                
                Button("Select PDF") {
                    showingDocumentPicker = true
                }
                .padding()
            }
            .navigationTitle("PDF Reader")
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(selectedURL: $selectedPDFURL, isPresented: $showingDocumentPicker)
            }
        }
    }
}
