import AppKit

/// 액션 종류 — 빌트인 BrowserAction / 사용자 정의 단축키 / 마우스 동작.
private enum ActionKind: Int {
    case builtin = 0
    case shortcut = 1
    case mouse = 2
}

/// Mouse Action popup의 항목. middleClick은 lines가 의미 없음.
private enum MouseChoice: Int, CaseIterable {
    case scrollUp = 0
    case scrollDown
    case scrollLeft
    case scrollRight
    case middleClick

    var label: String {
        switch self {
        case .scrollUp:    return "Scroll Up"
        case .scrollDown:  return "Scroll Down"
        case .scrollLeft:  return "Scroll Left"
        case .scrollRight: return "Scroll Right"
        case .middleClick: return "Middle Click"
        }
    }

    var hasLines: Bool { self != .middleClick }

    func toMouseAction(lines: Int) -> MouseAction {
        switch self {
        case .scrollUp:    return .scroll(direction: .up,    lines: lines)
        case .scrollDown:  return .scroll(direction: .down,  lines: lines)
        case .scrollLeft:  return .scroll(direction: .left,  lines: lines)
        case .scrollRight: return .scroll(direction: .right, lines: lines)
        case .middleClick: return .middleClick
        }
    }
}

final class AddGestureController: NSObject, NSWindowDelegate {
    static let shared = AddGestureController()

    private var window: NSWindow?
    private var captureView: GestureCaptureView?
    private weak var patternLabel: NSTextField?
    private weak var actionKindPopup: NSPopUpButton?
    private weak var actionPopup: NSPopUpButton?
    private weak var actionRow: NSStackView?
    private weak var shortcutRow: NSStackView?
    private weak var shortcutLabel: NSTextField?
    private weak var shortcutRecordButton: NSButton?
    private weak var mouseRow: NSStackView?
    private weak var mousePopup: NSPopUpButton?
    private weak var mouseLinesField: NSTextField?
    private weak var mouseLinesStepper: NSStepper?
    private weak var mouseLinesContainer: NSStackView?
    private weak var saveButton: NSButton?
    private weak var cancelButton: NSButton?

    private var capturedPattern: GesturePattern?
    private var capturedShortcut: KeyShortcut?

    /// 편집 모드 진입 시 원본 패턴. 저장 직전 비교해 패턴이 바뀌었으면 기존 항목을 먼저 제거한다.
    /// nil이면 새 항목 추가 모드.
    private var editingOriginalPattern: GesturePattern?

    /// 단축키 녹화 모드일 때 활성된 NSEvent monitor.
    private var keyMonitor: Any?

    /// disabled 제외한 액션 목록 — 사용자가 disabled를 등록하는 건 의미 없음
    private let actionChoices: [BrowserAction] = BrowserAction.allCases.filter { $0 != .disabled }

    /// 신규 추가용 진입점.
    func show() {
        show(editing: nil)
    }

