import AppKit

final class GestureToast {
    static let shared = GestureToast()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.display(message)
        }
    }

    private func display(_ message: String) {
        // 직전 Toast가 살아있으면 정리
        hideTimer?.invalidate()
        panel?.orderOut(nil)

        let width: CGFloat = 240
        let height: CGFloat = 56

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true  // 입력 가로채지 않도록

        // 시스템 HUD 스타일 배경 (블러 + 라운드)
        let visualEffect = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: width, height: height)
        )
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.backgroundColor = .clear
        label.frame = NSRect(x: 10, y: 14, width: width - 20, height: 28)
        visualEffect.addSubview(label)

        panel.contentView = visualEffect

        // 화면 상단 중앙에 배치
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: v.midX - width / 2,
                y: v.maxY - height - 100
            ))
        }

        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        })

        self.panel = panel
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            guard let self = self, let p = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                p.animator().alphaValue = 0
            }, completionHandler: {
                p.orderOut(nil)
                if self.panel === p { self.panel = nil }
            })
        }
    }
}

// MARK: - Settings Window (제스처 매핑 커스터마이즈)

/// 4방향 각각에 어떤 BrowserAction을 매핑할지 GUI로 설정한다.
/// 변경은 PopUpButton에서 즉시 UserDefaults에 반영되어 다음 제스처부터 적용된다.
