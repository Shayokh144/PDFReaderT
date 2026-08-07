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
    let documentId: String?
    @Binding var currentPage: Int
    @Binding var searchNavigation: SearchNavigationRequest?
    @Binding var goToBookmarkRequest: Bool
    let onReadOnlyPDF: () -> Void
    let onSaveFailed: () -> Void
    let onSaveFlusherReady: (SaveFlusher) -> Void
    let onSingleTap: () -> Void
    let onUserInteraction: () -> Void
    let onBookmarkMissing: () -> Void

    init(
        url: URL,
        initialPage: Int?,
        documentId: String? = nil,
        currentPage: Binding<Int>,
        searchNavigation: Binding<SearchNavigationRequest?> = .constant(nil),
        goToBookmarkRequest: Binding<Bool> = .constant(false),
        onReadOnlyPDF: @escaping () -> Void = {},
        onSaveFailed: @escaping () -> Void = {},
        onSaveFlusherReady: @escaping (SaveFlusher) -> Void = { _ in },
        onSingleTap: @escaping () -> Void = {},
        onUserInteraction: @escaping () -> Void = {},
        onBookmarkMissing: @escaping () -> Void = {}
    ) {
        self.url = url
        self.initialPage = initialPage
        self.documentId = documentId
        _currentPage = currentPage
        _searchNavigation = searchNavigation
        _goToBookmarkRequest = goToBookmarkRequest
        self.onReadOnlyPDF = onReadOnlyPDF
        self.onSaveFailed = onSaveFailed
        self.onSaveFlusherReady = onSaveFlusherReady
        self.onSingleTap = onSingleTap
        self.onUserInteraction = onUserInteraction
        self.onBookmarkMissing = onBookmarkMissing
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
        } else if context.coordinator.loadedDocumentId != documentId {
            context.coordinator.restoreBookmarkFromStore(in: pdfView)
        }

        // Navigate to and highlight a search result
        if let nav = searchNavigation {
            context.coordinator.navigateToSearchResult(nav, in: pdfView)
            DispatchQueue.main.async {
                self.searchNavigation = nil
            }
        }

        if goToBookmarkRequest {
            let found = context.coordinator.goToBookmark(in: pdfView)
            DispatchQueue.main.async {
                self.goToBookmarkRequest = false
                if !found {
                    self.onBookmarkMissing()
                }
            }
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
            coordinator.resetScaleTracking()
            coordinator.fitDocumentToVisibleBounds(in: pdfView, force: true)

            // Navigate to the initial page if specified
            if let initialPage = initialPage,
                initialPage < document.pageCount,
                let page = document.page(at: initialPage)
            {

                // Add a slight delay to ensure the document is fully loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pdfView.go(to: page)
                    coordinator.updateBookmarkFlagPosition(in: pdfView)
                }
            }

            coordinator.restoreBookmarkFromStore(in: pdfView)
        } else {
            log.error("Failed to load PDF document")
        }
    }
}

extension PDFViewer {
    final class Coordinator: NSObject {
        var parent: PDFViewer
        var loadedDocumentURL: URL?
        var loadedDocumentId: String?
        private weak var pdfView: PDFView?

        private var pageChangeObserver: NSObjectProtocol?
        private var selectionChangeObserver: NSObjectProtocol?
        private var scaleChangeObserver: NSObjectProtocol?
        private let saveCoordinator = PDFSaveCoordinator()
        private var didRegisterFlusher = false
        private var lastFittedSize: CGSize = .zero

        private let bookmarkStore: UserPdfBookmarkStoring
        private var currentBookmark: PdfBookmark?

        init(
            parent: PDFViewer,
            bookmarkStore: UserPdfBookmarkStoring = UserDefaultsPdfBookmarkStore()
        ) {
            self.parent = parent
            self.bookmarkStore = bookmarkStore
        }

