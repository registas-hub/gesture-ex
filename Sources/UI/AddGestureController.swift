import AppKit

final class AddGestureController: NSObject, NSWindowDelegate {
    static let shared = AddGestureController()

    private var window: NSWindow?
    private var captureView: GestureCaptureView?
    private weak var patternLabel: NSTextField?
    private weak var actionPopup: NSPopUpButton?
    private weak var saveButton: NSButton?

    private var capturedPattern: GesturePattern?

    /// disabled 제외한 액션 목록 — 사용자가 disabled를 등록하는 건 의미 없음
    private let actionChoices: [BrowserAction] = BrowserAction.allCases.filter { $0 != .disabled }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        buildAndShow()
    }

    private func buildAndShow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Add Custom Gesture"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = buildContent()
        w.center()
        self.window = w
        clearCapture()

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Draw your gesture")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(title)

        let desc = NSTextField(labelWithString:
            "Click and drag in the area below. Direction changes are recognized as new segments.")
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        root.addArrangedSubview(desc)

        // Drawing area
        let capture = GestureCaptureView(frame: NSRect(x: 0, y: 0, width: 380, height: 240))
        capture.translatesAutoresizingMaskIntoConstraints = false
        capture.widthAnchor.constraint(equalToConstant: 380).isActive = true
        capture.heightAnchor.constraint(equalToConstant: 240).isActive = true
        capture.onCapture = { [weak self] pattern in
            self?.handleCapture(pattern)
        }
        self.captureView = capture
        root.addArrangedSubview(capture)

        // Pattern preview
        let patternRow = NSStackView()
        patternRow.orientation = .horizontal
        patternRow.spacing = 10
        patternRow.alignment = .centerY

        let patternHead = NSTextField(labelWithString: "Pattern:")
        patternHead.font = .systemFont(ofSize: 13)
        patternHead.textColor = .secondaryLabelColor
        patternRow.addArrangedSubview(patternHead)

        let pLabel = NSTextField(labelWithString: "(draw to capture)")
        pLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        self.patternLabel = pLabel
        patternRow.addArrangedSubview(pLabel)
        root.addArrangedSubview(patternRow)

        // Action popup
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        actionRow.alignment = .centerY

        let actionHead = NSTextField(labelWithString: "Action:")
        actionHead.font = .systemFont(ofSize: 13)
        actionHead.textColor = .secondaryLabelColor
        actionRow.addArrangedSubview(actionHead)

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        for action in actionChoices {
            popup.addItem(withTitle: action.label)
        }
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        self.actionPopup = popup
        actionRow.addArrangedSubview(popup)
        root.addArrangedSubview(actionRow)

        // Footer (Clear / Cancel / Save)
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearTapped))
        footer.addArrangedSubview(clearButton)

        let flex = NSView()
        flex.translatesAutoresizingMaskIntoConstraints = false
        flex.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(flex)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"  // ESC
        footer.addArrangedSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        saveButton.keyEquivalent = "\r"  // Return
        saveButton.bezelStyle = .rounded
        saveButton.isEnabled = false
        self.saveButton = saveButton
        footer.addArrangedSubview(saveButton)

        root.addArrangedSubview(footer)

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        return container
    }

    private func handleCapture(_ pattern: GesturePattern?) {
        capturedPattern = pattern
        if let p = pattern {
            patternLabel?.stringValue = p.displayString
            saveButton?.isEnabled = true
        } else {
            patternLabel?.stringValue = "(too short or ambiguous — try again)"
            saveButton?.isEnabled = false
        }
    }

    private func clearCapture() {
        capturedPattern = nil
        captureView?.clear()
        patternLabel?.stringValue = "(draw to capture)"
        saveButton?.isEnabled = false
    }

    @objc private func clearTapped() {
        clearCapture()
    }

    @objc private func cancelTapped() {
        window?.performClose(nil)
    }

    @objc private func saveTapped() {
        guard let pattern = capturedPattern,
              let popup = actionPopup,
              popup.indexOfSelectedItem >= 0,
              popup.indexOfSelectedItem < actionChoices.count else { return }
        let action = actionChoices[popup.indexOfSelectedItem]
        let def = GestureDefinition(pattern: pattern, action: action)
        CustomGestureMappings.upsert(def)
        NotificationCenter.default.post(name: .customGesturesChanged, object: nil)
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        clearCapture()
    }
}

/// 사용자가 자유 드래그로 path를 그리는 NSView. 좌클릭 사용.
/// path는 view-local(bottom-left) 좌표로 캡처되며 mouseUp 시 CGEvent 좌표(top-left)로 변환해 PathAnalyzer에 전달.
private final class GestureCaptureView: NSView {
    var onCapture: ((GesturePattern?) -> Void)?

    private var localPath: [NSPoint] = []
    private let lineLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private let placeholder = NSTextField(labelWithString: "Click and drag to draw")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        glowLayer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.35).cgColor
        glowLayer.fillColor = nil
        glowLayer.lineWidth = 12
        glowLayer.lineCap = .round
        glowLayer.lineJoin = .round
        layer?.addSublayer(glowLayer)

        lineLayer.strokeColor = NSColor.systemBlue.cgColor
        lineLayer.fillColor = nil
        lineLayer.lineWidth = 4
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
        layer?.addSublayer(lineLayer)

        placeholder.font = .systemFont(ofSize: 13)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        localPath = [p]
        placeholder.isHidden = true
        redraw()
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        localPath.append(p)
        redraw()
    }

    override func mouseUp(with event: NSEvent) {
        // view-local (bottom-left) → CGEvent 스타일(top-left)로 y 뒤집기
        let h = bounds.height
        let cgPath = localPath.map { CGPoint(x: $0.x, y: h - $0.y) }
        let pattern = PathAnalyzer.analyze(path: cgPath)
        onCapture?(pattern)
    }

    func clear() {
        localPath = []
        placeholder.isHidden = false
        redraw()
    }

    private func redraw() {
        let bezier = NSBezierPath()
        if let first = localPath.first {
            bezier.move(to: first)
            for pt in localPath.dropFirst() {
                bezier.line(to: pt)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cg = bezier.asCGPath
        lineLayer.path = cg
        glowLayer.path = cg
        CATransaction.commit()
    }
}

// MARK: - App Delegate (Menu Bar UI)

