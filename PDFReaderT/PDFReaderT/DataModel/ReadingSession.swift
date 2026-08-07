//
//  ReadingSession.swift
//  PDFReaderT
//

import Foundation

struct ReadingSession: Codable, Identifiable {
    let id: UUID
    let documentId: UUID
    let documentName: String
    let startTime: Date
    var endTime: Date
    let startPage: Int
    var endPage: Int
    /// Active reading time excluding idle gaps (seconds).
    var durationSeconds: TimeInterval

    /// Pages advanced during this session (forward progress only).
    var pagesRead: Int {
        max(0, endPage - startPage)
    }
}
