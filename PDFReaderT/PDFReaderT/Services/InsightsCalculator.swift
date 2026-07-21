//
//  InsightsCalculator.swift
//  PDFReaderT
//

import Foundation

/// Pure computation helper for reading insights. No storage, no side effects.
enum InsightsCalculator {

    struct WeeklySummary {
        let totalMinutes: Double
        let dailyBreakdown: [DayMinutes]
        let dailyAverage: Double
        let topBookName: String?
        let topBookMinutes: Double
    }

    struct DayMinutes: Identifiable {
        let id: String
        let label: String
        let minutes: Double
    }

    // MARK: - Week helpers (Mon–Sun)

    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    static func weekDates(startingMonday monday: Date, calendar: Calendar = .current) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    // MARK: - Weekly summary

    static func weeklySummary(
        for weekStart: Date,
        dailyStats: [DailyReadingStats],
        sessions: [ReadingSession],
        calendar: Calendar = .current
    ) -> WeeklySummary {
        let dates = weekDates(startingMonday: weekStart, calendar: calendar)
        let dateStrings = Set(dates.map { DailyReadingStats.dateString(for: $0) })
        let weekStats = dailyStats.filter { dateStrings.contains($0.dateString) }

        let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dailyBreakdown: [DayMinutes] = dates.enumerated().map { i, date in
            let ds = DailyReadingStats.dateString(for: date)
            let mins = weekStats.first(where: { $0.dateString == ds })?.minutesRead ?? 0
            return DayMinutes(id: ds, label: dayLabels[i], minutes: mins)
        }

        let totalMinutes = weekStats.reduce(0.0) { $0 + $1.minutesRead }
        let daysWithData = dailyBreakdown.filter { $0.minutes > 0 }.count
        let dailyAverage = daysWithData > 0 ? totalMinutes / Double(daysWithData) : 0

        // Top book this week from sessions
        let weekSessions = sessions.filter {
            let ds = DailyReadingStats.dateString(for: $0.startTime)
            return dateStrings.contains(ds)
        }
        let byBook = Dictionary(grouping: weekSessions, by: \.documentName)
        let topEntry = byBook.max(by: {
            $0.value.reduce(0) { $0 + $1.durationSeconds } < $1.value.reduce(0) { $0 + $1.durationSeconds }
        })
        let topBookMinutes = (topEntry?.value.reduce(0) { $0 + $1.durationSeconds } ?? 0) / 60.0

        return WeeklySummary(
            totalMinutes: totalMinutes,
            dailyBreakdown: dailyBreakdown,
            dailyAverage: dailyAverage,
            topBookName: topEntry?.key,
            topBookMinutes: topBookMinutes
        )
    }

    // MARK: - Streak

    /// Consecutive days (ending today or yesterday) with ≥ 1 minute of reading.
    static func currentStreak(
        dailyStats: [DailyReadingStats],
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: Date())
        let qualifyingDates = Set(
            dailyStats
                .filter { $0.minutesRead >= 1 }
                .compactMap { DailyReadingStats.date(from: $0.dateString) }
                .map { calendar.startOfDay(for: $0) }
        )

        var streak = 0
        var checkDate = today

        // Allow streak to start from today or yesterday
        if !qualifyingDates.contains(checkDate) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            checkDate = yesterday
        }

        while qualifyingDates.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }

    // MARK: - Percent change

    static func percentChange(thisWeek: Double, lastWeek: Double) -> Double? {
        guard lastWeek > 0 else { return nil }
        return ((thisWeek - lastWeek) / lastWeek) * 100
    }

    // MARK: - Formatting

    static func formattedMinutes(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        if h > 0 {
            return String(format: NSLocalizedString("reading_stats.time_hm_format", comment: ""), h, m)
        }
        return String(format: NSLocalizedString("reading_stats.time_m_format", comment: ""), m)
    }
}
