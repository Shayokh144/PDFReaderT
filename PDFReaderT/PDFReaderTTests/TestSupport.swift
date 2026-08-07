//
//  TestSupport.swift
//  PDFReaderTTests
//

import Foundation
import PDFKit
import UIKit
@testable import PDFReaderT

// MARK: - Mocks

final class MockRecentFilesStore: RecentFilesStoring {
    var loadResult: RecentFilesLoadResult = .noStoredData
    var savedFiles: [[RecentFile]] = []

    func loadRecentFiles() -> RecentFilesLoadResult {
        loadResult
    }

    func saveRecentFiles(_ files: [RecentFile]) {
        savedFiles.append(files)
    }
}

final class InMemoryInsightsStorage: ReadingInsightsStoring {
    var sessions: [ReadingSession] = []
    var dailyStats: [DailyReadingStats] = []

    func loadSessions() -> [ReadingSession] { sessions }
    func saveSessions(_ sessions: [ReadingSession]) { self.sessions = sessions }
    func appendSession(_ session: ReadingSession) { sessions.append(session) }
    func loadDailyStats() -> [DailyReadingStats] { dailyStats }
    func saveDailyStats(_ stats: [DailyReadingStats]) { dailyStats = stats }
    func recordSessionInDailyStats(_ session: ReadingSession) {
        let today = DailyReadingStats.todayString()
        if let idx = dailyStats.firstIndex(where: { $0.dateString == today }) {
            dailyStats[idx].minutesRead += session.durationSeconds / 60.0
            dailyStats[idx].pagesRead += session.pagesRead
            if !dailyStats[idx].documentIds.contains(session.documentId) {
                dailyStats[idx].documentIds.append(session.documentId)
            }
        } else {
            dailyStats.append(
                DailyReadingStats(
                    dateString: today,
                    minutesRead: session.durationSeconds / 60.0,
                    pagesRead: session.pagesRead,
                    documentIds: [session.documentId]
                )
            )
        }
    }
}

// MARK: - PDF helpers

enum TestPDFFactory {
    /// Creates a multi-page searchable PDF in a unique temp directory.
    static func makePDF(
        pages: [(title: String, body: String)] = [
            ("Page One", "UniqueNeedleAlpha appears here for search."),
            ("Page Two", "UniqueNeedleBeta appears on the second page."),
        ]
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("sample.pdf")

        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        try renderer.writePDF(to: url) { context in
            for page in pages {
                context.beginPage()
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 18),
                ]
                let bodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                ]
                page.title.draw(at: CGPoint(x: 72, y: 72), withAttributes: titleAttrs)
                // Long body so snippet truncation / ellipsis branches can trigger.
                let padded = String(repeating: "prefix-word ", count: 8) + page.body + String(repeating: " suffix-word", count: 8)
                padded.draw(in: CGRect(x: 72, y: 110, width: 468, height: 600), withAttributes: bodyAttrs)
            }
        }
        return url
    }

    static func makeRecentFile(
        from url: URL,
        lastPage: Int = 0,
        readingTime: TimeInterval = 0
    ) throws -> RecentFile {
        guard let bookmark = url.bookmarkData() else {
            throw NSError(domain: "TestPDFFactory", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not create bookmark for test PDF",
            ])
        }
        let pageCount = PDFDocument(url: url)?.pageCount ?? 1
        return RecentFile(
            id: UUID(),
            name: url.lastPathComponent,
            bookmarkData: bookmark,
            dateAdded: Date(),
            fileSize: "1 KB",
            lastPageNumber: lastPage,
            totalPages: pageCount,
            readingTimeSeconds: readingTime
        )
    }
}
