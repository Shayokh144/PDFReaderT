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
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack {
                        Text(file.fileSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Show page info if available
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
                        
                        Spacer()
                        Text(formattedDateAdded(file.dateAdded))
                            .font(.caption)
                            .foregroundColor(.secondary)
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
