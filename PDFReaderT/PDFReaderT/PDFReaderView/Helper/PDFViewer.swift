//
//  PDFViewer.swift
//  PDFReaderT
//
//  Created by S M Taher on 8/7/25.
//

import OSLog
import PDFKit
import SwiftUI
import UIKit

private let log = AppLog.ui

final class SaveFlusher {
    private let asyncHandler: (@escaping () -> Void) -> Void
    private let syncHandler: () -> Void
    
    fileprivate init(
        asyncHandler: @escaping (@escaping () -> Void) -> Void,
        syncHandler: @escaping () -> Void
    ) {
        self.asyncHandler = asyncHandler
        self.syncHandler = syncHandler
    }
    
    func flush(completion: @escaping () -> Void) {
        asyncHandler(completion)
    }
    
    /// Blocks the calling thread until every pending save finishes.
    /// Safe to call on main when the UI is not visible (e.g. background transition).
    func flushSync() {
        syncHandler()
    }
}

struct PDFViewer: UIViewRepresentable {
    let url: URL
    let initialPage: Int?
    @Binding var currentPage: Int
    let onReadOnlyPDF: () -> Void
    let onSaveFailed: () -> Void
    let onSaveFlusherReady: (SaveFlusher) -> Void
    
    init(
        url: URL,
        initialPage: Int?,
        currentPage: Binding<Int>,
        onReadOnlyPDF: @escaping () -> Void = {},
        onSaveFailed: @escaping () -> Void = {},
        onSaveFlusherReady: @escaping (SaveFlusher) -> Void = { _ in }
    ) {
        self.url = url
        self.initialPage = initialPage
        _currentPage = currentPage
        self.onReadOnlyPDF = onReadOnlyPDF
        self.onSaveFailed = onSaveFailed
        self.onSaveFlusherReady = onSaveFlusherReady
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = HighlightablePDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        context.coordinator.configure(pdfView: pdfView)
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configure(pdfView: pdfView)
        
        // Reload when the URL changes, otherwise keep the current document.
        if pdfView.document == nil || context.coordinator.loadedDocumentURL != url {
            loadDocument(into: pdfView, coordinator: context.coordinator)
        }
    }
    
    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.saveDocument(from: uiView, trigger: "dismantle")
        coordinator.detachPageChangeObserver()
    }
    
    private func loadDocument(into pdfView: PDFView, coordinator: Coordinator) {
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            log.error("Failed to access security-scoped resource")
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            coordinator.loadedDocumentURL = url
            
            // Navigate to the initial page if specified
            if let initialPage = initialPage,
               initialPage < document.pageCount,
               let page = document.page(at: initialPage) {
                
                // Add a slight delay to ensure the document is fully loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pdfView.go(to: page)
                }
            }
        } else {
            log.error("Failed to load PDF document")
        }
    }
}

extension PDFViewer {
    final class Coordinator: NSObject {
        var parent: PDFViewer
        var loadedDocumentURL: URL?
        private weak var pdfView: PDFView?
        
        private var pageChangeObserver: NSObjectProtocol?
        private var selectionChangeObserver: NSObjectProtocol?
        private let saveCoordinator = PDFSaveCoordinator()
        private var didRegisterFlusher = false
        
        init(parent: PDFViewer) {
            self.parent = parent
        }
        
        func configure(pdfView: PDFView) {
            self.pdfView = pdfView
            
            guard let highlightablePDFView = pdfView as? HighlightablePDFView else {
                return
            }
            
            if pageChangeObserver == nil {
                pageChangeObserver = NotificationCenter.default.addObserver(
                    forName: .PDFViewPageChanged,
                    object: pdfView,
                    queue: .main
                ) { [weak self, weak pdfView] _ in
                    guard let self, let pdfView, let currentPDFPage = pdfView.currentPage, let document = pdfView.document else {
                        return
                    }
                    let pageIndex = document.index(for: currentPDFPage)
                    DispatchQueue.main.async { [weak self] in
                        self?.parent.currentPage = pageIndex
                    }
                }
            }
            
            if selectionChangeObserver == nil {
                selectionChangeObserver = NotificationCenter.default.addObserver(
                    forName: .PDFViewSelectionChanged,
                    object: pdfView,
                    queue: .main
                ) { [weak view = highlightablePDFView, weak pdfView] _ in
                    view?.latestSelection = pdfView?.currentSelection
                    view?.refreshHighlightMenuState()
                }
            }
            
            highlightablePDFView.highlightMenuTitle = String(localized: "pdf_reader.highlight_menu_title")
            highlightablePDFView.onHighlightSelection = { [weak self, weak pdfView] selection in
                guard let self, let pdfView else {
                    return
                }
                self.createHighlights(from: selection, in: pdfView)
            }
            
            if !didRegisterFlusher {
                didRegisterFlusher = true
                let coordinator = saveCoordinator
                let flusher = SaveFlusher(
                    asyncHandler: { completion in
                        DispatchQueue.global(qos: .userInitiated).async {
                            coordinator.waitForPendingSaves()
                            DispatchQueue.main.async { completion() }
                        }
                    },
                    syncHandler: {
                        coordinator.waitForPendingSaves()
                    }
                )
                parent.onSaveFlusherReady(flusher)
            }
        }
        
