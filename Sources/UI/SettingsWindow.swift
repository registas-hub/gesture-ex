import AppKit

/// 설정 윈도우의 좌측 사이드바에 표시할 그룹.
/// 새 카테고리를 추가하려면 case 추가 + buildPage(for:) 분기 + sidebar 셀 텍스트만 추가하면 된다.
private enum SettingsSection: Int, CaseIterable {
    case mappings
    case overlay
    case gestureApps
    case appFilter

    var label: String {
        switch self {
        case .mappings:    return "Gesture Mappings"
        case .overlay:     return "Live Overlay"
        case .gestureApps: return "Gesture Apps"
        case .appFilter:   return "Mouse-up Apps"
        }
    }

    /// macOS SF Symbol 이름 (사이드바 아이콘용).
    var symbolName: String {
        switch self {
        case .mappings:    return "arrow.up.and.down.and.arrow.left.and.right"
        case .overlay:     return "paintbrush"
        case .gestureApps: return "app.badge.checkmark"
        case .appFilter:   return "app.badge"
        }
    }
}

/// 공유 bundle-ID pattern 필터 페이지가 어느 storage를 다루는지 식별.
/// chooseApp 버튼·mode popup의 sender.tag로 dispatch한다.
private enum BundleFilterTarget: Int {
    case appFilter = 0       // Mouse-up Apps
    case gestureFilter = 1   // Gesture Apps
}

