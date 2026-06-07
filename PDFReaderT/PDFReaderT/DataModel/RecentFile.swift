//
//  Untitled.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import Foundation

struct RecentFile: Codable, Identifiable {

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bookmarkData
        case dateAdded
        case fileSize
        case lastPageNumber
        case totalPages
        case readingTimeSeconds
    }

    let id: UUID
    let name: String
    let bookmarkData: Data
    let dateAdded: Date
    let fileSize: String
    var lastPageNumber: Int
    var totalPages: Int
    /// Cumulative time the PDF was open in the reader while the app was in the foreground (seconds).
    var readingTimeSeconds: TimeInterval

    init(
        id: UUID,
        name: String,
        bookmarkData: Data,
        dateAdded: Date,
        fileSize: String,
        lastPageNumber: Int,
        totalPages: Int,
        readingTimeSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.dateAdded = dateAdded
        self.fileSize = fileSize
        self.lastPageNumber = lastPageNumber
        self.totalPages = totalPages
        self.readingTimeSeconds = readingTimeSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bookmarkData = try container.decode(Data.self, forKey: .bookmarkData)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        fileSize = try container.decode(String.self, forKey: .fileSize)
        lastPageNumber = try container.decode(Int.self, forKey: .lastPageNumber)
        totalPages = try container.decode(Int.self, forKey: .totalPages)
        readingTimeSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .readingTimeSeconds) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(bookmarkData, forKey: .bookmarkData)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(lastPageNumber, forKey: .lastPageNumber)
        try container.encode(totalPages, forKey: .totalPages)
        try container.encode(readingTimeSeconds, forKey: .readingTimeSeconds)
    }
}
