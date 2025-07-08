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
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack {
                        Text(file.fileSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(file.dateAdded, style: .relative)
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
