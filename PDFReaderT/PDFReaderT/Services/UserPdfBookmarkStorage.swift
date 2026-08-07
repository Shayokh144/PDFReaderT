//
//  UserPdfBookmarkStorage.swift
//  PDFReaderT
//

import Foundation
import OSLog

private let log = AppLog.storage

/// Persists at most one bookmark per document so it survives app restarts.
protocol UserPdfBookmarkStoring: AnyObject {
    func getBookmark(documentId: String) -> PdfBookmark?
    /// Replaces any existing bookmark for `bookmark.documentId`.
    func setBookmark(_ bookmark: PdfBookmark)
    func clearBookmark(documentId: String)
}

final class UserDefaultsPdfBookmarkStore: UserPdfBookmarkStoring {
    private let key = "user_pdf_bookmarks_by_document_v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cachedMap: [String: StoredBookmark]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func getBookmark(documentId: String) -> PdfBookmark? {
        guard !documentId.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let stored = ensureMapLoaded()[documentId], stored.page >= 0 else {
            return nil
        }
        return PdfBookmark(
            documentId: documentId,
            pageIndex: stored.page,
            x: stored.x,
            y: stored.y
        )
    }

    func setBookmark(_ bookmark: PdfBookmark) {
        guard !bookmark.documentId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var map = ensureMapLoaded()
        map[bookmark.documentId] = StoredBookmark(
            page: bookmark.pageIndex,
            x: bookmark.x,
            y: bookmark.y
        )
        cachedMap = map
        saveMap(map)
    }

    func clearBookmark(documentId: String) {
        guard !documentId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var map = ensureMapLoaded()
        guard map.removeValue(forKey: documentId) != nil else { return }
        cachedMap = map
        saveMap(map)
    }

    private func ensureMapLoaded() -> [String: StoredBookmark] {
        if let cachedMap {
            return cachedMap
        }
        let loaded = loadMapFromDisk()
        cachedMap = loaded
        return loaded
    }

    private func loadMapFromDisk() -> [String: StoredBookmark] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: StoredBookmark].self, from: data)
        } catch {
            log.error("Failed to decode PDF bookmarks: \(error.localizedDescription)")
            return [:]
        }
    }

    private func saveMap(_ map: [String: StoredBookmark]) {
        do {
            let data = try JSONEncoder().encode(map)
            defaults.set(data, forKey: key)
        } catch {
            log.error("Failed to save PDF bookmarks: \(error.localizedDescription)")
        }
    }
}

private struct StoredBookmark: Codable {
    let page: Int
    let x: Double
    let y: Double
}
