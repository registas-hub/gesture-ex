import AppKit

final class SettingsWindow: NSObject, NSWindowDelegate, NSTextViewDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var popups: [GestureDirection: NSPopUpButton] = [:]

    // Live Overlay 컨트롤 — reset 시 갱신을 위해 보유
    private weak var trailColorWell: NSColorWell?
    private weak var backgroundColorWell: NSColorWell?
    private weak var opacitySlider: NSSlider?
    private weak var opacityLabel: NSTextField?
    private weak var showLabelCheckbox: NSButton?
    private weak var lingerPopup: NSPopUpButton?

    /// Custom gesture 리스트 컨테이너 — 추가/삭제 시 동적으로 갱신.
    private weak var customListStack: NSStackView?

    // App Filter 컨트롤
    private weak var appFilterModePopup: NSPopUpButton?
    private weak var appFilterTextView: NSTextView?

    /// Linger duration 드롭다운에 표시할 옵션
    private static let lingerOptions: [(label: String, value: Double)] = [
        ("Instant (0.2s)",   0.22),
        ("Short (0.5s)",     0.5),
        ("Medium (1.0s)",    1.0),
        ("Long (1.5s)",      1.5),
        ("Very long (2.0s)", 2.0),
    ]

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
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 880),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Customize Mouse Gestures"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = buildContent()
        w.center()
        self.window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 22, right: 28)
        root.translatesAutoresizingMaskIntoConstraints = false

        // Header
        let title = NSTextField(labelWithString: "Mouse Gesture Mappings")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(title)

        let desc = NSTextField(labelWithString:
            "Drag with right-button held in a supported browser (Chromium / WebKit), then release.")
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        root.addArrangedSubview(desc)

        // 방향별 행 (NSGridView로 정렬: 화살표 / 라벨 / 드롭다운)
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false

        for direction in GestureDirection.allCases {
            let arrowLabel = NSTextField(labelWithString: direction.arrow)
            arrowLabel.font = .systemFont(ofSize: 22, weight: .medium)
            arrowLabel.alignment = .center

            let nameLabel = NSTextField(labelWithString: direction.name)
            nameLabel.font = .systemFont(ofSize: 13)
            nameLabel.textColor = .labelColor

            let popup = makePopup(for: direction)
            popups[direction] = popup

            grid.addRow(with: [arrowLabel, nameLabel, popup])
        }

        // 컬럼 폭 가이드
        if grid.numberOfColumns > 0 {
            grid.column(at: 0).width = 36
            grid.column(at: 1).width = 80
        }

        root.addArrangedSubview(grid)

        // ── Live Overlay 섹션 ──
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true

        let overlayTitle = NSTextField(labelWithString: "Live Overlay")
        overlayTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(overlayTitle)

        let overlayDesc = NSTextField(labelWithString:
            "Customize the trail and action label that appear during the drag.")
        overlayDesc.font = .systemFont(ofSize: 11)
        overlayDesc.textColor = .secondaryLabelColor
        root.addArrangedSubview(overlayDesc)

        root.addArrangedSubview(buildOverlayGrid())

        // ── Custom Gestures 섹션 ──
        let separator2 = NSBox()
        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(separator2)
        separator2.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true

        let customTitle = NSTextField(labelWithString: "Custom Gestures")
        customTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(customTitle)

        let customDesc = NSTextField(labelWithString:
            "Multi-segment patterns drawn by you (e.g. ←↑, ↓→). Single directions use the table above.")
        customDesc.font = .systemFont(ofSize: 11)
        customDesc.textColor = .secondaryLabelColor
        root.addArrangedSubview(customDesc)

        let addButton = NSButton(
            title: "+ Add Custom Gesture…",
            target: self,
            action: #selector(showAddGesture)
        )
        root.addArrangedSubview(addButton)

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.spacing = 4
        listStack.alignment = .leading
        listStack.translatesAutoresizingMaskIntoConstraints = false
        self.customListStack = listStack
        root.addArrangedSubview(listStack)

        refreshCustomList()

        // Custom gesture 변경 알림 구독 — Add 모달이 저장하면 즉시 리스트 갱신
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshCustomList),
            name: .customGesturesChanged,
            object: nil
        )

        // ── Application Filter 섹션 ──
        let separator3 = NSBox()
        separator3.boxType = .separator
        separator3.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(separator3)
        separator3.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true

        let filterTitle = NSTextField(labelWithString: "Application Filter")
        filterTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(filterTitle)

        let filterDesc = NSTextField(labelWithString:
            "Limit which apps the right-click on mouse-up conversion applies to.")
        filterDesc.font = .systemFont(ofSize: 11)
        filterDesc.textColor = .secondaryLabelColor
        root.addArrangedSubview(filterDesc)

        // Mode 드롭다운
        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        modeRow.spacing = 12
        modeRow.alignment = .centerY

        let modeLabel = NSTextField(labelWithString: "Mode:")
        modeLabel.font = .systemFont(ofSize: 13)
        modeRow.addArrangedSubview(modeLabel)

        let modePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        for m in AppFilterMode.allCases {
            modePopup.addItem(withTitle: m.label)
        }
        if let idx = AppFilterMode.allCases.firstIndex(of: AppFilter.mode) {
            modePopup.selectItem(at: idx)
        }
        modePopup.target = self
        modePopup.action = #selector(appFilterModeChanged(_:))
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        self.appFilterModePopup = modePopup
        modeRow.addArrangedSubview(modePopup)
        root.addArrangedSubview(modeRow)

        // Patterns 텍스트 영역
        let patternsLabel = NSTextField(labelWithString:
            "Patterns (one per line; prefix with 'regex:' for regular expression):")
        patternsLabel.font = .systemFont(ofSize: 11)
        patternsLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(patternsLabel)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 110).isActive = true
        scrollView.widthAnchor.constraint(equalToConstant: 460).isActive = true
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 110))
        textView.string = AppFilter.patternsText
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = self
        textView.minSize = NSSize(width: 0, height: 110)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: 460, height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        self.appFilterTextView = textView
        root.addArrangedSubview(scrollView)

        let helpLabel = NSTextField(labelWithString: """
        Examples:
          com.google.Chrome
          com.apple.Safari
          regex:^com\\.google\\..*
          # lines starting with '#' are comments
        """)
        helpLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        helpLabel.textColor = .tertiaryLabelColor
        root.addArrangedSubview(helpLabel)

        // Footer (Reset / Close)
        let footerSpacer = NSView()
        footerSpacer.translatesAutoresizingMaskIntoConstraints = false
        footerSpacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        root.addArrangedSubview(footerSpacer)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.alignment = .centerY

        let resetButton = NSButton(
            title: "Reset to Defaults",
            target: self,
            action: #selector(resetToDefaults)
        )
        footer.addArrangedSubview(resetButton)

        let flexible = NSView()
        flexible.translatesAutoresizingMaskIntoConstraints = false
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(flexible)

        let closeButton = NSButton(
            title: "Close",
            target: self,
            action: #selector(closeWindow)
        )
        closeButton.keyEquivalent = "\r"
        footer.addArrangedSubview(closeButton)

        // footer 너비 제약 — root 폭에 맞춰 늘어나게
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(footer)

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 0),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: 0),
        ])
        return container
    }

    private func makePopup(for direction: GestureDirection) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        for action in BrowserAction.allCases {
            popup.addItem(withTitle: action.label)
            // separator 흉내: disabled 항목 다음에 구분선 한 줄
            if action == .disabled {
                popup.menu?.addItem(NSMenuItem.separator())
            }
        }
        let current = GestureMappings.action(for: direction)
        popup.selectItem(withTitle: current.label)
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        popup.tag = direction.rawValue
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return popup
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard let direction = GestureDirection(rawValue: sender.tag),
              let title = sender.titleOfSelectedItem,
              let action = BrowserAction.allCases.first(where: { $0.label == title }) else {
            return
        }
        GestureMappings.setAction(action, for: direction)
    }

    // MARK: Live Overlay UI

    /// 4행 NSGridView: Trail color / Background color+opacity / Show label / Linger duration
    private func buildOverlayGrid() -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false

        // 1) Trail color
        let trailCW = NSColorWell()
        trailCW.color = OverlayPreferences.trailColor
        trailCW.target = self
        trailCW.action = #selector(trailColorChanged(_:))
        trailCW.translatesAutoresizingMaskIntoConstraints = false
        trailCW.widthAnchor.constraint(equalToConstant: 60).isActive = true
        trailCW.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.trailColorWell = trailCW
        grid.addRow(with: [makeFieldLabel("Trail color"), trailCW])

        // 2) Background color
        let bgCW = NSColorWell()
        bgCW.color = OverlayPreferences.backgroundColor
        bgCW.target = self
        bgCW.action = #selector(backgroundColorChanged(_:))
        bgCW.translatesAutoresizingMaskIntoConstraints = false
        bgCW.widthAnchor.constraint(equalToConstant: 60).isActive = true
        bgCW.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.backgroundColorWell = bgCW
        grid.addRow(with: [makeFieldLabel("Background color"), bgCW])

        // 3) Background opacity
        let opacityHStack = NSStackView()
        opacityHStack.orientation = .horizontal
        opacityHStack.spacing = 10
        opacityHStack.alignment = .centerY

        let slider = NSSlider(
            value: OverlayPreferences.backgroundOpacity * 100,
            minValue: 0,
            maxValue: 100,
            target: self,
            action: #selector(opacityChanged(_:))
        )
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        self.opacitySlider = slider

        let opacityValueLabel = NSTextField(labelWithString:
            "\(Int(OverlayPreferences.backgroundOpacity * 100))%")
        opacityValueLabel.font = .systemFont(ofSize: 12)
        opacityValueLabel.textColor = .secondaryLabelColor
        opacityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        opacityValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        self.opacityLabel = opacityValueLabel

        opacityHStack.addArrangedSubview(slider)
        opacityHStack.addArrangedSubview(opacityValueLabel)
        grid.addRow(with: [makeFieldLabel("Background opacity"), opacityHStack])

        // 4) Show action label
        let checkbox = NSButton(
            checkboxWithTitle: "Show action label while dragging",
            target: self,
            action: #selector(showLabelChanged(_:))
        )
        checkbox.state = OverlayPreferences.showActionLabel ? .on : .off
        self.showLabelCheckbox = checkbox
        grid.addRow(with: [makeFieldLabel("Action label"), checkbox])

        // 5) Linger duration
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        for option in Self.lingerOptions {
            popup.addItem(withTitle: option.label)
        }
        if let idx = Self.lingerOptions.firstIndex(where: {
            abs($0.value - OverlayPreferences.lingerDuration) < 0.01
        }) {
            popup.selectItem(at: idx)
        }
        popup.target = self
        popup.action = #selector(lingerChanged(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        self.lingerPopup = popup
        grid.addRow(with: [makeFieldLabel("Linger duration"), popup])

        if grid.numberOfColumns > 0 {
            grid.column(at: 0).width = 156
        }
        // 라벨 컬럼 우측 정렬
        for row in 0..<grid.numberOfRows {
            grid.cell(atColumnIndex: 0, rowIndex: row).xPlacement = .trailing
        }

        return grid
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text + ":")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.alignment = .right
        return label
    }

    @objc private func trailColorChanged(_ sender: NSColorWell) {
        OverlayPreferences.trailColor = sender.color
    }

    @objc private func backgroundColorChanged(_ sender: NSColorWell) {
        OverlayPreferences.backgroundColor = sender.color
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let value = sender.doubleValue / 100.0
        OverlayPreferences.backgroundOpacity = value
        opacityLabel?.stringValue = "\(Int(value * 100))%"
    }

    @objc private func showLabelChanged(_ sender: NSButton) {
        OverlayPreferences.showActionLabel = (sender.state == .on)
    }

    @objc private func lingerChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < Self.lingerOptions.count else { return }
        OverlayPreferences.lingerDuration = Self.lingerOptions[idx].value
    }

    // MARK: Custom Gestures UI

    /// CustomGestureMappings.all을 읽어 리스트를 다시 그린다.
    @objc private func refreshCustomList() {
        guard let stack = customListStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let all = CustomGestureMappings.all
        if all.isEmpty {
            let empty = NSTextField(labelWithString: "(no custom gestures yet)")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(empty)
            return
        }

        for (idx, def) in all.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 12
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false

            let patternLabel = NSTextField(labelWithString: def.pattern.displayString)
            patternLabel.font = .systemFont(ofSize: 18, weight: .medium)
            patternLabel.translatesAutoresizingMaskIntoConstraints = false
            patternLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
            row.addArrangedSubview(patternLabel)

            let arrow = NSTextField(labelWithString: "→")
            arrow.font = .systemFont(ofSize: 13)
            arrow.textColor = .tertiaryLabelColor
            row.addArrangedSubview(arrow)

            let actionLabel = NSTextField(labelWithString: def.action.label)
            actionLabel.font = .systemFont(ofSize: 13)
            actionLabel.translatesAutoresizingMaskIntoConstraints = false
            actionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
            row.addArrangedSubview(actionLabel)

            let removeButton = NSButton(
                title: "Remove",
                target: self,
                action: #selector(removeCustomGesture(_:))
            )
            removeButton.bezelStyle = .roundRect
            removeButton.controlSize = .small
            removeButton.tag = idx
            row.addArrangedSubview(removeButton)

            stack.addArrangedSubview(row)
        }
    }

    @objc private func showAddGesture() {
        AddGestureController.shared.show()
    }

    @objc private func removeCustomGesture(_ sender: NSButton) {
        let all = CustomGestureMappings.all
        let idx = sender.tag
        guard idx >= 0, idx < all.count else { return }
        CustomGestureMappings.remove(pattern: all[idx].pattern)
        refreshCustomList()
    }

    // MARK: Reset

    @objc private func resetToDefaults() {
        GestureMappings.resetToDefaults()
        OverlayPreferences.resetToDefaults()
        CustomGestureMappings.resetAll()
        AppFilter.resetToDefaults()
        // 매핑 popup 갱신
        for (direction, popup) in popups {
            let current = GestureMappings.action(for: direction)
            popup.selectItem(withTitle: current.label)
        }
        // 오버레이 컨트롤 갱신
        trailColorWell?.color = OverlayPreferences.trailColor
        backgroundColorWell?.color = OverlayPreferences.backgroundColor
        let opacity = OverlayPreferences.backgroundOpacity
        opacitySlider?.doubleValue = opacity * 100
        opacityLabel?.stringValue = "\(Int(opacity * 100))%"
        showLabelCheckbox?.state = OverlayPreferences.showActionLabel ? .on : .off
        if let idx = Self.lingerOptions.firstIndex(where: {
            abs($0.value - OverlayPreferences.lingerDuration) < 0.01
        }) {
            lingerPopup?.selectItem(at: idx)
        }
        // App Filter 컨트롤 갱신
        if let idx = AppFilterMode.allCases.firstIndex(of: AppFilter.mode) {
            appFilterModePopup?.selectItem(at: idx)
        }
        appFilterTextView?.string = AppFilter.patternsText
        refreshCustomList()
    }

    // MARK: App Filter handlers

    @objc private func appFilterModeChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < AppFilterMode.allCases.count else { return }
        AppFilter.mode = AppFilterMode.allCases[idx]
    }

    /// NSTextViewDelegate — 패턴 텍스트가 변경될 때마다 즉시 영속화.
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView,
              tv === appFilterTextView else { return }
        AppFilter.patternsText = tv.string
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // 메뉴바 앱이라 .accessory 활성 정책 그대로 유지
    }
}

// MARK: - Add Custom Gesture (drawing modal)

/// 사용자가 빈 영역에서 드래그해서 패턴을 직접 입력하고 액션을 선택해 등록하는 모달.
/// 패턴은 PathAnalyzer로 즉시 추출해 표시되며, 저장 시 CustomGestureMappings에 영속화한다.