        func configure(pdfView: PDFView) {
            self.pdfView = pdfView

            guard let highlightablePDFView = pdfView as? HighlightablePDFView else {
                return
            }

            highlightablePDFView.onLayoutChanged = { [weak self] view in
                self?.fitDocumentToVisibleBounds(in: view)
                self?.updateBookmarkFlagPosition(in: view)
            }

            highlightablePDFView.onViewportChanged = { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                self.updateBookmarkFlagPosition(in: pdfView)
            }

            if pageChangeObserver == nil {
                pageChangeObserver = NotificationCenter.default.addObserver(
                    forName: .PDFViewPageChanged,
                    object: pdfView,
                    queue: .main
                ) { [weak self, weak pdfView] _ in
                    guard let self, let pdfView, let currentPDFPage = pdfView.currentPage,
                        let document = pdfView.document
                    else {
                        return
                    }
                    let pageIndex = document.index(for: currentPDFPage)
                    DispatchQueue.main.async { [weak self] in
                        self?.parent.currentPage = pageIndex
                    }
                    self.updateBookmarkFlagPosition(in: pdfView)
                }
            }

            if scaleChangeObserver == nil {
                scaleChangeObserver = NotificationCenter.default.addObserver(
                    forName: .PDFViewScaleChanged,
                    object: pdfView,
                    queue: .main
                ) { [weak self, weak pdfView] _ in
                    guard let self, let pdfView else { return }
                    self.updateBookmarkFlagPosition(in: pdfView)
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

            highlightablePDFView.highlightMenuTitle = String(
                localized: "pdf_reader.highlight_menu_title")
            highlightablePDFView.bookmarkFlagAccessibilityLabel = String(
                localized: "pdf_reader.bookmark_flag")
            highlightablePDFView.onHighlightSelection = { [weak self, weak pdfView] selection in
                guard let self, let pdfView else {
                    return
                }
                self.createHighlights(from: selection, in: pdfView)
            }
            highlightablePDFView.onSingleTap = { [weak self] in
                self?.parent.onSingleTap()
                self?.parent.onUserInteraction()
            }
            highlightablePDFView.onTouchActivity = { [weak self] in
                self?.parent.onUserInteraction()
            }
            highlightablePDFView.onDoubleTapAtPoint = { [weak self, weak pdfView] point in
                guard let self, let pdfView else { return }
                self.parent.onUserInteraction()
                self.placeBookmark(at: point, in: pdfView)
            }
            highlightablePDFView.onBookmarkFlagLongPress = { [weak self] in
                self?.removeBookmark()
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

        private var searchHighlightWorkItem: DispatchWorkItem?
        private var temporaryAnnotations: [PDFAnnotation] = []

        func navigateToSearchResult(_ nav: SearchNavigationRequest, in pdfView: PDFView) {
            guard let document = pdfView.document else { return }

            let selections = document.findString(nav.searchText, withOptions: [.caseInsensitive])
            guard nav.matchIndex < selections.count else { return }

            let selection = selections[nav.matchIndex]

            // Remove any previous temporary annotations
            removeTemporaryAnnotations()

            // Navigate to the selection
            pdfView.go(to: selection)

            // Add temporary highlight annotations on each line of the selection
            let lineSelections = selection.selectionsByLine()
            for lineSelection in lineSelections {
                guard let page = lineSelection.pages.first else { continue }
                let bounds = lineSelection.bounds(for: page)
                guard !bounds.isEmpty, !bounds.isNull else { continue }

                let annotation = PDFAnnotation(
                    bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = UIColor.systemYellow.withAlphaComponent(0.5)
                page.addAnnotation(annotation)
                temporaryAnnotations.append(annotation)
            }

            pdfView.setNeedsDisplay()

            // Remove temporary annotations after 2 seconds
            searchHighlightWorkItem?.cancel()
            let clearWork = DispatchWorkItem { [weak self] in
                self?.removeTemporaryAnnotations()
                pdfView.setNeedsDisplay()
            }
            searchHighlightWorkItem = clearWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: clearWork)
        }

        private func removeTemporaryAnnotations() {
            for annotation in temporaryAnnotations {
                annotation.page?.removeAnnotation(annotation)
            }
            temporaryAnnotations.removeAll()
        }

        func resetScaleTracking() {
            lastFittedSize = .zero
        }

        func fitDocumentToVisibleBounds(in pdfView: PDFView, force: Bool = false) {
            guard pdfView.bounds.width > 0.0, pdfView.bounds.height > 0.0 else {
                return
            }

            let currentSize = pdfView.bounds.size
            guard force || currentSize != lastFittedSize else {
                return
            }

            lastFittedSize = currentSize
            let currentPage = pdfView.currentPage

            let fittedScale = pdfView.scaleFactorForSizeToFit
            guard fittedScale.isFinite && fittedScale > 0.0 else {
                return
            }

            pdfView.minScaleFactor = fittedScale
            pdfView.maxScaleFactor = max(fittedScale * 4.0, fittedScale)
            pdfView.scaleFactor = fittedScale

            if let currentPage {
                pdfView.go(to: currentPage)
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

            if let scaleChangeObserver {
                NotificationCenter.default.removeObserver(scaleChangeObserver)
                self.scaleChangeObserver = nil
            }
        }

        // MARK: - Bookmark

        func restoreBookmarkFromStore(in pdfView: PDFView) {
            let documentId = parent.documentId ?? ""
            loadedDocumentId = documentId
            guard !documentId.isEmpty else {
                currentBookmark = nil
                updateBookmarkFlagPosition(in: pdfView)
                return
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let loaded = self?.bookmarkStore.getBookmark(documentId: documentId)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.currentBookmark = loaded
                    self.updateBookmarkFlagPosition(in: pdfView)
                }
            }
        }

        private func placeBookmark(at viewPoint: CGPoint, in pdfView: PDFView) {
            guard let documentId = parent.documentId, !documentId.isEmpty else { return }
            guard let page = pdfView.page(for: viewPoint, nearest: true),
                let document = pdfView.document
            else { return }

            let pagePoint = pdfView.convert(viewPoint, to: page)
            let pageIndex = document.index(for: page)
            let bookmark = PdfBookmark(
                documentId: documentId,
                pageIndex: pageIndex,
                x: pagePoint.x,
                y: pagePoint.y
            )
            currentBookmark = bookmark
            updateBookmarkFlagPosition(in: pdfView)

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.bookmarkStore.setBookmark(bookmark)
            }
        }

        private func removeBookmark() {
            let documentId = parent.documentId ?? currentBookmark?.documentId ?? ""
            currentBookmark = nil
            if let pdfView {
                updateBookmarkFlagPosition(in: pdfView)
            }
            guard !documentId.isEmpty else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.bookmarkStore.clearBookmark(documentId: documentId)
            }
        }

        func updateBookmarkFlagPosition(in pdfView: PDFView) {
            guard let highlightable = pdfView as? HighlightablePDFView else { return }
            guard let bookmark = currentBookmark,
                let document = pdfView.document,
                bookmark.pageIndex >= 0,
                bookmark.pageIndex < document.pageCount,
                let page = document.page(at: bookmark.pageIndex)
            else {
                highlightable.setBookmarkFlagVisible(false)
                return
            }

            let pagePoint = CGPoint(x: bookmark.x, y: bookmark.y)
            let viewPoint = pdfView.convert(pagePoint, from: page)

            // Hide when the point is far outside the visible viewport.
            let insetBounds = pdfView.bounds.insetBy(dx: -24, dy: -24)
            guard insetBounds.contains(viewPoint) else {
                highlightable.setBookmarkFlagVisible(false)
                return
            }

            highlightable.setBookmarkFlag(at: viewPoint)
        }

        /// Scrolls to the saved bookmark page/position. Returns `false` if none exists.
        @discardableResult
        func goToBookmark(in pdfView: PDFView) -> Bool {
            guard let bookmark = currentBookmark,
                let document = pdfView.document,
                bookmark.pageIndex >= 0,
                bookmark.pageIndex < document.pageCount,
                let page = document.page(at: bookmark.pageIndex)
            else {
                return false
            }

            let destination = PDFDestination(
                page: page,
                at: CGPoint(x: bookmark.x, y: bookmark.y)
            )
            pdfView.go(to: destination)
            DispatchQueue.main.async { [weak self] in
                self?.updateBookmarkFlagPosition(in: pdfView)
            }
            return true
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

                let annotation = PDFAnnotation(
                    bounds: lineBounds, forType: .highlight, withProperties: nil)
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
            saveCoordinator.save(
                document: document, to: url, trigger: trigger, onFailure: onFailure)
        }

        /// Opaque pastel: same *look* as green at low alpha over white; PDF saves highlight RGB without alpha.
        private static let highlightColor = UIColor(red: 0.8, green: 1.0, blue: 0.8, alpha: 1.0)
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
            self.coalescedWrite(
                document: document, to: fileURL, trigger: trigger, onFailure: onFailure)
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

/// Allows simultaneous recognition so the touch-detection gesture doesn't block scrolling/zooming.
private final class SimultaneousGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
}

private final class HighlightablePDFView: PDFView, UIEditMenuInteractionDelegate {
    var onHighlightSelection: ((PDFSelection) -> Void)?
    var highlightMenuTitle: String = "Highlight"
    var latestSelection: PDFSelection?
    var onLayoutChanged: ((HighlightablePDFView) -> Void)?
    var onViewportChanged: (() -> Void)?
    var onSingleTap: (() -> Void)?
    var onDoubleTapAtPoint: ((CGPoint) -> Void)?
    var onTouchActivity: (() -> Void)?
    var onBookmarkFlagLongPress: (() -> Void)?
    var bookmarkFlagAccessibilityLabel: String = "Bookmark"

    private lazy var editInteraction = UIEditMenuInteraction(delegate: self)
    private var didAddInteraction = false
    private var didAddTapGesture = false
    private var didAddDoubleTapGesture = false
    private var didAddTouchGesture = false
    private let touchGestureDelegate = SimultaneousGestureDelegate()
    private var lastTouchCallbackTime: Date = .distantPast
    private var menuWorkItem: DispatchWorkItem?
    private var retryWorkItem: DispatchWorkItem?
    private var isOurMenuVisible = false
    private var lastLaidOutSize: CGSize = .zero
    private var contentOffsetObservation: NSKeyValueObservation?
    private weak var bookmarkDoubleTapGesture: UITapGestureRecognizer?

    private lazy var bookmarkFlagView: UIImageView = {
        let size = Self.bookmarkFlagSize
        let imageView = UIImageView(image: Self.makeBookmarkFlagImage(size: size))
        imageView.frame = CGRect(origin: .zero, size: CGSize(width: size, height: size))
        imageView.isHidden = true
        imageView.isUserInteractionEnabled = true
        imageView.accessibilityLabel = bookmarkFlagAccessibilityLabel
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(handleBookmarkFlagLongPress(_:)))
        imageView.addGestureRecognizer(longPress)
        addSubview(imageView)
        return imageView
    }()

    private static let bookmarkFlagSize: CGFloat = 24

    override var canBecomeFirstResponder: Bool { true }

    override func layoutSubviews() {
        super.layoutSubviews()

        observeDocumentScrollViewIfNeeded()
        disableBuiltInDoubleTapZoom()

        guard bounds.size != .zero, bounds.size != lastLaidOutSize else {
            return
        }

        lastLaidOutSize = bounds.size
        onLayoutChanged?(self)
    }

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
        if window != nil && !didAddDoubleTapGesture {
            let doubleTap = UITapGestureRecognizer(
                target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            addGestureRecognizer(doubleTap)
            bookmarkDoubleTapGesture = doubleTap
            didAddDoubleTapGesture = true
        }
        if window != nil && !didAddTapGesture {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            tap.numberOfTapsRequired = 1
            tap.delegate = self
            if let doubleTap = bookmarkDoubleTapGesture {
                tap.require(toFail: doubleTap)
            }
            addGestureRecognizer(tap)
            didAddTapGesture = true
        }
        if window != nil && !didAddTouchGesture {
            let touch = UILongPressGestureRecognizer(
                target: self, action: #selector(handleTouchInteraction(_:)))
            touch.minimumPressDuration = 0
            touch.cancelsTouchesInView = false
            touch.delegate = touchGestureDelegate
            addGestureRecognizer(touch)
            didAddTouchGesture = true
        }
        if window != nil {
            disableScrollToTopBehavior()
            stripCompetingEditMenuInteractions()
            observeDocumentScrollViewIfNeeded()
            disableBuiltInDoubleTapZoom()
            _ = bookmarkFlagView
        }
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onDoubleTapAtPoint?(gesture.location(in: self))
    }

    @objc private func handleTouchInteraction(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTouchCallbackTime) >= 5 else { return }
        lastTouchCallbackTime = now
        onTouchActivity?()
    }

    @objc private func handleBookmarkFlagLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onBookmarkFlagLongPress?()
    }