    /// 편집 진입점. nil이면 신규 추가.
    func show(editing definition: GestureDefinition?) {
        if window == nil {
            buildAndShow()
        }
        prefill(with: definition)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildAndShow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
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

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 편집 / 신규 진입 시 윈도우 컨트롤 상태를 한 번에 셋업한다.
    private func prefill(with def: GestureDefinition?) {
        editingOriginalPattern = def?.pattern
        clearCapture()

        guard let def = def else {
            applyActionKind(.builtin)
            window?.title = "Add Custom Gesture"
            saveButton?.title = "Save"
            return
        }

        // 패턴 프리필 — 캔버스는 비어있되 라벨/내부값은 원본 패턴을 유지.
        // 사용자가 다시 그리면 그것이 새 패턴이 된다.
        capturedPattern = def.pattern
        patternLabel?.stringValue = def.pattern.displayString

        // 액션 종류별 프리필
        switch def.action {
        case .builtin(let action):
            applyActionKind(.builtin)
            actionKindPopup?.selectItem(withTag: ActionKind.builtin.rawValue)
            if let idx = actionChoices.firstIndex(of: action) {
                actionPopup?.selectItem(at: idx)
            }
        case .shortcut(let s):
            applyActionKind(.shortcut)
            actionKindPopup?.selectItem(withTag: ActionKind.shortcut.rawValue)
            capturedShortcut = s
            shortcutLabel?.stringValue = s.displayString
            shortcutRecordButton?.title = "Re-record"
        case .mouse(let m):
            applyActionKind(.mouse)
            actionKindPopup?.selectItem(withTag: ActionKind.mouse.rawValue)
            switch m {
            case .scroll(let dir, let lines):
                let choice: MouseChoice
                switch dir {
                case .up:    choice = .scrollUp
                case .down:  choice = .scrollDown
                case .left:  choice = .scrollLeft
                case .right: choice = .scrollRight
                }
                mousePopup?.selectItem(withTag: choice.rawValue)
                mouseLinesField?.integerValue = lines
                mouseLinesStepper?.integerValue = lines
            case .middleClick:
                mousePopup?.selectItem(withTag: MouseChoice.middleClick.rawValue)
            }
            updateMouseLinesVisibility()
        }

        window?.title = "Edit Custom Gesture"
        saveButton?.title = "Update"
        updateSaveEnabled()
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

        // Action kind selector
        let kindRow = NSStackView()
        kindRow.orientation = .horizontal
        kindRow.spacing = 10
        kindRow.alignment = .centerY

        let kindHead = NSTextField(labelWithString: "Type:")
        kindHead.font = .systemFont(ofSize: 13)
        kindHead.textColor = .secondaryLabelColor
        kindRow.addArrangedSubview(kindHead)

        let kindPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        kindPopup.addItem(withTitle: "Built-in Action")
        kindPopup.item(at: 0)?.tag = ActionKind.builtin.rawValue
        kindPopup.addItem(withTitle: "Custom Shortcut")
        kindPopup.item(at: 1)?.tag = ActionKind.shortcut.rawValue
        kindPopup.addItem(withTitle: "Mouse Action")
        kindPopup.item(at: 2)?.tag = ActionKind.mouse.rawValue
        kindPopup.target = self
        kindPopup.action = #selector(actionKindChanged(_:))
        kindPopup.translatesAutoresizingMaskIntoConstraints = false
        kindPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        self.actionKindPopup = kindPopup
        kindRow.addArrangedSubview(kindPopup)
        root.addArrangedSubview(kindRow)

        // Built-in action popup row
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        actionRow.alignment = .centerY

        let actionHead = NSTextField(labelWithString: "Action:")
        actionHead.font = .systemFont(ofSize: 13)
        actionHead.textColor = .secondaryLabelColor
        actionRow.addArrangedSubview(actionHead)

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        for action in actionChoices {
            popup.addItem(withTitle: action.menuTitle)
        }
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        self.actionPopup = popup
        actionRow.addArrangedSubview(popup)
        self.actionRow = actionRow
        root.addArrangedSubview(actionRow)

        // Custom shortcut row
        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 10
        shortcutRow.alignment = .centerY

        let shortcutHead = NSTextField(labelWithString: "Shortcut:")
        shortcutHead.font = .systemFont(ofSize: 13)
        shortcutHead.textColor = .secondaryLabelColor
        shortcutRow.addArrangedSubview(shortcutHead)

        let sLabel = NSTextField(labelWithString: "(none)")
        sLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        sLabel.translatesAutoresizingMaskIntoConstraints = false
        sLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        self.shortcutLabel = sLabel
        shortcutRow.addArrangedSubview(sLabel)

        let recordButton = NSButton(
            title: "Record",
            target: self,
            action: #selector(recordShortcutTapped)
        )
        self.shortcutRecordButton = recordButton
        shortcutRow.addArrangedSubview(recordButton)
        self.shortcutRow = shortcutRow
        root.addArrangedSubview(shortcutRow)

        // Mouse action row
        let mouseRow = NSStackView()
        mouseRow.orientation = .horizontal
        mouseRow.spacing = 10
        mouseRow.alignment = .centerY

        let mouseHead = NSTextField(labelWithString: "Mouse:")
        mouseHead.font = .systemFont(ofSize: 13)
        mouseHead.textColor = .secondaryLabelColor
        mouseRow.addArrangedSubview(mouseHead)

        let mPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        for choice in MouseChoice.allCases {
            let item = NSMenuItem(title: choice.label, action: nil, keyEquivalent: "")
            item.tag = choice.rawValue
            mPopup.menu?.addItem(item)
        }
        mPopup.target = self
        mPopup.action = #selector(mouseChoiceChanged(_:))
        mPopup.translatesAutoresizingMaskIntoConstraints = false
        mPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        self.mousePopup = mPopup
        mouseRow.addArrangedSubview(mPopup)

        // Lines container — scroll 액션일 때만 표시
        let linesContainer = NSStackView()
        linesContainer.orientation = .horizontal
        linesContainer.spacing = 6
        linesContainer.alignment = .centerY

        let linesLabel = NSTextField(labelWithString: "lines:")
        linesLabel.font = .systemFont(ofSize: 12)
        linesLabel.textColor = .secondaryLabelColor
        linesContainer.addArrangedSubview(linesLabel)

        let linesField = NSTextField()
        linesField.stringValue = "3"
        linesField.alignment = .right
        linesField.font = .systemFont(ofSize: 13)
        linesField.translatesAutoresizingMaskIntoConstraints = false
        linesField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        self.mouseLinesField = linesField
        linesContainer.addArrangedSubview(linesField)

        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 50
        stepper.increment = 1
        stepper.integerValue = 3
        stepper.target = self
        stepper.action = #selector(linesStepperChanged(_:))
        self.mouseLinesStepper = stepper
        linesContainer.addArrangedSubview(stepper)

        self.mouseLinesContainer = linesContainer
        mouseRow.addArrangedSubview(linesContainer)

        self.mouseRow = mouseRow
        root.addArrangedSubview(mouseRow)

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
        self.cancelButton = cancelButton
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
        } else {
            patternLabel?.stringValue = "(too short or ambiguous — try again)"
        }
        updateSaveEnabled()
    }

