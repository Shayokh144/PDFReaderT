//
//  ReadingInsightsStorage.swift
//  PDFReaderT
//

import Foundation
import OSLog

private let log = AppLog.storage

/// Persists reading sessions and daily aggregates as JSON files in Application Support.
/// Prunes sessions older than 30 days and daily stats older than 90 days on load.
final class ReadingInsightsStorage {

    private let sessionsFileURL: URL
    private let dailyStatsFileURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ReadingInsights", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sessionsFileURL = dir.appendingPathComponent("sessions.json")
        dailyStatsFileURL = dir.appendingPathComponent("daily_stats.json")
    }

    // MARK: - Sessions

    func loadSessions() -> [ReadingSession] {
        guard let data = try? Data(contentsOf: sessionsFileURL) else { return [] }
        do {
            let sessions = try decoder.decode([ReadingSession].self, from: data)
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return sessions.filter { $0.startTime >= cutoff }
        } catch {
            log.error("Failed to decode sessions: \(error.localizedDescription)")
            return []
        }
    }

    func saveSessions(_ sessions: [ReadingSession]) {
        do {
            let data = try encoder.encode(sessions)
            try data.write(to: sessionsFileURL, options: .atomic)
        } catch {
            log.error("Failed to save sessions: \(error.localizedDescription)")
        }
    }

    func appendSession(_ session: ReadingSession) {
        var sessions = loadSessions()
        sessions.append(session)
        saveSessions(sessions)
    }

    // MARK: - Daily Stats

    func loadDailyStats() -> [DailyReadingStats] {
        guard let data = try? Data(contentsOf: dailyStatsFileURL) else { return [] }
        do {
            let stats = try decoder.decode([DailyReadingStats].self, from: data)
            let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
            let cutoffString = DailyReadingStats.dateString(for: cutoff)
            return stats.filter { $0.dateString >= cutoffString }
        } catch {
            log.error("Failed to decode daily stats: \(error.localizedDescription)")
            return []
        }
    }

    func saveDailyStats(_ stats: [DailyReadingStats]) {
        do {
            let data = try encoder.encode(stats)
            try data.write(to: dailyStatsFileURL, options: .atomic)
        } catch {
            log.error("Failed to save daily stats: \(error.localizedDescription)")
        }
    }

    /// Merges a completed session into today's daily aggregate.
    func recordSessionInDailyStats(_ session: ReadingSession) {
        var stats = loadDailyStats()
        let today = DailyReadingStats.todayString()

        if let idx = stats.firstIndex(where: { $0.dateString == today }) {
            stats[idx].minutesRead += session.durationSeconds / 60.0
            stats[idx].pagesRead += session.pagesRead
            if !stats[idx].documentIds.contains(session.documentId) {
                stats[idx].documentIds.append(session.documentId)
            }
        } else {
            let newDay = DailyReadingStats(
                dateString: today,
                minutesRead: session.durationSeconds / 60.0,
                pagesRead: session.pagesRead,
                documentIds: [session.documentId]
            )
            stats.append(newDay)
        }

        saveDailyStats(stats)
    }
}
