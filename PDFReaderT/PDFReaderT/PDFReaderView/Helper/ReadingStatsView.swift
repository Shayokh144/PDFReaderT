//
//  ReadingStatsView.swift
//  PDFReaderT
//

import SwiftUI

struct ReadingStatsView: View {
    let recentFiles: [RecentFile]

    @Environment(\.dismiss) private var dismiss

    private var totalReadingSeconds: TimeInterval {
        recentFiles.reduce(0) { $0 + $1.readingTimeSeconds }
    }

    private var totalPagesRead: Int {
        recentFiles.reduce(0) { $0 + min($1.lastPageNumber + 1, $1.totalPages) }
    }

    private var totalPagesAll: Int {
        recentFiles.reduce(0) { $0 + $1.totalPages }
    }

    private var filesSortedByTime: [RecentFile] {
        recentFiles.sorted { $0.readingTimeSeconds > $1.readingTimeSeconds }
    }

    private var finishedCount: Int {
        recentFiles.filter { progressPercent(for: $0) >= 95 }.count
    }

    var body: some View {
        NavigationStack {
            List {
                libraryOverviewSection
                if let topBook = filesSortedByTime.first, topBook.readingTimeSeconds > 0 {
                    topBookSection(topBook)
                }
                booksBreakdownSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "reading_stats.screen_title"))
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

    // MARK: - Sections

    private var libraryOverviewSection: some View {
        Section {
            HStack(spacing: 0) {
                overviewItem(
                    icon: "book.fill",
                    value: "\(recentFiles.count)",
                    label: String(localized: "reading_stats.books_opened")
                )
                Spacer()
                overviewItem(
                    icon: "clock.fill",
                    value: formattedTotalTime(totalReadingSeconds),
                    label: String(localized: "reading_stats.total_time")
                )
                Spacer()
                overviewItem(
                    icon: "doc.plaintext",
                    value: "\(totalPagesRead)/\(totalPagesAll)",
                    label: String(localized: "reading_stats.pages_read")
                )
                Spacer()
                overviewItem(
                    icon: "checkmark.circle.fill",
                    value: String(
                        format: String(localized: "reading_stats.finished_of_total_format"),
                        finishedCount,
                        recentFiles.count
                    ),
                    label: String(localized: "reading_stats.completed")
                )
            }
            .padding(.vertical, 8)
        } header: {
            Text("reading_stats.library_overview")
        }
    }

    private func topBookSection(_ file: RecentFile) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(formattedTotalTime(file.readingTimeSeconds))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(
                    String(
                        format: String(localized: "pdf_reader.progress_percent_format"),
                        progressPercent(for: file)
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("reading_stats.top_book")
        }
    }

    private var booksBreakdownSection: some View {
        Section {
            ForEach(filesSortedByTime) { file in
                bookRow(file)
            }
        } header: {
            Text("reading_stats.all_books")
        }
    }

    // MARK: - Row

    private func bookRow(_ file: RecentFile) -> some View {
        let pct = progressPercent(for: file)
        let finished = pct >= 95

        return HStack(spacing: 12) {
            Image(systemName: finished ? "checkmark.circle.fill" : "doc.text.fill")
                .foregroundColor(finished ? .blue : .green)
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.name)
                        .font(.subheadline)
                        .lineLimit(1)

                    if finished {
                        Text("pdf_reader.finished_badge")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Label(formattedTotalTime(file.readingTimeSeconds), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(
                        String(
                            format: String(localized: "pdf_reader.recent_file_page_format"),
                            file.lastPageNumber + 1,
                            file.totalPages
                        ),
                        systemImage: "doc.plaintext"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if file.totalPages > 0 {
                    ProgressView(value: Double(pct), total: 100)
                        .tint(finished ? .blue : .green)
                }
            }

            Spacer()

            if file.totalPages > 0 {
                Text(
                    String(
                        format: String(localized: "pdf_reader.progress_percent_format"),
                        pct
                    )
                )
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(finished ? .blue : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func overviewItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.green)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressPercent(for file: RecentFile) -> Int {
        guard file.totalPages > 0 else { return 0 }
        return min(100, Int((Double(file.lastPageNumber + 1) / Double(file.totalPages)) * 100))
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
