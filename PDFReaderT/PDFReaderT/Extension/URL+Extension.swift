//
//  URL+Extension.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import Foundation

extension URL {
    func bookmarkData() -> Data? {
        do {
            // For security-scoped URLs, we need to ensure we have access
            let hasAccess = self.startAccessingSecurityScopedResource()
            
            defer {
                if hasAccess {
                    self.stopAccessingSecurityScopedResource()
                }
            }
            
            // Create bookmark with appropriate options
            return try self.bookmarkData(
                options: [.minimalBookmark, .suitableForBookmarkFile],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            print("Error creating bookmark: \(error)")
            
            // Try alternative method for files that might be in app's documents
            do {
                return try self.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                print("Alternative bookmark creation also failed: \(error)")
                return nil
            }
        }
    }
    
    static func resolveBookmark(_ bookmarkData: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("Bookmark is stale, consider refreshing")
            }
            
            return url
        } catch {
            print("Error resolving bookmark: \(error)")
            return nil
        }
    }
}
