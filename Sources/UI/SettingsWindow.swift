import AppKit
import Carbon.HIToolbox  // kVK_Escape

/// 설정 윈도우의 좌측 사이드바에 표시할 그룹.
/// 새 카테고리를 추가하려면 case 추가 + buildPage(for:) 분기 + sidebar 셀 텍스트만 추가하면 된다.
private enum SettingsSection: Int, CaseIterable {
    case mappings
    case overlay
    case gestureApps
    case browsers
    case appFilter
    case shortcut
    case capture

    var label: String {
        switch self {
        case .mappings:    return "Gestures"
        case .overlay:     return "Overlay"
        case .gestureApps: return "Gesture Apps"
        case .browsers:    return "Browsers"
        case .appFilter:   return "Right-click Apps"
        case .shortcut:    return "Shortcut"
        case .capture:     return "Capture"
        }
    }

    /// macOS SF Symbol 이름 (사이드바 아이콘용).
    var symbolName: String {
        switch self {
        case .mappings:    return "arrow.up.and.down.and.arrow.left.and.right"
        case .overlay:     return "paintbrush"
        case .gestureApps: return "app.badge.checkmark"
        case .browsers:    return "safari"
        case .appFilter:   return "app.badge"
        case .shortcut:    return "command"
        case .capture:     return "camera.viewfinder"
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

    // Shortcut 페이지 — Reset 시 갱신을 위해 보유.
    private weak var shortcutEnableCheckbox: NSButton?
    private weak var shortcutBindingLabel: NSTextField?
    private weak var shortcutRecordButton: NSButton?
    private weak var shortcutStatusLabel: NSTextField?

    /// 글로벌 hotkey 녹화 모드 시 활성된 NSEvent monitor.
    private var hotkeyKeyMonitor: Any?

    // Live Overlay 컨트롤 — reset 시 갱신을 위해 보유
    private weak var trailColorWell: NSColorWell?
    private weak var backgroundColorWell: NSColorWell?
    private weak var opacitySlider: NSSlider?
    private weak var opacityLabel: NSTextField?
    private weak var showLabelCheckbox: NSButton?
    private weak var lingerPopup: NSPopUpButton?

    // Capture 컨트롤 — reset / 외부 변경 알림 시 갱신을 위해 보유.
    private weak var captureClipboardCheckbox: NSButton?
    private weak var captureDesktopCheckbox: NSButton?
    private weak var captureCustomPathCheckbox: NSButton?
    private weak var captureFormatPopup: NSPopUpButton?
    private weak var captureQualitySlider: NSSlider?
    private weak var captureQualityLabel: NSTextField?
    private weak var captureCustomPathLabel: NSTextField?
    private weak var captureClearPathButton: NSButton?

    /// Custom gesture 리스트 컨테이너 — 추가/삭제 시 동적으로 갱신.
    private weak var customListStack: NSStackView?

    /// 두 bundle filter 페이지(Right-click Apps / Gesture Apps)가 보여주는 컨트롤들의 weak 참조 묶음.
    /// ivars 4개를 페이지마다 따로 두면 Reset / 변경 알림 처리에서 호출부가 N배로 늘어나므로
    /// 한 struct로 묶어 BundleFilterTarget 별로 1쌍씩 보관한다.
    private struct BundleFilterControls {
        weak var modePopup: NSPopUpButton?
        weak var textView: NSTextView?
        weak var advancedStack: NSStackView?
        weak var disclosure: NSButton?
    }

    private var appFilterControls = BundleFilterControls()
    private var gestureFilterControls = BundleFilterControls()

    /// Browser List 체크박스. Reset to Defaults 시 일괄 갱신용으로 보관.
    private var browserCheckboxes: [NSButton] = []

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
        table.style = .sourceList
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

    /// `SettingsSection.allCases` 수만큼의 페이지를 가진 tabless NSTabView.
    /// 사이드바 행과 1:1 매칭되며 사이드바 선택 변경 시 `selectTabViewItem(at:)`으로 동기화한다.
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
            action: #selector(resetToDefaultsRequested)
        )
        if #available(macOS 12.0, *) {
            resetButton.hasDestructiveAction = true
        }
        resetButton.contentTintColor = .systemRed
        footer.addArrangedSubview(resetButton)

        let importButton = NSButton(
            title: "Import…",
            target: self,
            action: #selector(importConfigRequested)
        )
        footer.addArrangedSubview(importButton)