    func setBookmarkFlag(at viewPoint: CGPoint) {
        let flag = bookmarkFlagView
        flag.accessibilityLabel = bookmarkFlagAccessibilityLabel
        // Position so the flag tip sits near the tap point (pole at left, tip near top-left).
        flag.frame.origin = CGPoint(
            x: viewPoint.x - flag.bounds.width * 0.15,
            y: viewPoint.y - flag.bounds.height * 0.1
        )
        flag.isHidden = false
        bringSubviewToFront(flag)
    }

    func setBookmarkFlagVisible(_ visible: Bool) {
        bookmarkFlagView.isHidden = !visible
    }

    // MARK: UIGestureRecognizerDelegate (inherited from PDFView)

    override func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    override func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Single-tap fullscreen waits for our double-tap bookmark gesture.
        if gestureRecognizer is UITapGestureRecognizer,
            (gestureRecognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 1,
            let otherTap = otherGestureRecognizer as? UITapGestureRecognizer,
            otherTap.numberOfTapsRequired == 2
        {
            return true
        }
        return false
    }

    override func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
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
            let page = selection.pages.first
        else { return }

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

    /// Prevent taps on the top system chrome from snapping the PDF back to page 1.
    private func disableScrollToTopBehavior() {
        Self.forEachScrollView(in: self) { scrollView in
            scrollView.scrollsToTop = false
        }
    }

