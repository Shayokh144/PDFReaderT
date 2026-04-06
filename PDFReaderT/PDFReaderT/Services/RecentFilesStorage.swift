//
//  RecentFilesStorage.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import Foundation
import OSLog

private let log = AppLog.storage

enum RecentFilesLoadResult {
    case noStoredData
    case loaded([RecentFile])
    case decodeFailed(Error)
}

protocol RecentFilesStoring {
    func loadRecentFiles() -> RecentFilesLoadResult
    func saveRecentFiles(_ files: [RecentFile])
}

final class UserDefaultsRecentFilesStore: RecentFilesStoring {
    private let key = "RecentPDFFiles"

    func loadRecentFiles() -> RecentFilesLoadResult {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return .noStoredData
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let files = try decoder.decode([RecentFile].self, from: data)
            return .loaded(files)
        } catch {
            return .decodeFailed(error)
        }
    }

    func saveRecentFiles(_ files: [RecentFile]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(files)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            log.error("Error saving recent files: \(error.localizedDescription)")
        }
    }
}
