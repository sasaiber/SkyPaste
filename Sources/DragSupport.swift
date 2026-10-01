import SwiftUI
import AppKit

// MARK: - Multi-file drag source (works without ⌘, transparent to hover/clicks)

/// A transparent overlay NSView that:
/// - Returns nil from hitTest → completely invisible to SwiftUI's onHover and tap gestures
/// - Watches mouse events via a local monitor to detect drag gestures
/// - Starts a native NSDraggingSession with all provided URLs when a drag is detected
struct MultiFileDragOverlay: NSViewRepresentable {
    var urls: [URL]
    var dragImage: NSImage?

    func makeNSView(context: Context) -> _MultiFileDragView {
        let v = _MultiFileDragView()
        v.urls = urls
        v.dragImage = dragImage
        return v
    }

    func updateNSView(_ nsView: _MultiFileDragView, context: Context) {
        nsView.urls = urls
        nsView.dragImage = dragImage
    }
}

final class _MultiFileDragView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var dragImage: NSImage?

    private var mouseDownPoint: NSPoint?  // in self coordinates
    private var dragStarted = false
    private var monitor: Any?

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { startMonitor() } else { stopMonitor() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stopMonitor() }
    }

    deinit { stopMonitor() }

    // MARK: - Event Monitor

    private func startMonitor() {
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
            return event          // always pass event through
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            guard window != nil else { return }
            // Convert window-local point to our coordinate space
            let pt = convert(event.locationInWindow, from: nil)
            // Only track if the click is inside our frame
            if bounds.contains(pt) {
                mouseDownPoint = pt
                dragStarted = false
            } else {
                mouseDownPoint = nil
            }

        case .leftMouseDragged:
            guard !dragStarted, !urls.isEmpty,
                  let downPt = mouseDownPoint else { return }
            let pt = convert(event.locationInWindow, from: nil)
            let dx = pt.x - downPt.x
            let dy = pt.y - downPt.y
            guard sqrt(dx * dx + dy * dy) > 4 else { return }
            dragStarted = true
            startDragSession(at: pt, originalEvent: event)

        case .leftMouseUp:
            mouseDownPoint = nil
            dragStarted = false

        default:
            break
        }
    }

    // MARK: - Drag Session

    private func startDragSession(at pt: NSPoint, originalEvent event: NSEvent) {
        let items: [NSDraggingItem] = urls.map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon: NSImage
            if let provided = dragImage, urls.count == 1 {
                icon = provided
            } else {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            }
            let sz: CGFloat = 32
            icon.size = NSSize(width: sz, height: sz)
            item.setDraggingFrame(
                NSRect(x: pt.x - sz / 2, y: pt.y - sz / 2, width: sz, height: sz),
                contents: icon
            )
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Always copy — never allow .link/.move so Finder creates a real copy, not an alias
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragStarted = false
        mouseDownPoint = nil
    }

    // MARK: - Transparent to mouse events (onHover / tap work normally)

    /// Returning nil makes this view invisible to the AppKit hit-test chain,
    /// so SwiftUI's onHover tracking areas and tap gestures are unaffected.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - SwiftUI modifier

extension View {
    /// Adds a transparent drag layer for files/folders without requiring ⌘.
    /// Does nothing when `urls` is empty so there is no overhead for text rows.
    @ViewBuilder
    func multiFileDraggable(urls: [URL], dragImage: NSImage? = nil) -> some View {
        if urls.isEmpty {
            self
        } else {
            self.overlay(
                MultiFileDragOverlay(urls: urls, dragImage: dragImage)
                    .allowsHitTesting(false) // SwiftUI layer also ignores it
            )
        }
    }
}
