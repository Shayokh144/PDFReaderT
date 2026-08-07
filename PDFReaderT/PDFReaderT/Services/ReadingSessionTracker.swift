//
//  ReadingSessionTracker.swift
//  PDFReaderT
//

import Foundation
import OSLog

private let log = AppLog.viewModel

/// Tracks per-session reading data with idle detection.
/// Runs in parallel with the existing cumulative `readingTimeSeconds` on `RecentFile`.
@MainActor
final class ReadingSessionTracker {

    private let storage: ReadingInsightsStorage

    // Active session state
    private var sessionId: UUID?
    private var documentId: UUID?
    private var documentName: String?
    private var startPage: Int = 0
    private var latestPage: Int = 0
    private var sessionStartTime: Date?
    /// False until the first real user interaction (tap/scroll/pinch).
    /// Programmatic page changes (document load + restore-to-last-page) update
    /// `startPage` while unlocked so restore is not counted as pages read.
    private var startPageLocked = false

    // Idle detection: track active segments so idle gaps are excluded
    private var activeSegmentStart: Date?
    private var accumulatedActiveSeconds: TimeInterval = 0
    private var isIdle = false
    private var idleTimer: Timer?

    static let idleTimeout: TimeInterval = 60

    /// Called after a session is recorded. The ViewModel uses this to refresh UI.
    var onSessionRecorded: (() -> Void)?

    init(storage: ReadingInsightsStorage = ReadingInsightsStorage()) {
        self.storage = storage
    }

    var hasActiveSession: Bool { sessionId != nil }

    // MARK: - Session lifecycle

    func startSession(documentId: UUID, documentName: String, page: Int) {
        guard sessionId == nil else { return }
        let now = Date()
        sessionId = UUID()
        self.documentId = documentId
        self.documentName = documentName
        startPage = page
        latestPage = page
        sessionStartTime = now
        activeSegmentStart = now
        accumulatedActiveSeconds = 0
        isIdle = false
        startPageLocked = false
        startIdleTimer()
        log.debug("\(AppLog.scopePrefix(for: Self.self)) session started for \(documentName) at page \(page)")
    }

    /// Ends the session, persists it, and updates daily stats.
    func endSession(currentPage: Int) {
        guard let sid = sessionId,
              let did = documentId,
              let dname = documentName,
              let sStart = sessionStartTime else { return }

        latestPage = currentPage
        finalizeActiveSegment()

        let session = ReadingSession(
            id: sid,
            documentId: did,
            documentName: dname,
            startTime: sStart,
            endTime: Date(),
            startPage: startPage,
            endPage: latestPage,
            durationSeconds: accumulatedActiveSeconds
        )

        stopIdleTimer()
        resetState()

        guard session.durationSeconds >= 1 else {
            log.debug("\(AppLog.scopePrefix(for: Self.self)) session too short, discarding")
            return
        }

        storage.appendSession(session)
        storage.recordSessionInDailyStats(session)
        onSessionRecorded?()
        log.debug("\(AppLog.scopePrefix(for: Self.self)) session ended: \(session.durationSeconds, privacy: .public)s active, pages \(session.startPage)->\(session.endPage)")
    }

    /// Pause for app background — commits the active segment but keeps state so we can resume.
    func pauseForBackground(currentPage: Int) {
        guard sessionId != nil else { return }
        latestPage = currentPage
        finalizeActiveSegment()
        stopIdleTimer()
        log.debug("\(AppLog.scopePrefix(for: Self.self)) session paused for background")
    }

    /// Resume after returning to foreground.
    func resumeFromForeground() {
        guard sessionId != nil else { return }
        activeSegmentStart = Date()
        isIdle = false
        startIdleTimer()
        log.debug("\(AppLog.scopePrefix(for: Self.self)) session resumed from foreground")
    }

    /// Call when the visible page changes, including programmatic navigation
    /// (document load, restore-to-last-page, search jump). Does not lock startPage.
    func onPageChanged(currentPage: Int) {
        guard sessionId != nil else { return }
        latestPage = currentPage
        if !startPageLocked {
            // Follow restore/load until the user actually interacts.
            startPage = currentPage
            return
        }

        // After lock, page turns count as activity for idle detection.
        if isIdle {
            activeSegmentStart = Date()
            isIdle = false
            log.debug("\(AppLog.scopePrefix(for: Self.self)) resumed from idle at page \(currentPage)")
        }
        resetIdleTimer()
    }

    /// Call on real user interaction (tap, scroll, pinch). Locks startPage and
    /// resets the idle timer / resumes tracking if the session was idle.
    func onUserInteraction(currentPage: Int) {
        guard sessionId != nil else { return }

        if !startPageLocked {
            startPage = currentPage
            startPageLocked = true
            log.debug("\(AppLog.scopePrefix(for: Self.self)) locked startPage to \(currentPage)")
        }

        latestPage = currentPage

        if isIdle {
            activeSegmentStart = Date()
            isIdle = false
            log.debug("\(AppLog.scopePrefix(for: Self.self)) resumed from idle at page \(currentPage)")
        }

        resetIdleTimer()
    }

    // MARK: - Idle timer

    private func startIdleTimer() {
        stopIdleTimer()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleIdleTimeout()
            }
        }
    }

    private func resetIdleTimer() {
        startIdleTimer()
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func handleIdleTimeout() {
        guard sessionId != nil, !isIdle else { return }
        finalizeActiveSegment()
        isIdle = true
        log.debug("\(AppLog.scopePrefix(for: Self.self)) idle timeout — paused active tracking")
    }

    // MARK: - Helpers

    /// Adds the current active segment's duration to the accumulator.
    private func finalizeActiveSegment() {
        guard let start = activeSegmentStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed > 0 {
            accumulatedActiveSeconds += elapsed
        }
        activeSegmentStart = nil
    }

    private func resetState() {
        sessionId = nil
        documentId = nil
        documentName = nil
        startPage = 0
        latestPage = 0
        sessionStartTime = nil
        activeSegmentStart = nil
        accumulatedActiveSeconds = 0
        isIdle = false
        startPageLocked = false
    }
}