        func detachPageChangeObserver() {
            if let pageChangeObserver {
                NotificationCenter.default.removeObserver(pageChangeObserver)
                self.pageChangeObserver = nil
            }
            
            if let selectionChangeObserver {
                NotificationCenter.default.removeObserver(selectionChangeObserver)
                self.selectionChangeObserver = nil
            }
        }
        
        private func createHighlights(from selection: PDFSelection, in pdfView: PDFView) {
            guard let document = pdfView.document else {
                return
            }
            
            // TODO: Add fallback persistence for read-only documents in app storage.
            // Note: FileManager.isWritableFile can report false for security-scoped URLs
            // even when PDFDocument.write(to:) succeeds, so we avoid using it as a hard gate.
            guard document.allowsCommenting else {
                parent.onReadOnlyPDF()
                return
            }
            
            let lineSelections = selection.selectionsByLine()
            for lineSelection in lineSelections {
                guard let page = lineSelection.pages.first else {
                    continue
                }
                
                let lineBounds = lineSelection.bounds(for: page)
                guard !lineBounds.isEmpty && !lineBounds.isNull else {
                    continue
                }
                
                let annotation = PDFAnnotation(bounds: lineBounds, forType: .highlight, withProperties: nil)
                annotation.color = Self.highlightColor
                page.addAnnotation(annotation)
            }
            
            pdfView.setNeedsDisplay()
            saveDocumentIfNeeded(trigger: "highlight-created")
        }
        
        func saveDocumentIfNeeded(trigger: String) {
            guard let loadedDocumentURL, let document = pdfView?.document else {
                return
            }
            enqueueSave(document: document, to: loadedDocumentURL, trigger: trigger)
        }
        
        func saveDocument(from pdfView: PDFView, trigger: String) {
            guard let loadedDocumentURL, let document = pdfView.document else {
                return
            }
            enqueueSave(document: document, to: loadedDocumentURL, trigger: trigger)
        }
        
        private func enqueueSave(document: PDFDocument, to url: URL, trigger: String) {
            let onFailure: () -> Void = { [weak self] in
                self?.parent.onSaveFailed()
            }
            saveCoordinator.save(document: document, to: url, trigger: trigger, onFailure: onFailure)
        }
        
        private static let highlightColor = UIColor.yellow.withAlphaComponent(0.5)
    }
}

// MARK: - PDFSaveCoordinator

/// Owns the serial queue, coalescing flags, and write logic for persisting
/// PDF annotations.  Intentionally holds **no** back-reference to
/// `PDFViewer.Coordinator`, so the coordinator can be deallocated freely
/// while a long write (large PDF) finishes in the background.
private final class PDFSaveCoordinator {
    private var hasPendingSave = false
    private var isSaveRunning = false
    private let queue = DispatchQueue(label: "com.pdfreadert.pdfviewer.save", qos: .utility)
    
    /// Blocks the caller until every previously enqueued save has finished.
    func waitForPendingSaves() {
        queue.sync {}
    }
    
    func save(
        document: PDFDocument,
        to fileURL: URL,
        trigger: String,
        onFailure: @escaping () -> Void
    ) {
        // Begin the background task BEFORE dispatching to the serial queue.
        // Without this, the app can be suspended between enqueue and write,
        // losing highlight annotations that were added just before backgrounding.
        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "PDFAnnotationSave") {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
        
        queue.async { [self] in
            defer {
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                    bgTaskID = .invalid
                }
            }
            self.hasPendingSave = true
            self.coalescedWrite(document: document, to: fileURL, trigger: trigger, onFailure: onFailure)
        }
    }
    
    private func coalescedWrite(
        document: PDFDocument,
        to fileURL: URL,
        trigger: String,
        onFailure: @escaping () -> Void
    ) {
        guard !isSaveRunning else { return }
        
        isSaveRunning = true
        defer { isSaveRunning = false }
        
        while hasPendingSave {
            hasPendingSave = false
            
            guard fileURL.startAccessingSecurityScopedResource() else {
                log.error("Failed security-scoped access while saving (\(trigger))")
                DispatchQueue.main.async { onFailure() }
                return
            }
            
            let didWrite = document.write(to: fileURL)
            fileURL.stopAccessingSecurityScopedResource()
            
            if !didWrite {
                log.error("Failed writing PDF annotations (\(trigger))")
                DispatchQueue.main.async { onFailure() }
                return
            }
        }
    }
}