    private func clearCapture() {
        capturedPattern = nil
        captureView?.clear()
        patternLabel?.stringValue = "(draw to capture)"
        capturedShortcut = nil
        shortcutLabel?.stringValue = "(none)"
        stopRecordingShortcut(restoreUI: true)
        updateSaveEnabled()
    }

    /// Save 활성 조건: 패턴 캡처 OK + 액션 종류별 추가 조건 충족.
    private func updateSaveEnabled() {
        guard capturedPattern != nil else {
            saveButton?.isEnabled = false
            return
        }
        switch currentActionKind() {
        case .builtin:
            saveButton?.isEnabled = true
        case .shortcut:
            saveButton?.isEnabled = (capturedShortcut != nil)
        case .mouse:
            saveButton?.isEnabled = true
        }
    }

    private func currentActionKind() -> ActionKind {
        let raw = actionKindPopup?.selectedItem?.tag ?? ActionKind.builtin.rawValue
        return ActionKind(rawValue: raw) ?? .builtin
    }

    private func currentMouseChoice() -> MouseChoice {
        let raw = mousePopup?.selectedItem?.tag ?? MouseChoice.scrollUp.rawValue
        return MouseChoice(rawValue: raw) ?? .scrollUp
    }

    private func applyActionKind(_ kind: ActionKind) {
        switch kind {
        case .builtin:
            actionRow?.isHidden = false
            shortcutRow?.isHidden = true
            mouseRow?.isHidden = true
            stopRecordingShortcut(restoreUI: true)
        case .shortcut:
            actionRow?.isHidden = true
            shortcutRow?.isHidden = false
            mouseRow?.isHidden = true
        case .mouse:
            actionRow?.isHidden = true
            shortcutRow?.isHidden = true
            mouseRow?.isHidden = false
            stopRecordingShortcut(restoreUI: true)
            updateMouseLinesVisibility()
        }
        updateSaveEnabled()
    }

