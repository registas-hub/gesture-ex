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

    /// 첫 실행 자동 알림이 이미 표시됐는지 추적. 사용자가 finishLaunching 직후
    /// hotkey로 toggleEnabled을 빠르게 눌러 동기 alert을 띄운 직후 async 블록이
    /// 같은 alert을 다시 띄우는 race를 막는다.
    private var didShowLaunchPermissionAlert = false

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

        // 첫 실행 시 권한이 하나라도 없으면 자동으로 안내한다.
        // 사용자가 메뉴를 열어 "ON (no permission)"을 발견하기 전에 능동적으로 알림.
        // applyState가 메뉴를 갱신한 직후에 띄워야 메뉴 상태가 일관된다.
        if !PermissionChecker.allGranted {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.didShowLaunchPermissionAlert else { return }
                self.didShowLaunchPermissionAlert = true
                self.showPermissionAlert()
            }
        }
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
        // 번들에 .icns가 있으면 그걸 사용 — About 다이얼로그가 Finder 아이콘과 같은 모양이 된다.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
            return
        }

        // 폴백: SF Symbol
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
        // isEnabled를 코드에서 명시적으로 제어한다. 기본 auto-validation은 target/action이
        // 유효하면 disabled 설정을 다시 켜버려 mouse-up 종속 그레이아웃이 동작하지 않는다.
        menu.autoenablesItems = false

        statusLabelItem = NSMenuItem(title: "—", action: nil, keyEquivalent: "")
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)

        activeAppItem = NSMenuItem(title: "Active: …", action: nil, keyEquivalent: "")
        activeAppItem.isEnabled = false
        menu.addItem(activeAppItem)

        menu.addItem(NSMenuItem.separator())

        // 제스처 섹션 — 토글 ON 시 mouse-up이 자동으로 함께 켜진다.
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

        menu.addItem(NSMenuItem.separator())

        // mouse-up 변환 토글 — 글로벌 hotkey ⌥⌘G로도 토글 가능.
        toggleItem = NSMenuItem(
            title: "Enable right-click on mouse-up",
            action: #selector(toggleEnabled),
            keyEquivalent: "g"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .option]
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        customizeItem = NSMenuItem(
            title: "Open Config…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        customizeItem.keyEquivalentModifierMask = [.command, .shift]
        customizeItem.target = self
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
        let axOK = PermissionChecker.accessibilityGranted
        let imOK = PermissionChecker.inputMonitoringGranted
        let permissionsOK = axOK && imOK

        toggleItem.state = enabled ? .on : .off
        chromiumGesturesItem.state = EventTapController.shared.chromiumGesturesEnabled ? .on : .off
        webkitGesturesItem.state = EventTapController.shared.webkitGesturesEnabled ? .on : .off

        // 브라우저 제스처는 mouse-up이 켜져 있어야만 동작한다. master OFF면 클릭 자체를 막아
        // 시각적으로(회색) 종속 관계를 드러낸다.
        chromiumGesturesItem.isEnabled = enabled
        webkitGesturesItem.isEnabled = enabled
        customizeItem.isEnabled = true

        // 섹션 헤더 — mouse-up OFF / 권한 부족 / 미동작(stopped) 상태를 명시해 inert 상태를 인지시킨다.
        // 헤더와 statusText 모두 동일 신호(permissionsOK)를 우선 평가해 상태 표시 모순을 방지.
        if !enabled {
            gesturesSectionHeader.title = "Browser Gestures (mouse-up off)"
        } else if !permissionsOK {
            gesturesSectionHeader.title = "Browser Gestures (no permission)"
        } else if !running {
            gesturesSectionHeader.title = "Browser Gestures (stopped)"
        } else {
            gesturesSectionHeader.title = "Browser Gestures"
        }

        // Status 라벨 — 권한 미부여 시 두 권한을 ✓/✗로 분리 표시해
        // 사용자가 어느 단계가 남았는지 즉시 파악하도록 한다.
        let statusText: String
        if !enabled {
            statusText = "Status: OFF"
        } else if !permissionsOK {
            let ax = axOK ? "✓" : "✗"
            let im = imOK ? "✓" : "✗"
            statusText = "Permissions: Accessibility \(ax) · Input Monitoring \(im)"
        } else if running {
            statusText = "Status: ON ✓"
        } else {
            statusText = "Status: ON (stopped)"
        }
        statusLabelItem.title = statusText

        if let button = statusItem.button {
            // 3가지 시각 상태:
            //   - 권한 부재(빨강 경고): 사용자가 즉시 인지해야 할 blocker
            //   - master OFF(회색 outline): 사용자가 의도적으로 끔
            //   - 정상 동작(filled): 모든 조건 충족
            let symbolName: String
            let tint: NSColor?
            if enabled && !permissionsOK {
                symbolName = "exclamationmark.triangle.fill"
                tint = .systemRed
            } else if enabled && running {
                symbolName = "cursorarrow.click.2"
                tint = nil
            } else {
                symbolName = "cursorarrow.click"
                tint = nil
            }
            if let img = NSImage(systemSymbolName: symbolName,
                                  accessibilityDescription: "right-click on up") {
                // tint를 적용하려면 isTemplate=false (template은 색이 시스템에 의해 강제됨)
                img.isTemplate = (tint == nil)
                button.image = img
                button.title = ""
                button.contentTintColor = tint
            } else {
                button.image = nil
                button.title = (enabled && running) ? "●" : "○"
                button.contentTintColor = tint
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
        let willEnable = !EventTapController.shared.chromiumGesturesEnabled
        EventTapController.shared.chromiumGesturesEnabled = willEnable
        ensureMouseUpEnabledIfNeeded(turningOn: willEnable)
    }

    @objc private func toggleWebkitGestures() {
        let willEnable = !EventTapController.shared.webkitGesturesEnabled
        EventTapController.shared.webkitGesturesEnabled = willEnable
        ensureMouseUpEnabledIfNeeded(turningOn: willEnable)
    }

    /// 브라우저 제스처를 켤 때 mouse-up이 꺼져 있거나 tap이 동작 중이 아니면 활성화한다.
    /// 권한 부족 등으로 start()가 실패하면 *자동 활성화*한 isEnabled는 롤백한다 —
    /// 사용자가 명시적으로 켠 게 아닌 master 상태가 영속되는 부작용을 방지하기 위함.
    private func ensureMouseUpEnabledIfNeeded(turningOn: Bool) {
        defer { updateMenuStateUI() }
        let ctrl = EventTapController.shared
        guard turningOn else { return }
        if ctrl.isEnabled && ctrl.isRunning { return }

        let didAutoEnable = !ctrl.isEnabled
        if didAutoEnable {
            ctrl.isEnabled = true
        }
        if !ctrl.start() {
            if didAutoEnable {
                ctrl.isEnabled = false
            }
            showPermissionAlert()
        }
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
        // PrivacyPane.accessibility.url로 위임해 URL 단일 소스 유지.
        openPrivacyPane(.accessibility)
    }

    @objc private func showAbout() {
        // macOS 표준 About 패널 — 다른 앱과 일관된 룩(아이콘·이름·버전·copyright)을
        // 자동으로 채우고, credits만 우리가 주입한다.
        let credits = NSAttributedString(
            string: """
            Right-click on mouse-up + browser mouse gestures
            for Chromium and WebKit.

            ⌥⌘G  toggle on/off
            ⇧⌘,  open Settings
            """,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.credits: credits,
        ])
    }

    private func showPermissionAlert() {
        let axOK = PermissionChecker.accessibilityGranted
        let imOK = PermissionChecker.inputMonitoringGranted
        let ax = axOK ? "✓" : "✗"
        let im = imOK ? "✓" : "✗"

        // 두 권한이 모두 부여된 경우엔 알릴 게 없다 (이중 호출 방지).
        if axOK && imOK { return }

        let granted = (axOK ? 1 : 0) + (imOK ? 1 : 0)

        let alert = NSAlert()
        alert.messageText = "Permissions required (\(granted)/2 granted)"
        alert.informativeText = """
        gesture-ex needs both permissions to convert right-clicks and read mouse drags.

          \(ax)  Accessibility
          \(im)  Input Monitoring

        Open Privacy & Security to grant the missing one.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: axOK ? "Open Input Monitoring" : "Open Accessibility")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            // 부족한 첫 번째 권한 페인으로 직접 이동한다.
            if !axOK {
                openPrivacyPane(.accessibility)
            } else {
                openPrivacyPane(.inputMonitoring)
            }
        }
    }

    private enum PrivacyPane {
        case accessibility
        case inputMonitoring

        var url: URL? {
            switch self {
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            case .inputMonitoring:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
            }
        }
    }

    private func openPrivacyPane(_ pane: PrivacyPane) {
        if let url = pane.url {
            NSWorkspace.shared.open(url)
        }
    }
}