// MARK: - HighlightablePDFView

private final class HighlightablePDFView: PDFView, UIEditMenuInteractionDelegate {
    var onHighlightSelection: ((PDFSelection) -> Void)?
    var highlightMenuTitle: String = "Highlight"
    var latestSelection: PDFSelection?
    
    private lazy var editInteraction = UIEditMenuInteraction(delegate: self)
    private var didAddInteraction = false
    private var menuWorkItem: DispatchWorkItem?
    private var retryWorkItem: DispatchWorkItem?
    private var isOurMenuVisible = false
    
    override var canBecomeFirstResponder: Bool { true }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.copy(_:)) {
            return hasSelectionText
        }
        if action == NSSelectorFromString("_define:") {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
    
    override func copy(_ sender: Any?) {
        guard let text = (latestSelection ?? currentSelection)?.string else { return }
        UIPasteboard.general.string = text
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && !didAddInteraction {
            addInteraction(editInteraction)
            didAddInteraction = true
        }
        if window != nil {
            stripCompetingEditMenuInteractions()
        }
    }
    
    /// Called by the coordinator on every `PDFViewSelectionChanged` notification.
    /// Debounces and then programmatically presents our edit menu at the selection.
    func refreshHighlightMenuState() {
        menuWorkItem?.cancel()
        retryWorkItem?.cancel()
        stripCompetingEditMenuInteractions()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.latestSelection = self.currentSelection
            
            guard self.hasSelectionText else {
                self.editInteraction.dismissMenu()
                return
            }
            self.presentHighlightMenu(remainingAttempts: 4)
        }
        menuWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    private func presentHighlightMenu(remainingAttempts: Int) {
        guard hasSelectionText, remainingAttempts > 0,
              let selection = latestSelection ?? currentSelection,
              let page = selection.pages.first else { return }
        
        let selectionBounds = selection.bounds(for: page)
        let viewBounds = convert(selectionBounds, from: page)
        let sourcePoint = CGPoint(x: viewBounds.midX, y: viewBounds.minY)
        
        UIMenuController.shared.hideMenu(from: self)
        stripCompetingEditMenuInteractions()
        
        let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: sourcePoint)
        editInteraction.presentEditMenu(with: config)
        
        // If our menu didn't appear, retry after a short interval
        retryWorkItem?.cancel()
        let retry = DispatchWorkItem { [weak self] in
            guard let self, self.hasSelectionText, !self.isOurMenuVisible else { return }
            self.presentHighlightMenu(remainingAttempts: remainingAttempts - 1)
        }
        retryWorkItem = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: retry)
    }
    
    private func stripCompetingEditMenuInteractions() {
        let ours = editInteraction
        Self.forEachEditMenuInteraction(in: self) { view, interaction in
            if interaction !== ours {
                interaction.dismissMenu()
                view.removeInteraction(interaction)
            }
        }
    }
    
    private static func forEachEditMenuInteraction(
        in view: UIView,
        action: (UIView, UIEditMenuInteraction) -> Void
    ) {
        for interaction in view.interactions {
            if let emi = interaction as? UIEditMenuInteraction {
                action(view, emi)
            }
        }
        for subview in view.subviews {
            forEachEditMenuInteraction(in: subview, action: action)
        }
    }
    
    // MARK: UIEditMenuInteractionDelegate
    
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard hasSelectionText else { return nil }
        
        let highlightAction = UIAction(
            title: highlightMenuTitle,
            image: UIImage(systemName: "highlighter")
        ) { [weak self] _ in
            self?.highlight(nil)
        }
        
        return UIMenu(children: suggestedActions + [highlightAction])
    }
    
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willPresentMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        isOurMenuVisible = true
        retryWorkItem?.cancel()
    }
    
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        isOurMenuVisible = false
    }
    
    // MARK: Selection & action
    
    var hasSelectionText: Bool {
        guard let selectedText = (latestSelection ?? currentSelection)?
            .string?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !selectedText.isEmpty
    }
    
    @objc func highlight(_ sender: Any?) {
        guard let selection = latestSelection ?? currentSelection else {
            return
        }
        onHighlightSelection?(selection)
    }
}