    /// scroll 선택일 때만 lines 입력란을 보여 준다.
    private func updateMouseLinesVisibility() {
        mouseLinesContainer?.isHidden = !currentMouseChoice().hasLines
    }

    @objc private func actionKindChanged(_ sender: NSPopUpButton) {
        applyActionKind(currentActionKind())
    }

    @objc private func mouseChoiceChanged(_ sender: NSPopUpButton) {
        updateMouseLinesVisibility()
    }

    @objc private func linesStepperChanged(_ sender: NSStepper) {
        mouseLinesField?.integerValue = sender.integerValue
    }

    @objc private func clearTapped() {
        clearCapture()
    }

    @objc private func cancelTapped() {
        window?.performClose(nil)
    }

    @objc private func saveTapped() {
        guard let pattern = capturedPattern else { return }
        let action: GestureAction
        switch currentActionKind() {
        case .builtin:
            guard let popup = actionPopup,
                  popup.indexOfSelectedItem >= 0,
                  popup.indexOfSelectedItem < actionChoices.count else { return }
            action = .builtin(actionChoices[popup.indexOfSelectedItem])
        case .shortcut:
            guard let shortcut = capturedShortcut else { return }
            action = .shortcut(shortcut)
        case .mouse:
            let choice = currentMouseChoice()
            let lines = max(1, min(50, mouseLinesField?.integerValue ?? 3))
            action = .mouse(choice.toMouseAction(lines: lines))
        }
        // 편집 모드에서 패턴이 바뀌었으면 기존 항목을 먼저 정리.
        // upsert가 같은 패턴은 알아서 덮어쓰므로 패턴이 그대로일 땐 추가 작업 불필요.
        if let original = editingOriginalPattern, original != pattern {
            CustomGestureMappings.remove(pattern: original)
        }
        let def = GestureDefinition(pattern: pattern, action: action)
        CustomGestureMappings.upsert(def)
        NotificationCenter.default.post(name: .customGesturesChanged, object: nil)
        window?.performClose(nil)
    }

    // MARK: - Shortcut recording

    @objc private func recordShortcutTapped() {
        if keyMonitor != nil {
            stopRecordingShortcut(restoreUI: true)
        } else {
            startRecordingShortcut()
        }
    }

    private func startRecordingShortcut() {
        shortcutRecordButton?.title = "Press a key…"
        shortcutLabel?.stringValue = "…"
        // 녹화 중에는 Save/Cancel의 keyEquivalent가 가로채지 않도록 잠시 비활성.
        saveButton?.keyEquivalent = ""
        cancelButton?.keyEquivalent = ""

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            // ESC 단독 — 녹화 취소
            if event.keyCode == 0x35
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.stopRecordingShortcut(restoreUI: true)
                return nil
            }
            guard let shortcut = KeyShortcut.from(event: event) else {
                // modifier-only 등 — 무시하고 계속 대기
                return nil
            }
            self.capturedShortcut = shortcut
            self.shortcutLabel?.stringValue = shortcut.displayString
            self.stopRecordingShortcut(restoreUI: true)
            self.updateSaveEnabled()
            return nil
        }
    }

    private func stopRecordingShortcut(restoreUI: Bool) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        guard restoreUI else { return }
        shortcutRecordButton?.title = (capturedShortcut == nil) ? "Record" : "Re-record"
        if capturedShortcut == nil {
            shortcutLabel?.stringValue = "(none)"
        }
        saveButton?.keyEquivalent = "\r"
        cancelButton?.keyEquivalent = "\u{1b}"
    }

    func windowWillClose(_ notification: Notification) {
        stopRecordingShortcut(restoreUI: false)
        editingOriginalPattern = nil
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