    private func observeDocumentScrollViewIfNeeded() {
        guard contentOffsetObservation == nil else { return }
        Self.forEachScrollView(in: self) { [weak self] scrollView in
            guard let self, self.contentOffsetObservation == nil else { return }
            self.contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.new]) {
                [weak self] _, _ in
                self?.onViewportChanged?()
            }
        }
    }

    /// PDFKit's built-in double-tap zoom must not run; bookmarks own double-tap.
    private func disableBuiltInDoubleTapZoom() {
        let ours = bookmarkDoubleTapGesture
        Self.forEachGestureRecognizer(in: self) { recognizer in
            guard let tap = recognizer as? UITapGestureRecognizer,
                tap.numberOfTapsRequired == 2,
                tap !== ours
            else { return }
            tap.isEnabled = false
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

    private static func forEachScrollView(
        in view: UIView,
        action: (UIScrollView) -> Void
    ) {
        if let scrollView = view as? UIScrollView {
            action(scrollView)
        }
        for subview in view.subviews {
            forEachScrollView(in: subview, action: action)
        }
    }

    private static func forEachGestureRecognizer(
        in view: UIView,
        action: (UIGestureRecognizer) -> Void
    ) {
        for recognizer in view.gestureRecognizers ?? [] {
            action(recognizer)
        }
        for subview in view.subviews {
            forEachGestureRecognizer(in: subview, action: action)
        }
    }

    private static func makeBookmarkFlagImage(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            let scale = size / 16.0

            // Pole (Kept original orange/yellow color)
            cg.setFillColor(UIColor(red: 0.565, green: 0.933, blue: 0.565, alpha: 1).cgColor)
            cg.fill(CGRect(x: 2.5 * scale, y: 1 * scale, width: 1.5 * scale, height: 14 * scale))

            // Flag triangle (Changed to light green)
            cg.setFillColor(UIColor(red: 0.565, green: 0.933, blue: 0.565, alpha: 1).cgColor)
            cg.beginPath()
            cg.move(to: CGPoint(x: 4 * scale, y: 1.5 * scale))
            cg.addLine(to: CGPoint(x: 13.5 * scale, y: 5 * scale))
            cg.addLine(to: CGPoint(x: 4 * scale, y: 8.5 * scale))
            cg.closePath()
            cg.fillPath()
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
        guard
            let selectedText = (latestSelection ?? currentSelection)?
                .string?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
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
