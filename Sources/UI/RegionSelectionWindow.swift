import AppKit
import Carbon.HIToolbox

/// Result of an interactive region selection: the rectangle (in NSScreen global,
/// bottom-left, points) plus the NSScreen the user dragged on. The screen is
/// returned so the caller can route the capture to the correct CGDisplay and
/// apply the right backing scale.
struct RegionSelectionResult {
    let rect: CGRect      // NSScreen global coords (bottom-left, points)
    let screen: NSScreen
}

/// Picker abstraction so ScreenCaptureKitService doesn't depend on AppKit UI.
/// Tests can inject a fake picker that returns a fixed rect.
protocol RegionPicker: Sendable {
    func pickRegion() async -> RegionSelectionResult?
}

/// Full-screen overlay panel that lets the user drag a rectangle.
/// Cancellation: ESC / Cmd+. / right-click / 60s timeout.
@MainActor
final class RegionSelectionWindow: NSObject, RegionPicker {
    // Nonisolated singleton + init — only the class instance pointer is shared
    // here. All mutable state (panel, monitors, continuation) is touched solely
    // through @MainActor methods, so the singleton holding is safe.
    nonisolated static let shared = RegionSelectionWindow()
    private nonisolated override init() { super.init() }

    private var panel: NSPanel?
    private var contentView: SelectionView?
    private var continuation: CheckedContinuation<RegionSelectionResult?, Never>?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var timeoutTask: Task<Void, Never>?
    private var cursorPushed = false

    nonisolated func pickRegion() async -> RegionSelectionResult? {
        await withCheckedContinuation { (cont: CheckedContinuation<RegionSelectionResult?, Never>) in
            Task { @MainActor [weak self] in
                self?.beginSession(continuation: cont) ?? cont.resume(returning: nil)
            }
        }
    }

    private func beginSession(continuation: CheckedContinuation<RegionSelectionResult?, Never>) {
        // Tear down any prior session completely before starting a new one.
        cleanupSession(resumeWithNil: true)
        self.continuation = continuation

        let unionFrame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }

        let panel = NSPanel(
            contentRect: unionFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // .popUpMenu sits above normal windows but below system security UI.
        panel.level = .popUpMenu
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.18)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        let view = SelectionView(frame: NSRect(origin: .zero, size: unionFrame.size))
        view.panelFrameOrigin = unionFrame.origin
        view.onResult = { [weak self] localRect in
            guard let self else { return }
            guard let localRect else { self.finish(nil); return }
            let global = NSRect(
                x: localRect.origin.x + view.panelFrameOrigin.x,
                y: localRect.origin.y + view.panelFrameOrigin.y,
                width: localRect.size.width,
                height: localRect.size.height
            )
            let screen = NSScreen.screens.first(where: {
                $0.frame.intersects(global)
            }) ?? NSScreen.main ?? NSScreen.screens.first
            if let screen {
                self.finish(.init(rect: global, screen: screen))
            } else {
                self.finish(nil)
            }
        }
        panel.contentView = view

        self.panel = panel
        self.contentView = view

        panel.makeKeyAndOrderFront(nil)

        // Local monitor handles ESC when our panel is key.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isCancelKey(event) {
                Task { @MainActor in self?.finish(nil) }
                return nil
            }
            return event
        }
        // Global monitor handles ESC when focus moved away (e.g. notification banner).
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isCancelKey(event) {
                Task { @MainActor in self?.finish(nil) }
            }
        }

        NSCursor.crosshair.push()
        cursorPushed = true

        // Safety timeout — auto-cancel after 60s.
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finish(nil)
        }
        timeoutTask = task
    }

    private func finish(_ result: RegionSelectionResult?) {
        let cont = self.continuation
        self.continuation = nil
        cleanupSession(resumeWithNil: false)
        cont?.resume(returning: result)
    }

    /// Tear down panel/monitors/cursor. If `resumeWithNil` and a continuation is
    /// still pending, resume it with nil first (stale prior session).
    private func cleanupSession(resumeWithNil: Bool) {
        if resumeWithNil, let prev = self.continuation {
            self.continuation = nil
            prev.resume(returning: nil)
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
        if let m = globalKeyMonitor {
            NSEvent.removeMonitor(m)
            globalKeyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        contentView = nil
    }

    private static func isCancelKey(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) { return true }
        if event.charactersIgnoringModifiers == "."
            && event.modifierFlags.contains(.command) {
            return true
        }
        return false
    }
}

/// Drag-rectangle drawing view. nil result = user cancelled / drag too small.
private final class SelectionView: NSView {
    var panelFrameOrigin: NSPoint = .zero
    var onResult: ((CGRect?) -> Void)?

    private var startLocal: NSPoint?
    private var currentLocal: NSPoint?

    private static let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
        .backgroundColor: NSColor.black.withAlphaComponent(0.7)
    ]

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        startLocal = p
        currentLocal = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let prev = selectionRect()
        currentLocal = convert(event.locationInWindow, from: nil)
        let next = selectionRect()
        // Mark only the union of prev+next as dirty — large multi-monitor unions
        // would otherwise redraw the whole panel each frame.
        setNeedsDisplay(prev.union(next).insetBy(dx: -2, dy: -2))
    }

    override func mouseUp(with event: NSEvent) {
        let rect = selectionRect()
        if rect.width >= 4 && rect.height >= 4 {
            onResult?(rect)
        } else {
            onResult?(nil)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onResult?(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = selectionRect()
        guard rect.width > 0 && rect.height > 0 else { return }

        NSColor.clear.setFill()
        rect.fill(using: .copy)

        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        NSColor.systemBlue.setStroke()
        path.stroke()

        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let size = text.size(withAttributes: Self.labelAttrs)
        let labelOrigin = NSPoint(x: rect.maxX - size.width - 4, y: rect.minY - size.height - 4)
        text.draw(at: labelOrigin, withAttributes: Self.labelAttrs)
    }

    private func selectionRect() -> NSRect {
        guard let s = startLocal, let c = currentLocal else { return .zero }
        return NSRect(
            x: min(s.x, c.x),
            y: min(s.y, c.y),
            width: abs(c.x - s.x),
            height: abs(c.y - s.y)
        )
    }
}
