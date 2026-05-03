import AppKit
import ServiceManagement
import Carbon.HIToolbox  // kVK_ANSI_G, cmdKey, optionKey 상수 (글로벌 hotkey 등록)

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var statusLabelItem: NSMenuItem!
    private var activeAppItem: NSMenuItem!
    private var chromiumGesturesItem: NSMenuItem!
    private var webkitGesturesItem: NSMenuItem!
    private var customizeItem: NSMenuItem!
    private var gesturesSectionHeader: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupAppIcon()

        if UserDefaults.standard.object(forKey: "rightClickOnUp.enabled") == nil {
            EventTapController.shared.isEnabled = true
        }

        // 후행 토스트는 모두 제거 — 모든 메시지(성공/실패/사유)는 라이브 오버레이에 표시한다.
        // GestureToast 클래스는 향후 다른 용도로 쓸 수 있어 보존.

        // 글로벌 hotkey ⌥⌘G — 어디서나 mouse-up 변환 토글
        HotkeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak self] in
            self?.toggleEnabled()
        }

        // 우클릭 down/up 시점에 화면 트레일 오버레이 표시 / 숨김
        EventTapController.shared.onRightDown = {
            GestureTrailWindow.shared.begin()
        }
        EventTapController.shared.onRightUp = {
            GestureTrailWindow.shared.end()
        }

        // 패턴 인식용 path 공급자 — GestureTrailWindow가 polling으로 캡처한 path를 제공
        EventTapController.shared.pathProvider = {
            GestureTrailWindow.shared.currentCGPath()
        }

        buildStatusItem()
        applyState(showAlertOnFailure: false)
    }

    // MARK: - NSMenuDelegate

    /// 메뉴가 열리기 직전에 frontmost 앱 정보를 갱신한다.
    /// status bar 메뉴는 표시 시점에 우리 앱을 frontmost로 활성화하지 않으므로,
    /// 여기서 본 frontmost는 사용자가 마지막으로 작업하던 앱(예: Chrome)이다.
    func menuWillOpen(_ menu: NSMenu) {
        let app = NSWorkspace.shared.frontmostApplication
        let name = app?.localizedName ?? "(unknown)"
        let bid = app?.bundleIdentifier ?? "(unknown)"
        let mark: String
        if let engine = BrowserDetector.frontmostEngine {
            mark = "\(engine) ✓"
        } else {
            mark = "Not in list ✗"
        }
        activeAppItem.title = "Active: \(name) — \(mark)"
        activeAppItem.toolTip = "Bundle ID: \(bid)"
        updateMenuStateUI()
    }

    private func setupAppIcon() {
        guard let symbol = NSImage(
            systemSymbolName: "cursorarrow.click.2",
            accessibilityDescription: "right-click on up"
        ) else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 128, weight: .regular)
        let icon = symbol.withSymbolConfiguration(config) ?? symbol
        icon.isTemplate = false
        NSApp.applicationIconImage = icon
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self  // menuWillOpen 호출되도록

        statusLabelItem = NSMenuItem(title: "—", action: nil, keyEquivalent: "")
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)

        activeAppItem = NSMenuItem(title: "Active: …", action: nil, keyEquivalent: "")
        activeAppItem.isEnabled = false
        menu.addItem(activeAppItem)

        menu.addItem(NSMenuItem.separator())

        // 메인 토글 — 모든 기능의 전제 조건. 글로벌 hotkey ⌥⌘G로도 토글 가능.
        toggleItem = NSMenuItem(
            title: "Enable right-click on mouse-up",
            action: #selector(toggleEnabled),
            keyEquivalent: "g"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .option]
        toggleItem.target = self
        menu.addItem(toggleItem)

        // 제스처 섹션 (mouse-up 의존) — 시각적으로 분리·indent로 위계 표현
        gesturesSectionHeader = NSMenuItem(title: "Browser Gestures",
                                            action: nil, keyEquivalent: "")
        gesturesSectionHeader.isEnabled = false
        menu.addItem(gesturesSectionHeader)

        chromiumGesturesItem = NSMenuItem(
            title: "Chromium (Chrome / Edge / Brave / Arc / …)",
            action: #selector(toggleChromiumGestures),
            keyEquivalent: ""
        )
        chromiumGesturesItem.target = self
        chromiumGesturesItem.indentationLevel = 1
        menu.addItem(chromiumGesturesItem)

        webkitGesturesItem = NSMenuItem(
            title: "WebKit (Safari / Safari TP / Orion)",
            action: #selector(toggleWebkitGestures),
            keyEquivalent: ""
        )
        webkitGesturesItem.target = self
        webkitGesturesItem.indentationLevel = 1
        menu.addItem(webkitGesturesItem)

        customizeItem = NSMenuItem(
            title: "Customize Gestures…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        customizeItem.keyEquivalentModifierMask = [.command, .shift]
        customizeItem.target = self
        customizeItem.indentationLevel = 1
        menu.addItem(customizeItem)

        menu.addItem(NSMenuItem.separator())

        launchAtLoginItem = NSMenuItem(
            title: "Launch at login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        let openSettingsItem = NSMenuItem(
            title: "Open Privacy Settings…",
            action: #selector(openPrivacySettings),
            keyEquivalent: ""
        )
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)

        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu

        updateMenuStateUI()
    }

    private func updateMenuStateUI() {
        let enabled = EventTapController.shared.isEnabled
        let running = EventTapController.shared.isRunning

        toggleItem.state = enabled ? .on : .off
        chromiumGesturesItem.state = EventTapController.shared.chromiumGesturesEnabled ? .on : .off
        webkitGesturesItem.state = EventTapController.shared.webkitGesturesEnabled ? .on : .off

        // 제스처 설정은 mouse-up 변환이 ON일 때만 의미가 있다 (기능 의존성).
        // OFF면 위계상 하위인 제스처 항목들을 비활성화해 사용자 혼란 방지.
        let gesturesAvailable = enabled && running
        chromiumGesturesItem.isEnabled = gesturesAvailable
        webkitGesturesItem.isEnabled = gesturesAvailable
        customizeItem.isEnabled = gesturesAvailable

        // 섹션 헤더 — 의존성 상태에 따라 라벨에 hint 부착
        if !enabled {
            gesturesSectionHeader.title = "Browser Gestures (enable above first)"
        } else if !running {
            gesturesSectionHeader.title = "Browser Gestures (no permission)"
        } else {
            gesturesSectionHeader.title = "Browser Gestures"
        }

        let statusText: String
        if !enabled {
            statusText = "Status: OFF"
        } else if running {
            statusText = "Status: ON ✓"
        } else {
            statusText = "Status: ON (no permission)"
        }
        statusLabelItem.title = statusText

        if let button = statusItem.button {
            let symbolName = (enabled && running) ? "cursorarrow.click.2" : "cursorarrow.click"
            if let img = NSImage(systemSymbolName: symbolName,
                                  accessibilityDescription: "right-click on up") {
                img.isTemplate = true
                button.image = img
                button.title = ""
            } else {
                button.image = nil
                button.title = (enabled && running) ? "●" : "○"
            }
        }

        if #available(macOS 13.0, *) {
            launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            launchAtLoginItem.isEnabled = true
        } else {
            launchAtLoginItem.isEnabled = false
            launchAtLoginItem.title = "Launch at login (requires macOS 13+)"
        }
    }

    private func applyState(showAlertOnFailure: Bool) {
        if EventTapController.shared.isEnabled {
            let ok = EventTapController.shared.start()
            if !ok && showAlertOnFailure {
                showPermissionAlert()
            }
        } else {
            EventTapController.shared.stop()
        }
        updateMenuStateUI()
    }

    @objc private func toggleEnabled() {
        EventTapController.shared.isEnabled.toggle()
        applyState(showAlertOnFailure: true)
    }

    @objc private func toggleChromiumGestures() {
        EventTapController.shared.chromiumGesturesEnabled.toggle()
        updateMenuStateUI()
    }

    @objc private func toggleWebkitGestures() {
        EventTapController.shared.webkitGesturesEnabled.toggle()
        updateMenuStateUI()
    }

    @objc private func showSettings() {
        SettingsWindow.shared.show()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at login 설정 실패"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        updateMenuStateUI()
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "gesture-ex"
        alert.informativeText = """
        macOS 우클릭을 마우스 떼는 시점(mouse-up)에 발사하도록 변환합니다.

        Chromium 계열(Chrome / Edge / Brave / Arc / Whale / Vivaldi / Opera 등) 및
        WebKit 계열(Safari / Safari TP / Orion) 브라우저에서 4방향 + 사용자 정의 다중 segment
        마우스 제스처를 지원합니다. 매핑은 Customize Gestures…(⇧⌘,)에서 변경 가능.

        Global hotkey: ⌥⌘G — anywhere to toggle on/off
        HID 이벤트 탭 사용. 필요 권한: Accessibility + Input Monitoring.
        """
        alert.runModal()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "권한이 필요합니다"
        alert.informativeText = """
        다음 두 권한을 모두 부여해주세요:

        • System Settings → Privacy & Security → Accessibility
        • System Settings → Privacy & Security → Input Monitoring

        부여 후 메뉴에서 토글을 다시 켜면 적용됩니다.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openPrivacySettings()
        }
    }
}