        let exportButton = NSButton(
            title: "Export…",
            target: self,
            action: #selector(exportConfigRequested)
        )
        footer.addArrangedSubview(exportButton)

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
    ///
    /// container는 NSTabViewItem.view로 들어가는데, NSTabView는 자식 뷰를 autoresizing
    /// mask로 사이즈맞춤하지 *autolayout 제약을 자동으로 만들어 주지 않는다.* 그래서
    /// `translatesAutoresizingMaskIntoConstraints = false`인 채로 두면 container의 frame이
    /// 미정 상태가 되어 안쪽 body가 (0,0) 근방으로 몰리며 모든 페이지의 컨트롤이 겹쳐 보인다.
    /// 따라서 container는 autoresizing 기반으로 두고, body만 autolayout으로 container에 핀한다.
    private func buildPage(for section: SettingsSection) -> NSView {
        let body: NSStackView
        switch section {
        case .mappings:    body = buildMappingsBody()
        case .overlay:     body = buildOverlayBody()
        case .gestureApps: body = buildGestureAppsBody()
        case .browsers:    body = buildBrowsersBody()
        case .appFilter:   body = buildAppFilterBody()
        case .shortcut:    body = buildShortcutBody()
        case .capture:     body = buildCaptureBody()
        }

        let container = NSView()
        container.autoresizingMask = [.width, .height]
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
    /// 두 섹션을 각각 카드(NSBox)로 감싸 Common Region 신호를 강화한다 —
    /// 사용자가 "이 그리드는 4-direction 매핑, 저 리스트는 custom 영역"으로 자동 분리 인식.
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

        stack.addArrangedSubview(makeCard(title: "4-Direction Mappings", content: grid))
        stack.addArrangedSubview(makeCard(title: "Custom Gestures", content: buildCustomGesturesContent()))
        return stack
    }

