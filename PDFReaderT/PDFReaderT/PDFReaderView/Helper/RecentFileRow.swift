//
//  RecentFileRow.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import SwiftUI

struct RecentFileRow: View {
    let file: RecentFile
    let onTap: () -> Void

    private var progressPercent: Int {
        guard file.totalPages > 0 else { return 0 }
        return min(100, Int((Double(file.lastPageNumber + 1) / Double(file.totalPages)) * 100))
    }

    private var isFinished: Bool { progressPercent >= 95 }

    /// Minutes when total reading time is at most 60 minutes; otherwise hours (whole or one decimal).
    private func formattedReadingTime(_ seconds: TimeInterval) -> String {
        let totalMinutes = seconds / 60.0
        if totalMinutes <= 60 {
            let minutes = max(0, Int((seconds / 60.0).rounded(.toNearestOrAwayFromZero)))
            return String(
                format: String(localized: "pdf_reader.reading_time_minutes_format"),
                locale: .current,
                minutes
            )
        }
        let hours = seconds / 3600.0
        if abs(hours - hours.rounded()) < 0.01 {
            return String(
                format: String(localized: "pdf_reader.reading_time_hours_whole_format"),
                locale: .current,
                Int(hours.rounded())
            )
        }
        let roundedTenth = (hours * 10).rounded() / 10
        return String(
            format: String(localized: "pdf_reader.reading_time_hours_decimal_format"),
            locale: .current,
            roundedTenth
        )
    }

    /// Stable caption without live second-by-second updates from `Text(_:style: .relative)`.
    private func formattedDateAdded(_ date: Date) -> String {
        let secondsAgo = Date().timeIntervalSince(date)
        if secondsAgo < 60 {
            return String(localized: "pdf_reader.recent_file_date_added_just_now")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isFinished ? "checkmark.circle.fill" : "doc.text.fill")
                    .foregroundColor(isFinished ? .blue : .green)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(file.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if isFinished {
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
                    
                    HStack {
                        Text(file.fileSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if file.totalPages > 0 {
                            Text("pdf_reader.list_separator")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(
                                String(
                                    format: String(localized: "pdf_reader.recent_file_page_format"),
                                    file.lastPageNumber + 1,
                                    file.totalPages
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        Text("pdf_reader.list_separator")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(formattedReadingTime(file.readingTimeSeconds))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if file.totalPages > 0 {
                            Text("pdf_reader.list_separator")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(
                                String(
                                    format: String(localized: "pdf_reader.progress_percent_format"),
                                    progressPercent
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        Text(formattedDateAdded(file.dateAdded))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if file.totalPages > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemGray4))
                                    .frame(height: 4)
                                Capsule()
                                    .fill(isFinished ? Color.blue : Color.green)
                                    .frame(width: geo.size.width * CGFloat(progressPercent) / 100.0, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
