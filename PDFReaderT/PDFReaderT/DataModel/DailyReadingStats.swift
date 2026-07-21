//
//  DailyReadingStats.swift
//  PDFReaderT
//

import Foundation

struct DailyReadingStats: Codable, Identifiable {
    var id: String { dateString }

    /// Calendar day in "yyyy-MM-dd" format.
    let dateString: String
    var minutesRead: Double
    var pagesRead: Int
    /// UUIDs of documents opened that day (for unique count).
    var documentIds: [UUID]

    var documentsOpened: Int { Set(documentIds).count }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func todayString() -> String {
        dateFormatter.string(from: Date())
    }

    static func dateString(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        dateFormatter.date(from: string)
    }
}
