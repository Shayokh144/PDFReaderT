//
//  InsightsCard.swift
//  PDFReaderT
//

import SwiftUI

/// Compact weekly insights card for the home screen (Task 2).
/// Sits below the Task 1 ReadingStatsCard.
struct InsightsCard: View {
    let dailyStats: [DailyReadingStats]
    let sessions: [ReadingSession]

    private var thisWeekStart: Date {
        InsightsCalculator.startOfWeek(containing: Date())
    }

    private var lastWeekStart: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
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

    private var hasData: Bool {
        !dailyStats.isEmpty
    }

    var body: some View {
        if hasData {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("insights.card_title")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 0) {
                    weekTimeItem
                    Spacer()
                    trendItem
                    Spacer()
                    streakItem
                    Spacer()
                    topBookItem
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    private var weekTimeItem: some View {
        VStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.caption)
                .foregroundColor(.orange)
            Text(InsightsCalculator.formattedMinutes(thisWeek.totalMinutes))
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(String(localized: "insights.this_week"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var trendItem: some View {
        let pct = InsightsCalculator.percentChange(thisWeek: thisWeek.totalMinutes, lastWeek: lastWeek.totalMinutes)
        return VStack(spacing: 4) {
            Image(systemName: trendIcon(pct))
                .font(.caption)
                .foregroundColor(trendColor(pct))
            Text(trendText(pct))
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(trendColor(pct))
            Text(String(localized: "insights.vs_last_week"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var streakItem: some View {
        VStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.caption)
                .foregroundColor(.orange)
            Text("\(streak)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(String(localized: "insights.day_streak"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var topBookItem: some View {
        VStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.caption)
                .foregroundColor(.yellow)
            Text(thisWeek.topBookName.map { truncate($0, to: 8) } ?? "—")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(String(localized: "insights.top_book"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func trendIcon(_ pct: Double?) -> String {
        guard let pct else { return "minus" }
        return pct >= 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private func trendColor(_ pct: Double?) -> Color {
        guard let pct else { return .secondary }
        return pct >= 0 ? .green : .red
    }

    private func trendText(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(Int(pct.rounded()))%"
    }

    private func truncate(_ str: String, to max: Int) -> String {
        if str.count <= max { return str }
        return String(str.prefix(max)) + "…"
    }
}
