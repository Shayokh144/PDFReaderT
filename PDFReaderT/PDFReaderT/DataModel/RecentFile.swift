//
//  Untitled.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import Foundation

struct RecentFile: Codable, Identifiable {

    let id: UUID
    let name: String
    let bookmarkData: Data
    let dateAdded: Date
    let fileSize: String
    var lastPageNumber: Int
    var totalPages: Int
}
