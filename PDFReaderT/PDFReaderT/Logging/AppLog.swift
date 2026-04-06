//
//  AppLog.swift
//  PDFReaderT
//

import OSLog

/// App-wide loggers (subsystem + category). Categories group logs in Console (ViewModel, UI, Storage, Bookmarks, Network, …); use ``logger(category:)`` for one-offs.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "PDFReaderT"
    
    static let viewModel = Logger(subsystem: subsystem, category: "ViewModel")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    static let bookmarks = Logger(subsystem: subsystem, category: "Bookmarks")
    static let network = Logger(subsystem: subsystem, category: "Network")
    
    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
    
    /// Use at the start of a log message: `log.debug("\(AppLog.scopePrefix(for: Self.self)) …")`.
    /// `function` defaults to the **call site’s** method name (via `#function`).
    static func scopePrefix(for type: Any.Type, function: StaticString = #function) -> String {
        "LOG_T \(String(describing: type)).\(function)"
    }
}
