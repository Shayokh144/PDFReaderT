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
            return try self.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            print("Error creating bookmark: \(error)")
            return nil
        }
    }
    
    static func resolveBookmark(_ bookmarkData: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale)
            return isStale ? nil : url
        } catch {
            print("Error resolving bookmark: \(error)")
            return nil
        }
    }
}
