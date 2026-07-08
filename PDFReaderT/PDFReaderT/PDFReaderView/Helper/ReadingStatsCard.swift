//
//  ReadingStatsCard.swift
//  PDFReaderT
//

import SwiftUI

struct ReadingStatsCard: View {
    let recentFiles: [RecentFile]

    private var totalReadingSeconds: TimeInterval {
        recentFiles.reduce(0) { $0 + $1.readingTimeSeconds }
    }

    private var totalPagesRead: Int {
        recentFiles.reduce(0) { $0 + min($1.lastPageNumber + 1, $1.totalPages) }
    }

    private var booksCount: Int { recentFiles.count }

    private var finishedCount: Int {
        recentFiles.filter { file in
            guard file.totalPages > 0 else { return false }
            let pct = Int((Double(file.lastPageNumber + 1) / Double(file.totalPages)) * 100)
            return pct >= 95
        }.count
    }

    private var hasData: Bool {
        recentFiles.contains { $0.readingTimeSeconds > 0 }
    }

    var body: some View {
        if hasData {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.green)
                    Text("reading_stats.title")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 0) {
                    statItem(
                        icon: "clock.fill",
                        value: formattedTotalTime(totalReadingSeconds),
                        label: String(localized: "reading_stats.total_time")
                    )
                    Spacer()
                    statItem(
                        icon: "book.fill",
                        value: "\(booksCount)",
                        label: String(localized: "reading_stats.books_opened")
                    )
                    Spacer()
                    statItem(
                        icon: "doc.plaintext",
                        value: "\(totalPagesRead)",
                        label: String(localized: "reading_stats.pages_read")
                    )
                    Spacer()
                    statItem(
                        icon: "checkmark.circle.fill",
                        value: "\(finishedCount)",
                        label: String(localized: "reading_stats.finished")
                    )
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedTotalTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 {
            return String(format: String(localized: "reading_stats.time_hm_format"), h, m)
        }
        return String(format: String(localized: "reading_stats.time_m_format"), m)
    }
}