    /// 페이지 안의 sub-section을 둘러싸는 카드 컨테이너.
    /// 미묘한 테두리·배경으로 Common Region 신호를 만들어 그룹을 시각적으로 구분한다.
    /// 카드 간 spacing은 부모 stack의 spacing에 의존(기본 14) — 그룹 간 간격이 그룹 내 간격보다 크다.
    ///
    /// 주의: 기존 구현은 NSBox(.primary) + box.contentView = NSStackView 패턴이었으나
    /// 최근 macOS에서 NSBox가 autolayout view를 contentView로 받을 때 frame을 관리해 주지 않아
    /// 안쪽 컨트롤이 페이지 좌상단(0,0)에 떨어져 헤더와 겹치는 문제가 발생한다 — autolayout
    /// 기반 NSView로 직접 그린다.
    private func makeCard(title: String, content: NSView) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.cornerRadius = 6

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -12),

            content.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 480),
        ])
        return card
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

    /// Custom Gestures 카드 안에 들어갈 수직 스택.
    /// description → Add 버튼 → 리스트 순서. 카드 frame은 makeCard가 그린다.
    private func buildCustomGesturesContent() -> NSView {
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false

        let desc = NSTextField(wrappingLabelWithString:
            "Multi-segment patterns drawn by you (e.g. ←↑, ↓→).")
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        desc.preferredMaxLayoutWidth = 460
        inner.addArrangedSubview(desc)

        let addButton = NSButton(
            title: "+ Add Custom Gesture…",
            target: self,
            action: #selector(showAddGesture)
        )
        inner.addArrangedSubview(addButton)

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.spacing = 4
        listStack.alignment = .leading
        listStack.translatesAutoresizingMaskIntoConstraints = false
        self.customListStack = listStack
        inner.addArrangedSubview(listStack)

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

        return inner
    }

    /// Right-click on mouse-up 변환의 적용 대상 앱 설정 페이지.
    private func buildAppFilterBody() -> NSStackView {
        let result = buildBundleIDFilterPage(
            title: "Apps for Right-click on Mouse-up",
            description: "Choose which apps the right-click on mouse-up conversion applies to. By default it runs in every app.",
            target: .appFilter,
            initialMode: AppFilter.mode,
            initialPatterns: AppFilter.patternsText
        )
        appFilterControls = result.controls
        return result.view
    }

    /// 글로벌 hotkey 커스터마이징 페이지.
    /// 기본값은 ⌥⌘G — 다른 앱과 충돌하면 사용자가 임의 키로 변경하거나 hotkey를 끌 수 있다.
    private func buildShortcutBody() -> NSStackView {
        let stack = makePageStack(
            title: "Global Shortcut",
            description:
                "Customize the global hotkey that toggles right-click on mouse-up. " +
                "If the default conflicts with another app, record a new combination or disable the shortcut entirely."
        )

        // Enable 체크박스
        let enableCb = NSButton(
            checkboxWithTitle: "Enable global shortcut",
            target: self,
            action: #selector(shortcutEnableChanged(_:))
        )
        enableCb.state = HotkeyPreferences.isEnabled ? .on : .off
        self.shortcutEnableCheckbox = enableCb
        stack.addArrangedSubview(enableCb)

        // 현재 바인딩 + Record/Default 버튼
        let bindingRow = NSStackView()
        bindingRow.orientation = .horizontal
        bindingRow.spacing = 12
        bindingRow.alignment = .centerY
        bindingRow.translatesAutoresizingMaskIntoConstraints = false

        let head = NSTextField(labelWithString: "Shortcut:")
        head.font = .systemFont(ofSize: 13)
        head.textColor = .secondaryLabelColor
        bindingRow.addArrangedSubview(head)

        let label = NSTextField(labelWithString: HotkeyPreferences.binding.displayString)
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.shortcutBindingLabel = label
        bindingRow.addArrangedSubview(label)

        let recordButton = NSButton(
            title: "Record",
            target: self,
            action: #selector(shortcutRecordTapped)
        )
        self.shortcutRecordButton = recordButton
        bindingRow.addArrangedSubview(recordButton)

        let defaultButton = NSButton(
            title: "Use Default (⌥⌘G)",
            target: self,
            action: #selector(shortcutUseDefaultTapped)
        )
        bindingRow.addArrangedSubview(defaultButton)

        stack.addArrangedSubview(bindingRow)

        // Status 라벨 — 등록 충돌/비활성 상태를 사용자에게 알린다.
        let status = NSTextField(wrappingLabelWithString: " ")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.preferredMaxLayoutWidth = 460
        self.shortcutStatusLabel = status
        stack.addArrangedSubview(status)

        // SettingsWindow 싱글톤이고 buildShortcutBody는 build 시 1회만 호출되므로
        // 옵저버 해제는 불필요.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshShortcutUI),
            name: .toggleHotkeyChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyRegistrationResult(_:)),
            name: .toggleHotkeyRegistrationResult,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.refreshShortcutUI()
        }

        return stack
    }

    /// 등록 결과 알림 처리 — 다른 앱과 충돌해 실패하면 빨간 경고를 status 라벨에 표시.
    @objc private func handleHotkeyRegistrationResult(_ note: Notification) {
        guard hotkeyKeyMonitor == nil else { return }   // 녹화 중엔 라벨을 건드리지 않음
        let ok = (note.userInfo?["ok"] as? Bool) ?? true
        guard !ok else {
            // 성공 시엔 refreshShortcutUI가 정상 메시지를 채운다.
            return
        }
        shortcutStatusLabel?.stringValue =
            "This shortcut is already in use by another app. Choose a different combination."
        shortcutStatusLabel?.textColor = .systemRed
    }

    /// 현재 HotkeyPreferences를 읽어 페이지 컨트롤들을 동기화.
    @objc private func refreshShortcutUI() {
        let binding = HotkeyPreferences.binding
        let enabled = HotkeyPreferences.isEnabled
        shortcutEnableCheckbox?.state = enabled ? .on : .off
        shortcutBindingLabel?.stringValue = binding.displayString
        shortcutBindingLabel?.textColor = enabled ? .labelColor : .tertiaryLabelColor

        // 녹화 진행 중이 아니면 status 메시지를 갱신.
        if hotkeyKeyMonitor != nil { return }
        if !enabled {
            shortcutStatusLabel?.stringValue = "Shortcut is disabled. The menu bar toggle still works."
            shortcutStatusLabel?.textColor = .secondaryLabelColor
        } else {
            shortcutStatusLabel?.stringValue = "Press Record and then your desired key combination. Esc cancels."
            shortcutStatusLabel?.textColor = .secondaryLabelColor
        }
    }

    @objc private func shortcutEnableChanged(_ sender: NSButton) {
        HotkeyPreferences.isEnabled = (sender.state == .on)
    }

    @objc private func shortcutUseDefaultTapped() {
        HotkeyPreferences.binding = HotkeyPreferences.defaultBinding
    }

    @objc private func shortcutRecordTapped() {
        if hotkeyKeyMonitor != nil {
            stopRecordingHotkey()
        } else {
            startRecordingHotkey()
        }
    }

    private func startRecordingHotkey() {
        removeHotkeyMonitor()

        shortcutRecordButton?.title = "Press keys…"
        shortcutBindingLabel?.stringValue = "…"
        shortcutStatusLabel?.stringValue = "Press the new shortcut, or Esc to cancel."
        shortcutStatusLabel?.textColor = .secondaryLabelColor

        hotkeyKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == UInt16(kVK_Escape)
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.stopRecordingHotkey()
                return nil
            }
            guard let shortcut = KeyShortcut.from(event: event) else { return nil }
            // modifier-less 단축키는 거부 — 글로벌 등록 시 시스템 전역 키 입력을 가로채
            // 사용자가 자기 발등을 찍는다. 녹화는 계속해 사용자가 수정 키를 추가할 기회를 준다.
            guard shortcut.hasModifier else {
                self.shortcutBindingLabel?.stringValue = shortcut.displayString
                self.shortcutStatusLabel?.stringValue =
                    "A shortcut must include at least one modifier (⌘ ⌥ ⌃ ⇧). Press again with a modifier."
                self.shortcutStatusLabel?.textColor = .systemOrange
                return nil
            }
            self.stopRecordingHotkey()
            HotkeyPreferences.binding = shortcut
            return nil
        }
    }

    private func stopRecordingHotkey() {
        removeHotkeyMonitor()
        shortcutRecordButton?.title = "Record"
        refreshShortcutUI()
    }

    private func removeHotkeyMonitor() {
        guard let monitor = hotkeyKeyMonitor else { return }
        NSEvent.removeMonitor(monitor)
        hotkeyKeyMonitor = nil
    }

    // MARK: - Capture page

    /// Screen Capture 설정 페이지.
    /// CapturePreferences의 destinations / format / jpegQuality / customPath 4개 값을 노출한다.
    /// 캡처 액션은 아직 GestureAction에 연결되지 않았으나, 이 페이지는 prefs를 사용자에게 즉시 노출하여
    /// 향후 액션 연결 시 곧바로 의미 있는 기본값이 되도록 한다.
    private func buildCaptureBody() -> NSStackView {
        let stack = makePageStack(
            title: "Capture",
            description: "Configure where screenshots are saved and how they're encoded."
        )

        stack.addArrangedSubview(buildCaptureGrid())

        // 파일명 패턴 안내 — 변경 불가하므로 read-only 텍스트로 노출.
        let nameInfo = NSTextField(wrappingLabelWithString:
            "Files are saved as gesture-ex-YYYYMMDD-HHmmss.<ext>.")
        nameInfo.font = .systemFont(ofSize: 11)
        nameInfo.textColor = .secondaryLabelColor
        nameInfo.preferredMaxLayoutWidth = 460
        stack.addArrangedSubview(nameInfo)

        // SettingsWindow 싱글톤이고 buildCaptureBody는 build 시 1회만 호출되므로 옵저버 해제는 불필요.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshCaptureUI),
            name: .capturePreferencesChanged,
            object: nil
        )

        return stack
    }

    /// 4행 NSGridView: Destinations / Format / Quality / Custom path.
    private func buildCaptureGrid() -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false

        let dest = CapturePreferences.destinations

        // 1) Destinations — 3개 체크박스를 수평 스택에 묶는다. tag = OptionSet rawValue 비트.
        let destStack = NSStackView()
        destStack.orientation = .horizontal
        destStack.spacing = 16
        destStack.alignment = .centerY

        let clipboardCb = NSButton(
            checkboxWithTitle: "Clipboard",
            target: self,
            action: #selector(captureDestinationToggled(_:))
        )
        clipboardCb.tag = CaptureDestination.clipboard.rawValue
        clipboardCb.state = dest.contains(.clipboard) ? .on : .off
        self.captureClipboardCheckbox = clipboardCb
        destStack.addArrangedSubview(clipboardCb)

        let desktopCb = NSButton(
            checkboxWithTitle: "Desktop",
            target: self,
            action: #selector(captureDestinationToggled(_:))
        )
        desktopCb.tag = CaptureDestination.fileDesktop.rawValue
        desktopCb.state = dest.contains(.fileDesktop) ? .on : .off
        self.captureDesktopCheckbox = desktopCb
        destStack.addArrangedSubview(desktopCb)

        let customCb = NSButton(
            checkboxWithTitle: "Custom Path",
            target: self,
            action: #selector(captureDestinationToggled(_:))
        )
        customCb.tag = CaptureDestination.fileCustomPath.rawValue
        customCb.state = dest.contains(.fileCustomPath) ? .on : .off
        self.captureCustomPathCheckbox = customCb
        destStack.addArrangedSubview(customCb)

        grid.addRow(with: [makeFieldLabel("Save to"), destStack])

        // 2) Format
        let formatPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 26))
        formatPopup.addItem(withTitle: "PNG")
        formatPopup.addItem(withTitle: "JPEG")
        formatPopup.target = self
        formatPopup.action = #selector(captureFormatChanged(_:))
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        formatPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        let isJPEG: Bool = {
            if case .jpeg = CapturePreferences.format { return true } else { return false }
        }()
        formatPopup.selectItem(at: isJPEG ? 1 : 0)
        self.captureFormatPopup = formatPopup
        grid.addRow(with: [makeFieldLabel("Format"), formatPopup])

        // 3) JPEG quality slider + value label
        let qualityHStack = NSStackView()
        qualityHStack.orientation = .horizontal
        qualityHStack.spacing = 10
        qualityHStack.alignment = .centerY

        let quality = CapturePreferences.jpegQuality
        let qualitySlider = NSSlider(
            value: quality * 100,
            minValue: 10,
            maxValue: 100,
            target: self,
            action: #selector(captureQualityChanged(_:))
        )
        qualitySlider.isContinuous = true
        qualitySlider.isEnabled = isJPEG
        qualitySlider.translatesAutoresizingMaskIntoConstraints = false
        qualitySlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        self.captureQualitySlider = qualitySlider

        let qualityValueLabel = NSTextField(labelWithString: "\(Int(quality * 100))%")
        qualityValueLabel.font = .systemFont(ofSize: 12)
        qualityValueLabel.textColor = isJPEG ? .secondaryLabelColor : .tertiaryLabelColor
        qualityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        qualityValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        self.captureQualityLabel = qualityValueLabel

        qualityHStack.addArrangedSubview(qualitySlider)
        qualityHStack.addArrangedSubview(qualityValueLabel)
        grid.addRow(with: [makeFieldLabel("JPEG quality"), qualityHStack])

        // 4) Custom path: 라벨 + Choose / Clear 버튼.
        let pathStack = NSStackView()
        pathStack.orientation = .horizontal
        pathStack.spacing = 8
        pathStack.alignment = .centerY

        let pathLabel = NSTextField(labelWithString: customPathDisplayString())
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        self.captureCustomPathLabel = pathLabel
        pathStack.addArrangedSubview(pathLabel)

        let chooseButton = NSButton(
            title: "Choose Folder…",
            target: self,
            action: #selector(captureChooseCustomPath)
        )
        chooseButton.bezelStyle = .rounded
        pathStack.addArrangedSubview(chooseButton)

        let clearButton = NSButton(
            title: "Clear",
            target: self,
            action: #selector(captureClearCustomPath)
        )
        clearButton.bezelStyle = .rounded
        clearButton.isEnabled = (CapturePreferences.customPath != nil)
        self.captureClearPathButton = clearButton
        pathStack.addArrangedSubview(clearButton)

        grid.addRow(with: [makeFieldLabel("Custom path"), pathStack])

        if grid.numberOfColumns > 0 {
            grid.column(at: 0).width = 156
        }
        for row in 0..<grid.numberOfRows {
            grid.cell(atColumnIndex: 0, rowIndex: row).xPlacement = .trailing
        }

        return grid
    }

    /// customPath의 사용자에게 보여줄 짧은 표현. nil이면 placeholder.
    private func customPathDisplayString() -> String {
        guard let url = CapturePreferences.customPath else { return "(none)" }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    // MARK: - Capture handlers

    /// CapturePreferences를 읽어 캡처 페이지 컨트롤들을 동기화하는 단일 진입점.
    /// `.capturePreferencesChanged` 옵저버 + Reset / Import 흐름이 모두 이 메서드를 호출한다.
    @objc private func refreshCaptureUI() {
        let dest = CapturePreferences.destinations
        let onCount = [.clipboard, .fileDesktop, .fileCustomPath]
            .filter { (bit: CaptureDestination) in dest.contains(bit) }.count

        captureClipboardCheckbox?.state = dest.contains(.clipboard) ? .on : .off
        captureDesktopCheckbox?.state = dest.contains(.fileDesktop) ? .on : .off
        captureCustomPathCheckbox?.state = dest.contains(.fileCustomPath) ? .on : .off

        // 최소 1개는 반드시 켜져 있어야 한다 — 마지막 1개를 끄려는 시도를 silent revert로 막으면
        // 사용자가 클릭이 무시된 줄 오인한다. 마지막으로 남은 켠 체크박스를 비활성화하여 시도 자체를 차단한다.
        captureClipboardCheckbox?.isEnabled = !(onCount == 1 && dest.contains(.clipboard))
        captureDesktopCheckbox?.isEnabled = !(onCount == 1 && dest.contains(.fileDesktop))
        captureCustomPathCheckbox?.isEnabled = !(onCount == 1 && dest.contains(.fileCustomPath))

        let isJPEG: Bool = {
            if case .jpeg = CapturePreferences.format { return true } else { return false }
        }()
        captureFormatPopup?.selectItem(at: isJPEG ? 1 : 0)

        let quality = CapturePreferences.jpegQuality
        captureQualitySlider?.doubleValue = quality * 100
        captureQualitySlider?.isEnabled = isJPEG
        captureQualityLabel?.stringValue = "\(Int(quality * 100))%"
        captureQualityLabel?.textColor = isJPEG ? .secondaryLabelColor : .tertiaryLabelColor

        captureCustomPathLabel?.stringValue = customPathDisplayString()
        captureClearPathButton?.isEnabled = (CapturePreferences.customPath != nil)
    }

    /// 3개 destination 체크박스가 공유하는 핸들러.
    /// 마지막 1개를 끄려는 시도는 무시 — destinations가 비어 있으면 캡처가 의미를 잃는다.
    @objc private func captureDestinationToggled(_ sender: NSButton) {
        let bit = CaptureDestination(rawValue: sender.tag)
        var current = CapturePreferences.destinations

        if sender.state == .on {
            // Custom Path를 켰는데 경로가 없으면 폴더 선택 다이얼로그를 자동으로 띄운다.
            if bit == .fileCustomPath, CapturePreferences.customPath == nil {
                if !chooseCustomPathInteractive() {
                    // 사용자가 취소 — 체크박스를 다시 off로 되돌리고 끝낸다.
                    sender.state = .off
                    return
                }
            }
            current.insert(bit)
        } else {
            var next = current
            next.remove(bit)
            if next.rawValue == 0 {
                // 마지막 1개 — 즉시 복원하고 사용자에게 silent revert 신호를 준다.
                sender.state = .on
                return
            }
            current = next
        }
        CapturePreferences.destinations = current
    }

    @objc private func captureFormatChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        switch idx {
        case 0: CapturePreferences.format = .png
        case 1: CapturePreferences.format = .jpeg(quality: CapturePreferences.jpegQuality)
        default: break
        }
    }

    @objc private func captureQualityChanged(_ sender: NSSlider) {
        let value = sender.doubleValue / 100.0
        // 슬라이더는 JPEG일 때만 enabled이지만 방어적으로 한 번 더 확인.
        // jpegQuality 값을 직접 갱신하면 format이 PNG일 때도 다음 JPEG 전환에서 보존된다.
        CapturePreferences.jpegQuality = value
        if case .jpeg = CapturePreferences.format {
            CapturePreferences.format = .jpeg(quality: value)
        }
        captureQualityLabel?.stringValue = "\(Int(value * 100))%"
    }

    @objc private func captureChooseCustomPath() {
        _ = chooseCustomPathInteractive()
    }

    /// 폴더 선택 다이얼로그를 띄우고 결과를 영속화한다. 사용자가 취소하면 false 반환.
    /// CapturePreferences.customPath setter는 검증 실패 silent drop과 "동일 값 silent skip"을
    /// 모두 같은 no-op로 처리하므로, setter 호출 후 값 비교로는 거부 여부를 구분할 수 없다.
    /// 사용자에게 정확한 사유를 알리기 위해 UI에서 같은 검증을 한 번 더 수행해 분기한다.
    @discardableResult
    private func chooseCustomPathInteractive() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose Capture Save Folder"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = CapturePreferences.customPath
            ?? FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists, isDir.boolValue,
              FileManager.default.isWritableFile(atPath: url.path) else {
            presentError(
                title: "Folder not usable",
                message: "The selected folder must exist and be writable. Please choose a different folder."
            )
            return false
        }

        CapturePreferences.customPath = url
        return true
    }

    @objc private func captureClearCustomPath() {
        // 경로를 지우면 .fileCustomPath 비트도 함께 정리한다.
        // 그렇지 않으면 destinations에 .fileCustomPath가 남았는데 customPath가 nil인 모순 상태가 되어
        // 캡처 시점에 출력 대상을 찾지 못하고 silent failure가 발생한다.
        var dests = CapturePreferences.destinations
        if dests.contains(.fileCustomPath) {
            dests.remove(.fileCustomPath)
            if dests.rawValue == 0 { dests.insert(.clipboard) }   // 비어 있을 수 없다
            CapturePreferences.destinations = dests
        }
        CapturePreferences.customPath = nil
    }

    /// 마우스 제스처 인식의 적용 대상 앱 설정 페이지.
    /// (Browsers 섹션은 별도 사이드바 항목으로 분리되었다 — `buildBrowsersBody` 참고)
    private func buildGestureAppsBody() -> NSStackView {
        let result = buildBundleIDFilterPage(
            title: "Apps for Mouse Gestures",
            description: """
            Choose which apps fire mouse gestures.

            • All apps (default): supported browsers only.
            • Whitelist: supported browsers + listed apps (any app type).
            • Blacklist: supported browsers except listed apps.
            """,
            target: .gestureFilter,
            initialMode: GestureAppFilter.mode,
            initialPatterns: GestureAppFilter.patternsText
        )
        gestureFilterControls = result.controls
        return result.view
    }

    /// "Supported Browsers" 페이지 — 카탈로그 브라우저 enable/disable.
    /// 이전엔 Gesture Apps 하단에 끼어있어 정보 밀도가 과다했으나
    /// 별도 사이드바 항목으로 분리해 한 화면 = 한 주제 원칙에 정렬한다.
    /// 두 엔진(Chromium / WebKit)을 각각 카드로 묶어 Common Region 신호를 강화한다.
    private func buildBrowsersBody() -> NSStackView {
        let stack = makePageStack(
            title: "Supported Browsers",
            description:
                "Uncheck a browser to exclude it from auto-detection. " +
                "Disabled browsers behave like any other non-browser app — gestures only fire if you add them to the Whitelist on the Gesture Apps page."
        )

        browserCheckboxes.removeAll()
        stack.addArrangedSubview(makeCard(title: "Chromium engine", content: makeBrowserGrid(.chromium)))
        stack.addArrangedSubview(makeCard(title: "WebKit engine",   content: makeBrowserGrid(.webkit)))
        return stack
    }

    /// 한 엔진의 브라우저 체크박스를 2열 그리드로 배치.
    /// 카드 안에 들어갈 콘텐츠로 설계되어 헤더 라벨은 카드 제목이 담당한다.
    private func makeBrowserGrid(_ engine: BrowserEngine) -> NSGridView {
        let entries = BrowserDetector.catalog.filter { $0.engine == engine }
        let grid = NSGridView()
        grid.rowSpacing = 4
        grid.columnSpacing = 24
        grid.translatesAutoresizingMaskIntoConstraints = false
        for pair in stride(from: 0, to: entries.count, by: 2) {
            let left = makeBrowserCheckbox(entries[pair])
            let right: NSView = (pair + 1 < entries.count)
                ? makeBrowserCheckbox(entries[pair + 1])
                : NSView()
            grid.addRow(with: [left, right])
        }
        return grid
    }

    private func makeBrowserCheckbox(_ entry: BrowserCatalogEntry) -> NSButton {
        let cb = NSButton(
            checkboxWithTitle: entry.displayName,
            target: self,
            action: #selector(browserToggleChanged(_:))
        )
        cb.state = BrowserPreferences.isEnabled(entry.bundleID) ? .on : .off
        cb.toolTip = entry.bundleID
        cb.identifier = NSUserInterfaceItemIdentifier(entry.bundleID)
        browserCheckboxes.append(cb)
        return cb
    }

    @objc private func browserToggleChanged(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        BrowserPreferences.setEnabled(sender.state == .on, for: bundleID)
    }

    private struct BundleFilterPageResult {
        let view: NSStackView
        let controls: BundleFilterControls
    }

    /// Right-click Apps와 Gesture Apps가 공유하는 bundle ID pattern filter 페이지 빌더.
    /// storage는 sender.tag(BundleFilterTarget)로 dispatch한다.
    ///
    /// 레이아웃 우선순위:
    ///   1) Mode 드롭다운 — 어떤 정책을 쓸지가 가장 큰 결정
    ///   2) "Add an app…" prominent 버튼 — GUI 경로(80% 사용자)
    ///   3) Disclosure 토글로 숨겨진 patterns textarea — 코드형 입력은 power-user 영역
    private func buildBundleIDFilterPage(
        title: String,
        description: String,
        target: BundleFilterTarget,
        initialMode: AppFilterMode,
        initialPatterns: String
    ) -> BundleFilterPageResult {
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
        modeRow.addArrangedSubview(modePopup)
        stack.addArrangedSubview(modeRow)

        // Prominent "Add an app…" 행 — 일반 사용자가 쓰는 주 경로.
        let chooseRow = NSStackView()
        chooseRow.orientation = .horizontal
        chooseRow.alignment = .centerY
        chooseRow.spacing = 12

        let chooseLabel = NSTextField(labelWithString: "Add an app:")
        chooseLabel.font = .systemFont(ofSize: 13)
        chooseRow.addArrangedSubview(chooseLabel)

        let chooseAppButton = NSButton(
            title: "Choose App…",
            target: self,
            action: #selector(bundleFilterChooseApp(_:))
        )
        chooseAppButton.bezelStyle = .rounded
        chooseAppButton.tag = target.rawValue
        chooseRow.addArrangedSubview(chooseAppButton)
        stack.addArrangedSubview(chooseRow)

        // 점진적 노출용 disclosure — bundle ID/regex 직접 편집은 advanced 영역에 숨긴다.
        // chevron SF Symbol을 image/alternateImage로 두면 onOff 토글 시 시스템이 자동으로
        // ▶ ↔ ▼ 표시를 바꿔주므로 핸들러는 isHidden 동기화만 책임지면 된다.
        let disclosure = NSButton(
            title: "Advanced patterns",
            target: self,
            action: #selector(toggleBundleFilterAdvanced(_:))
        )
        disclosure.bezelStyle = .recessed
        disclosure.setButtonType(.onOff)
        disclosure.controlSize = .small
        disclosure.tag = target.rawValue
        disclosure.state = .off
        disclosure.imagePosition = .imageLeading
        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        disclosure.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: "show"
        )?.withSymbolConfiguration(chevronConfig)
        disclosure.alternateImage = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: "hide"
        )?.withSymbolConfiguration(chevronConfig)
        stack.addArrangedSubview(disclosure)

        // Advanced 영역 — 기본 접힘. 펼치면 patterns 라벨 + textarea + 예시 도움말 노출.
        let advancedStack = NSStackView()
        advancedStack.orientation = .vertical
        advancedStack.alignment = .leading
        advancedStack.spacing = 8
        advancedStack.translatesAutoresizingMaskIntoConstraints = false
        advancedStack.isHidden = true

        let patternsLabel = NSTextField(labelWithString:
            "Patterns (one per line; prefix with 'regex:' for regular expression):")
        patternsLabel.font = .systemFont(ofSize: 11)
        patternsLabel.textColor = .secondaryLabelColor
        advancedStack.addArrangedSubview(patternsLabel)

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
        advancedStack.addArrangedSubview(scrollView)

        let helpLabel = NSTextField(labelWithString: """
        Examples:
          com.google.Chrome
          com.apple.Safari
          regex:^com\\.google\\..*
          # lines starting with '#' are comments
        """)
        helpLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        helpLabel.textColor = .tertiaryLabelColor
        advancedStack.addArrangedSubview(helpLabel)

        stack.addArrangedSubview(advancedStack)

        let controls = BundleFilterControls(
            modePopup: modePopup,
            textView: textView,
            advancedStack: advancedStack,
            disclosure: disclosure
        )
        return BundleFilterPageResult(view: stack, controls: controls)
    }

    /// disclosure 버튼 토글 핸들러 — sender.tag로 어느 페이지를 토글할지 결정.
    /// chevron 이미지는 NSButton이 alternateImage로 자동 토글하므로 본 핸들러는
    /// advanced 영역의 isHidden 동기화만 담당한다.
    @objc private func toggleBundleFilterAdvanced(_ sender: NSButton) {
        let isOn = (sender.state == .on)
        switch BundleFilterTarget(rawValue: sender.tag) {
        case .appFilter:
            appFilterControls.advancedStack?.isHidden = !isOn
        case .gestureFilter:
            gestureFilterControls.advancedStack?.isHidden = !isOn
        case .none:
            break
        }
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
        BrowserActionPopup.populate(popup, includeDisabled: true)
        BrowserActionPopup.select(GestureMappings.action(for: direction), in: popup)
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        popup.tag = direction.rawValue
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        return popup
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
            // destructive 시각 신호 — Edit과 동일 형태였던 위치를 차별화해
            // 미스 클릭으로 제스처가 사라지는 사고를 줄인다.
            if #available(macOS 12.0, *) {
                removeButton.hasDestructiveAction = true
            }
            removeButton.contentTintColor = .systemRed
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
        NotificationCenter.default.post(name: .customGesturesChanged, object: nil)
    }

    // MARK: - Reset

    /// 사용자 클릭 진입점 — destructive action 보호용 확인 다이얼로그.
    /// 모든 페이지의 설정(매핑·오버레이·커스텀·필터·브라우저)을 한 번에 초기화하므로
    /// 실수 클릭 방지를 위해 명시적 확인을 받는다.
    @objc private func resetToDefaultsRequested() {
        let alert = NSAlert()
        alert.messageText = "Reset all settings to defaults?"
        alert.informativeText = """
        This will erase your custom gestures, gesture mappings, overlay colors, app filters, browser toggles, global shortcut, and capture preferences. This cannot be undone.
        """
        alert.alertStyle = .warning
        let resetBtn = alert.addButton(withTitle: "Reset")
        resetBtn.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        present(alert) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.performResetToDefaults()
            }
        }
    }

    private func performResetToDefaults() {
        GestureMappings.resetToDefaults()
        OverlayPreferences.resetToDefaults()
        CustomGestureMappings.resetAll()
        AppFilter.resetToDefaults()
        GestureAppFilter.resetToDefaults()
        BrowserPreferences.resetToDefaults()
        HotkeyPreferences.resetToDefaults()
        CapturePreferences.resetToDefaults()
        refreshAllControlsFromStorage()
        // Reset은 advanced 패널을 기본(접힘) 상태로 되돌린다. Import는 사용자가 펴둔 상태를 보존한다.
        for controls in [appFilterControls, gestureFilterControls] {
            controls.disclosure?.state = .off
            controls.advancedStack?.isHidden = true
        }
    }

    private func refreshAllControlsFromStorage() {
        for (direction, popup) in popups {
            BrowserActionPopup.select(GestureMappings.action(for: direction), in: popup)
        }
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
        if let idx = AppFilterMode.allCases.firstIndex(of: AppFilter.mode) {
            appFilterControls.modePopup?.selectItem(at: idx)
        }
        appFilterControls.textView?.string = AppFilter.patternsText
        if let idx = AppFilterMode.allCases.firstIndex(of: GestureAppFilter.mode) {
            gestureFilterControls.modePopup?.selectItem(at: idx)
        }
        gestureFilterControls.textView?.string = GestureAppFilter.patternsText
        let disabled = BrowserPreferences.disabledBundleIDs
        for cb in browserCheckboxes {
            if let bundleID = cb.identifier?.rawValue {
                cb.state = disabled.contains(bundleID) ? .off : .on
            }
        }
        refreshCustomList()
        refreshCaptureUI()
    }

    // MARK: - Import / Export

    @objc private func exportConfigRequested() {
        let panel = NSSavePanel()
        panel.title = "Export Configuration"
        panel.nameFieldStringValue = defaultExportFilename()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        present(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.performExport(to: url)
        }
    }

    @objc private func importConfigRequested() {
        let panel = NSOpenPanel()
        panel.title = "Import Configuration"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]

        present(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.confirmAndPerformImport(from: url)
        }
    }

    private func performExport(to url: URL) {
        do {
            try ConfigIO.save(to: url)
        } catch {
            presentError(title: "Export failed", message: errorMessage(error))
        }
    }

    private func confirmAndPerformImport(from url: URL) {
        let snap: ConfigSnapshot
        do {
            snap = try ConfigIO.load(from: url)
        } catch {
            presentError(title: "Import failed", message: errorMessage(error))
            return
        }
        let alert = NSAlert()
        alert.messageText = "Import this configuration?"
        alert.informativeText = """
        Your current settings will be overwritten with the values from the selected file. This cannot be undone.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        present(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            ConfigIO.apply(snap)
            self?.refreshAllControlsFromStorage()
        }
    }

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "gesture-ex-config-\(formatter.string(from: Date())).json"
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        present(alert)
    }

    private func present(_ panel: NSSavePanel,
                         completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func present(_ alert: NSAlert,
                         completion: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        panel.allowedContentTypes = [.application]
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
            appFilterControls.textView?.string = text
        case .gestureFilter:
            GestureAppFilter.patternsText = text
            gestureFilterControls.textView?.string = text
        }
    }

    /// NSTextViewDelegate — 패턴 텍스트가 변경될 때마다 즉시 영속화.
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        if tv === appFilterControls.textView {
            AppFilter.patternsText = tv.string
        } else if tv === gestureFilterControls.textView {
            GestureAppFilter.patternsText = tv.string
        }
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // 녹화 중 닫혔을 때 NSEvent monitor가 영구히 살아 다음 녹화를 깨뜨리는 누수 방지.
        stopRecordingHotkey()
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
