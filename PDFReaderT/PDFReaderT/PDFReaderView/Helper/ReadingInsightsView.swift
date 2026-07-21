//
//  ReadingInsightsView.swift
//  PDFReaderT
//

import SwiftUI

/// Full Reading Insights screen (Task 2).
struct ReadingInsightsView: View {
    let dailyStats: [DailyReadingStats]
    let sessions: [ReadingSession]

    @Environment(\.dismiss) private var dismiss

    private var calendar: Calendar { .current }

    private var thisWeekStart: Date {
        InsightsCalculator.startOfWeek(containing: Date())
    }
    private var lastWeekStart: Date {
        calendar.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
    }
    private var thisWeek: InsightsCalculator.WeeklySummary {
        InsightsCalculator.weeklySummary(for: thisWeekStart, dailyStats: dailyStats, sessions: sessions)
    }
    private var lastWeek: InsightsCalculator.WeeklySummary {
        InsightsCalculator.weeklySummary(for: lastWeekStart, dailyStats: dailyStats, sessions: sessions)
    }
    private var streak: Int {
        InsightsCalculator.currentStreak(dailyStats: dailyStats)
    }
    private var percentChange: Double? {
        InsightsCalculator.percentChange(thisWeek: thisWeek.totalMinutes, lastWeek: lastWeek.totalMinutes)
    }

    var body: some View {
        NavigationStack {
            List {
                weekComparisonSection
                barChartSection
                streakAndAverageSection
                if thisWeek.topBookName != nil {
                    topBookSection
                }
                booksThisWeekSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "insights.screen_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "pdf_reader.close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Week comparison

    private var weekComparisonSection: some View {
        Section {
            HStack(spacing: 16) {
                weekCard(
                    title: String(localized: "insights.this_week"),
                    minutes: thisWeek.totalMinutes,
                    highlight: true
                )
                weekCard(
                    title: String(localized: "insights.last_week"),
                    minutes: lastWeek.totalMinutes,
                    highlight: false
                )
            }
            .padding(.vertical, 4)

            if let pct = percentChange {
                HStack {
                    Image(systemName: pct >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .foregroundColor(pct >= 0 ? .green : .red)
                    Text(trendDescription(pct))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("insights.weekly_comparison")
        }
    }

    private func weekCard(title: String, minutes: Double, highlight: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(InsightsCalculator.formattedMinutes(minutes))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(highlight ? .green : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(highlight ? Color.green.opacity(0.08) : Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Bar chart

    private var barChartSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                let maxMinutes = thisWeek.dailyBreakdown.map(\.minutes).max() ?? 1

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(thisWeek.dailyBreakdown) { day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(barColor(for: day))
                                .frame(height: barHeight(minutes: day.minutes, max: maxMinutes))
                                .frame(maxWidth: .infinity)

                            Text(day.label)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(height: 140)
                .padding(.top, 8)
            }
        } header: {
            Text("insights.daily_breakdown")
        }
    }

    private func barHeight(minutes: Double, max: Double) -> CGFloat {
        guard max > 0, minutes > 0 else { return 4 }
        return CGFloat(minutes / max) * 120 + 4
    }

    private func barColor(for day: InsightsCalculator.DayMinutes) -> Color {
        let today = DailyReadingStats.todayString()
        if day.id == today { return .green }
        return day.minutes > 0 ? .green.opacity(0.6) : Color(.systemGray4)
    }

    // MARK: - Streak & average

    private var streakAndAverageSection: some View {
        Section {
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text("\(streak)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(String(localized: "insights.day_streak"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 60)

                VStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text(InsightsCalculator.formattedMinutes(thisWeek.dailyAverage))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(String(localized: "insights.daily_average"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Top book

    private var topBookSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(thisWeek.topBookName ?? "")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    Text(InsightsCalculator.formattedMinutes(thisWeek.topBookMinutes))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            Text("insights.top_book_this_week")
        }
    }

    // MARK: - Per-book breakdown

    private var booksThisWeekSection: some View {
        Section {
            let weekDateStrings = weekDateStringsForThisWeek
            let weekSessions = sessions.filter {
                weekDateStrings.contains(DailyReadingStats.dateString(for: $0.startTime))
            }
            let byBook = Dictionary(grouping: weekSessions, by: \.documentName)
            let sorted = byBook.sorted {
                $0.value.reduce(0) { $0 + $1.durationSeconds } > $1.value.reduce(0) { $0 + $1.durationSeconds }
            }

            if sorted.isEmpty {
                Text("insights.no_sessions_this_week")
                    .foregroundColor(.secondary)
            } else {
                ForEach(sorted, id: \.key) { name, bookSessions in
                    let totalSec = bookSessions.reduce(0) { $0 + $1.durationSeconds }
                    let pages = bookSessions.reduce(0) { $0 + max(0, $1.endPage - $1.startPage) }
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Label(InsightsCalculator.formattedMinutes(totalSec / 60), systemImage: "clock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Label(
                                    String(
                                        format: String(localized: "insights.pages_count_format"),
                                        pages
                                    ),
                                    systemImage: "doc.plaintext"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(
                            String(
                                format: String(localized: "insights.sessions_count_format"),
                                bookSessions.count
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("insights.books_this_week")
        }
    }

    // MARK: - Helpers

    private var weekDateStringsForThisWeek: Set<String> {
        Set(InsightsCalculator.weekDates(startingMonday: thisWeekStart).map {
            DailyReadingStats.dateString(for: $0)
        })
    }

    private func trendDescription(_ pct: Double) -> String {
        let sign = pct >= 0 ? "+" : ""
        return String(
            format: String(localized: "insights.trend_description_format"),
            "\(sign)\(Int(pct.rounded()))%"
        )
    }
}