final class SettingsWindow: NSObject,
                             NSWindowDelegate,
                             NSTextViewDelegate,
                             NSTableViewDataSource,
                             NSTableViewDelegate {
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

    // App Filter (Mouse-up Apps) 컨트롤
    private weak var appFilterModePopup: NSPopUpButton?
    private weak var appFilterTextView: NSTextView?

    // Gesture App Filter (Gesture Apps) 컨트롤 — Mouse-up Apps와 동일 패턴, 다른 storage
    private weak var gestureFilterModePopup: NSPopUpButton?
    private weak var gestureFilterTextView: NSTextView?

    // 사이드바/페이지 컨테이너
    private weak var sidebarTable: NSTableView?
    private weak var pagesTabView: NSTabView?

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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Config"
        w.minSize = NSSize(width: 640, height: 520)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = buildContent()
        w.center()
        self.window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Top-level layout

    /// Window content =  [ Split (sidebar | pages) ]  +  [ footer ]  세로 스택.
    private func buildContent() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let split = buildSplitView()
        let footer = buildFooter()

        container.addSubview(split)
        container.addSubview(footer)

        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: container.topAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            footer.heightAnchor.constraint(equalToConstant: 32),
        ])

        return container
    }

    /// 좌측 사이드바(NSTableView) + 우측 NSTabView를 가진 horizontal split.
    private func buildSplitView() -> NSSplitView {
        let split = NSSplitView()
        split.dividerStyle = .thin
        split.isVertical = true
        split.translatesAutoresizingMaskIntoConstraints = false

        split.addArrangedSubview(buildSidebar())
        split.addArrangedSubview(buildPagesTabView())
        split.setHoldingPriority(.init(260), forSubviewAt: 0)
        return split
    }

    /// SF Symbol + 라벨 셀로 구성된 source-list 스타일 NSTableView.
    private func buildSidebar() -> NSView {
        let table = NSTableView()
        table.headerView = nil
        if #available(macOS 11.0, *) {
            table.style = .sourceList
        } else {
            table.selectionHighlightStyle = .sourceList
        }
        table.rowSizeStyle = .default
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.usesAutomaticRowHeights = false
        table.rowHeight = 28
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        self.sidebarTable = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        scroll.widthAnchor.constraint(lessThanOrEqualToConstant: 240).isActive = true

        // 사이드바 배경에 source-list 톤을 입혀 표준 macOS 룩과 가깝게 만든다.
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .followsWindowActiveState
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -8),
        ])

        // 첫 진입 시 첫 섹션 자동 선택
        DispatchQueue.main.async {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        return visualEffect
    }

    /// 4개 페이지를 가진 tabless NSTabView.
    private func buildPagesTabView() -> NSView {
        let tab = NSTabView()
        tab.tabViewType = .noTabsNoBorder
        tab.translatesAutoresizingMaskIntoConstraints = false

        for section in SettingsSection.allCases {
            let item = NSTabViewItem(identifier: section.rawValue)
            item.label = section.label
            item.view = buildPage(for: section)
            tab.addTabViewItem(item)
        }
        self.pagesTabView = tab
        return tab
    }

    private func buildFooter() -> NSStackView {
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false

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

        return footer
    }

    // MARK: - Page builders

    /// 단일 페이지 컨테이너. body(NSStackView)를 top-leading 정렬로 고정.
    /// 모든 페이지 콘텐츠가 윈도우 minSize(640×520) 안에 들어가므로 NSScrollView 미사용.
    private func buildPage(for section: SettingsSection) -> NSView {
        let body: NSStackView
        switch section {
        case .mappings:    body = buildMappingsBody()
        case .overlay:     body = buildOverlayBody()
        case .gestureApps: body = buildGestureAppsBody()
        case .appFilter:   body = buildAppFilterBody()
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            body.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
        ])
        return container
    }

    /// 모든 페이지가 공유하는 vertical stack + title + description prelude.
    private func makePageStack(title: String, description: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(makeSectionTitle(title))
        stack.addArrangedSubview(makeSectionDescription(description))
        return stack
    }

    /// 4-direction gesture mapping + custom gestures를 함께 보여주는 페이지.
    private func buildMappingsBody() -> NSStackView {
        let stack = makePageStack(
            title: "Mouse Gesture Mappings",
            description: "Drag with right-button held in a supported browser (Chromium / WebKit), then release."
        )

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

        if grid.numberOfColumns > 0 {
            grid.column(at: 0).width = 36
            grid.column(at: 1).width = 80
        }

        stack.addArrangedSubview(grid)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true
        stack.addArrangedSubview(divider)

        appendCustomGesturesSection(to: stack)
        return stack
    }

    /// Live Overlay 페이지.
    private func buildOverlayBody() -> NSStackView {
        let stack = makePageStack(
            title: "Live Overlay",
            description: "Customize the trail and action label that appear during the drag."
        )
        stack.addArrangedSubview(buildOverlayGrid())
        return stack
    }

    /// Mappings 페이지 하단에 붙는 Custom Gestures sub-section.
    private func appendCustomGesturesSection(to stack: NSStackView) {
        let title = NSTextField(labelWithString: "Custom Gestures")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(title)

        let desc = NSTextField(wrappingLabelWithString:
            "Multi-segment patterns drawn by you (e.g. ←↑, ↓→).")
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        desc.preferredMaxLayoutWidth = 460
        stack.addArrangedSubview(desc)

        let addButton = NSButton(
            title: "+ Add Custom Gesture…",
            target: self,
            action: #selector(showAddGesture)
        )
        stack.addArrangedSubview(addButton)

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.spacing = 4
        listStack.alignment = .leading
        listStack.translatesAutoresizingMaskIntoConstraints = false
        self.customListStack = listStack
        stack.addArrangedSubview(listStack)

        refreshCustomList()

        // Custom gesture 변경 알림 구독 — Add 모달이 저장하면 즉시 리스트 갱신.
        // 윈도우가 매번 새로 생성되지 않으므로(공유 인스턴스) addObserver 중복 방지를 위해 먼저 제거.
        NotificationCenter.default.removeObserver(
            self,
            name: .customGesturesChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshCustomList),
            name: .customGesturesChanged,
            object: nil
        )
    }

    /// Right-click on mouse-up 변환의 적용 대상 앱 설정 페이지.
    private func buildAppFilterBody() -> NSStackView {
        return buildBundleIDFilterPage(
            title: "Apps for Right-click on Mouse-up",
            description: "Choose which apps the right-click on mouse-up conversion applies to. By default it runs in every app.",
            target: .appFilter,
            initialMode: AppFilter.mode,
            initialPatterns: AppFilter.patternsText,
            storeModePopup: { [weak self] in self?.appFilterModePopup = $0 },
            storeTextView: { [weak self] in self?.appFilterTextView = $0 }
        )
    }

    /// 마우스 제스처 인식의 적용 대상 앱 설정 페이지.
    private func buildGestureAppsBody() -> NSStackView {
        return buildBundleIDFilterPage(
            title: "Apps for Mouse Gestures",
            description: """
            Choose which apps fire mouse gestures. \
            All apps mode (default): gestures run in every supported browser only. \
            Whitelist: gestures run ONLY in the listed apps — non-browsers included, engine check is bypassed. \
            Blacklist: gestures run in every supported browser except the listed ones. \
            Note: in non-browser apps the gesture actions still fire keyboard shortcuts (⌘[, ⌘R, …) which may have different meanings.
            """,
            target: .gestureFilter,
            initialMode: GestureAppFilter.mode,
            initialPatterns: GestureAppFilter.patternsText,
            storeModePopup: { [weak self] in self?.gestureFilterModePopup = $0 },
            storeTextView: { [weak self] in self?.gestureFilterTextView = $0 }
        )
    }

    /// Mouse-up Apps와 Gesture Apps가 공유하는 bundle ID pattern filter 페이지 빌더.
    /// storage는 sender.tag(BundleFilterTarget)로 dispatch한다.
    private func buildBundleIDFilterPage(
        title: String,
        description: String,
        target: BundleFilterTarget,
        initialMode: AppFilterMode,
        initialPatterns: String,
        storeModePopup: (NSPopUpButton) -> Void,
        storeTextView: (NSTextView) -> Void
    ) -> NSStackView {
        let stack = makePageStack(title: title, description: description)

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
        if let idx = AppFilterMode.allCases.firstIndex(of: initialMode) {
            modePopup.selectItem(at: idx)
        }
        modePopup.target = self
        modePopup.action = #selector(bundleFilterModeChanged(_:))
        modePopup.tag = target.rawValue
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        storeModePopup(modePopup)
        modeRow.addArrangedSubview(modePopup)
        stack.addArrangedSubview(modeRow)

        let patternsRow = NSStackView()
        patternsRow.orientation = .horizontal
        patternsRow.alignment = .centerY
        patternsRow.spacing = 8

        let patternsLabel = NSTextField(labelWithString:
            "Patterns (one per line; prefix with 'regex:' for regular expression):")
        patternsLabel.font = .systemFont(ofSize: 11)
        patternsLabel.textColor = .secondaryLabelColor
        patternsRow.addArrangedSubview(patternsLabel)

        let chooseAppButton = NSButton(
            title: "Choose App…",
            target: self,
            action: #selector(bundleFilterChooseApp(_:))
        )
        chooseAppButton.bezelStyle = .roundRect
        chooseAppButton.controlSize = .small
        chooseAppButton.tag = target.rawValue
        patternsRow.addArrangedSubview(chooseAppButton)
        stack.addArrangedSubview(patternsRow)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 140).isActive = true
        scrollView.widthAnchor.constraint(equalToConstant: 460).isActive = true
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 140))
        textView.string = initialPatterns
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = self
        textView.minSize = NSSize(width: 0, height: 140)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: 460, height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        storeTextView(textView)
        stack.addArrangedSubview(scrollView)

        let helpLabel = NSTextField(labelWithString: """
        Examples:
          com.google.Chrome
          com.apple.Safari
          regex:^com\\.google\\..*
          # lines starting with '#' are comments
        """)
        helpLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        helpLabel.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(helpLabel)

        return stack
    }

    // MARK: - Common UI helpers

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }

    private func makeSectionDescription(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 460
        return label
    }

    private func makePopup(for direction: GestureDirection) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        for action in BrowserAction.allCases {
            let item = NSMenuItem(title: action.menuTitle, action: nil, keyEquivalent: "")
            item.representedObject = action
            popup.menu?.addItem(item)
            // separator 흉내: disabled 항목 다음에 구분선 한 줄
            if action == .disabled {
                popup.menu?.addItem(NSMenuItem.separator())
            }
        }
        Self.selectAction(GestureMappings.action(for: direction), in: popup)
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        popup.tag = direction.rawValue
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        return popup
    }

    /// representedObject 기반으로 BrowserAction에 해당하는 메뉴 항목을 선택한다.
    /// menuTitle이 라벨+단축키 조합이라 title 매칭이 더 이상 안전하지 않으므로 representedObject를 사용.
    private static func selectAction(_ action: BrowserAction, in popup: NSPopUpButton) {
        if let idx = popup.menu?.items.firstIndex(where: {
            ($0.representedObject as? BrowserAction) == action
        }) {
            popup.selectItem(at: idx)
        }
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard let direction = GestureDirection(rawValue: sender.tag),
              let action = sender.selectedItem?.representedObject as? BrowserAction else {
            return
        }
        GestureMappings.setAction(action, for: direction)
    }

    // MARK: - Live Overlay grid

    /// 5행 NSGridView: Trail color / Background color / opacity / Show label / Linger duration
    private func buildOverlayGrid() -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false

        let trailCW = makeColorWell(initial: OverlayPreferences.trailColor,
                                     action: #selector(trailColorChanged(_:)))
        self.trailColorWell = trailCW
        grid.addRow(with: [makeFieldLabel("Trail color"), trailCW])

        let bgCW = makeColorWell(initial: OverlayPreferences.backgroundColor,
                                  action: #selector(backgroundColorChanged(_:)))
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

    private func makeColorWell(initial: NSColor, action: Selector) -> NSColorWell {
        let cw = NSColorWell()
        cw.color = initial
        cw.target = self
        cw.action = action
        cw.translatesAutoresizingMaskIntoConstraints = false
        cw.widthAnchor.constraint(equalToConstant: 60).isActive = true
        cw.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return cw
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

    // MARK: - Custom Gestures handlers

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

            let editButton = NSButton(
                title: "Edit",
                target: self,
                action: #selector(editCustomGesture(_:))
            )
            editButton.bezelStyle = .roundRect
            editButton.controlSize = .small
            editButton.tag = idx
            row.addArrangedSubview(editButton)

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

    @objc private func editCustomGesture(_ sender: NSButton) {
        let all = CustomGestureMappings.all
        let idx = sender.tag
        guard idx >= 0, idx < all.count else { return }
        AddGestureController.shared.show(editing: all[idx])
    }

    @objc private func removeCustomGesture(_ sender: NSButton) {
        let all = CustomGestureMappings.all
        let idx = sender.tag
        guard idx >= 0, idx < all.count else { return }
        CustomGestureMappings.remove(pattern: all[idx].pattern)
        refreshCustomList()
    }

    // MARK: - Reset

    @objc private func resetToDefaults() {
        GestureMappings.resetToDefaults()
        OverlayPreferences.resetToDefaults()
        CustomGestureMappings.resetAll()
        AppFilter.resetToDefaults()
        GestureAppFilter.resetToDefaults()
        // 매핑 popup 갱신
        for (direction, popup) in popups {
            Self.selectAction(GestureMappings.action(for: direction), in: popup)
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
        // Bundle ID filter 컨트롤 갱신 (Mouse-up Apps · Gesture Apps 둘 다)
        if let idx = AppFilterMode.allCases.firstIndex(of: AppFilter.mode) {
            appFilterModePopup?.selectItem(at: idx)
        }
        appFilterTextView?.string = AppFilter.patternsText
        if let idx = AppFilterMode.allCases.firstIndex(of: GestureAppFilter.mode) {
            gestureFilterModePopup?.selectItem(at: idx)
        }
        gestureFilterTextView?.string = GestureAppFilter.patternsText
        refreshCustomList()
    }

    // MARK: - Bundle ID filter handlers (Mouse-up Apps · Gesture Apps)

    @objc private func bundleFilterModeChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < AppFilterMode.allCases.count else { return }
        let mode = AppFilterMode.allCases[idx]
        switch BundleFilterTarget(rawValue: sender.tag) {
        case .appFilter:     AppFilter.mode = mode
        case .gestureFilter: GestureAppFilter.mode = mode
        case .none:          break
        }
    }

    /// NSOpenPanel로 .app 번들을 선택받아 bundle ID를 패턴 목록에 추가한다.
    /// sender.tag로 어느 필터(Mouse-up Apps / Gesture Apps)에 추가할지 결정한다.
    @objc private func bundleFilterChooseApp(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.prompt = "Add"
        panel.allowedFileTypes = ["app"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Could not read bundle identifier"
            alert.informativeText =
                "The selected file does not appear to be a valid application bundle."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        guard let target = BundleFilterTarget(rawValue: sender.tag) else { return }
        appendFilterPattern(bundleID, to: target)
    }

    /// 패턴 텍스트 끝에 한 줄 추가. 동일 패턴이 이미 있으면 추가하지 않는다.
    private func appendFilterPattern(_ pattern: String, to target: BundleFilterTarget) {
        let currentText: String
        switch target {
        case .appFilter:     currentText = AppFilter.patternsText
        case .gestureFilter: currentText = GestureAppFilter.patternsText
        }
        var text = currentText
        let alreadyExists = text
            .split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespaces) == pattern }
        if alreadyExists { return }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += pattern + "\n"
        switch target {
        case .appFilter:
            AppFilter.patternsText = text
            appFilterTextView?.string = text
        case .gestureFilter:
            GestureAppFilter.patternsText = text
            gestureFilterTextView?.string = text
        }
    }

    /// NSTextViewDelegate — 패턴 텍스트가 변경될 때마다 즉시 영속화.
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        if tv === appFilterTextView {
            AppFilter.patternsText = tv.string
        } else if tv === gestureFilterTextView {
            GestureAppFilter.patternsText = tv.string
        }
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // 메뉴바 앱이라 .accessory 활성 정책 그대로 유지
    }

    // MARK: - NSTableViewDataSource / NSTableViewDelegate (sidebar)

    func numberOfRows(in tableView: NSTableView) -> Int {
        return SettingsSection.allCases.count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let section = SettingsSection.allCases[row]
        let cell = NSTableCellView()

        let text = NSTextField(labelWithString: section.label)
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        text.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: section.symbolName,
                             accessibilityDescription: section.label)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)
        cell.addSubview(text)
        cell.imageView = icon
        cell.textField = text

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView,
              table === sidebarTable,
              let tab = pagesTabView else { return }
        let row = table.selectedRow
        guard row >= 0, row < SettingsSection.allCases.count else { return }
        tab.selectTabViewItem(at: row)
    }
}

// MARK: - Add Custom Gesture (drawing modal)

/// 사용자가 빈 영역에서 드래그해서 패턴을 직접 입력하고 액션을 선택해 등록하는 모달.
/// 패턴은 PathAnalyzer로 즉시 추출해 표시되며, 저장 시 CustomGestureMappings에 영속화한다.
