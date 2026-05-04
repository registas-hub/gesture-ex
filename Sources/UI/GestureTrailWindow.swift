import AppKit

private final class TrailView: NSView {
    private let glowLayer = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let bezier = NSBezierPath()
    private var lastPoint: NSPoint?

    private let labelBackground: NSView
    private let labelText: NSTextField
    /// 60Hz tick에서 라벨 텍스트가 변하지 않는 동안 stringValue·setFrameOrigin 호출을 건너뛴다.
    private var lastLabelText: String?
    private var lastLabelOrigin: NSPoint?

    /// 마우스 우하단으로의 라벨 오프셋 (마우스 커서 가리지 않도록)
    private static let labelOffset = NSPoint(x: 18, y: -56)
    private static let labelSize = NSSize(width: 170, height: 40)

    override init(frame: NSRect) {
        // 라벨 배경 (단순 NSView + cornerRadius — prefs 색상/투명도 반영 가능)
        labelBackground = NSView(frame: NSRect(origin: .zero, size: Self.labelSize))
        labelBackground.wantsLayer = true
        labelBackground.layer?.cornerRadius = 10
        labelBackground.layer?.masksToBounds = true
        labelBackground.isHidden = true

        // 라벨 텍스트 (색상은 reset() 시 배경 대비로 자동 결정)
        labelText = NSTextField(labelWithString: "")
        labelText.font = .systemFont(ofSize: 16, weight: .semibold)
        labelText.alignment = .center
        labelText.backgroundColor = .clear
        labelText.frame = NSRect(x: 8, y: 8, width: Self.labelSize.width - 16, height: 24)
        labelBackground.addSubview(labelText)

        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(glowLayer)
        layer?.addSublayer(lineLayer)
        addSubview(labelBackground)  // 라벨이 path 위에 그려지도록 마지막에 추가

        glowLayer.fillColor = nil
        glowLayer.lineWidth = 14
        glowLayer.lineCap = .round
        glowLayer.lineJoin = .round

        lineLayer.fillColor = nil
        lineLayer.lineWidth = 5
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round

        applyPreferences()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// OverlayPreferences를 읽어 색상·투명도를 layer/뷰에 적용한다.
    private func applyPreferences() {
        let trailColor = OverlayPreferences.trailColor
        glowLayer.strokeColor = trailColor.withAlphaComponent(0.35).cgColor
        lineLayer.strokeColor = trailColor.cgColor

        let bgColor = OverlayPreferences.backgroundColor
        let opacity = OverlayPreferences.backgroundOpacity
        labelBackground.layer?.backgroundColor = bgColor.withAlphaComponent(CGFloat(opacity)).cgColor
        labelText.textColor = textColorOnBackground(bgColor)
    }

    func reset(start: NSPoint) {
        applyPreferences()  // 매 드래그 시작 시 최신 prefs 반영
        bezier.removeAllPoints()
        bezier.move(to: start)
        lastPoint = start
        applyPath()
        labelBackground.isHidden = true
        lastLabelText = nil
        lastLabelOrigin = nil
    }

    func extend(to point: NSPoint) {
        // 너무 가까운 점은 무시 (smoothing + 성능)
        if let last = lastPoint {
            let dx = point.x - last.x
            let dy = point.y - last.y
            if dx * dx + dy * dy < 4.0 { return }
        }
        bezier.line(to: point)
        lastPoint = point
        applyPath()
    }

    /// 라이브 액션 라벨을 갱신한다.
    /// - Parameters:
    ///   - mouseLocal: 윈도우 로컬 좌표계의 현재 마우스 위치
    ///   - text: 표시할 텍스트. nil이면 라벨 숨김.
    func updateLiveLabel(at mouseLocal: NSPoint, text: String?) {
        // CATransaction으로 위치 변경 시 implicit animation 비활성화 (부드러운 추적)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let text = text else {
            labelBackground.isHidden = true
            lastLabelText = nil
            lastLabelOrigin = nil
            return
        }

        if text != lastLabelText {
            labelText.stringValue = text
            lastLabelText = text
        }

        // 마우스 위치 + 오프셋. 화면 가장자리에서는 자동 flip.
        var origin = NSPoint(
            x: mouseLocal.x + Self.labelOffset.x,
            y: mouseLocal.y + Self.labelOffset.y
        )
        if origin.x + Self.labelSize.width > bounds.maxX {
            origin.x = mouseLocal.x - Self.labelSize.width - Self.labelOffset.x
        }
        if origin.y < bounds.minY {
            origin.y = mouseLocal.y + 24
        }
        if origin != lastLabelOrigin {
            labelBackground.setFrameOrigin(origin)
            lastLabelOrigin = origin
        }
        labelBackground.isHidden = false
    }

    private func applyPath() {
        // CAShapeLayer 갱신 시 implicit animation을 끄면 잔상 없이 즉시 반영
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cg = bezier.asCGPath
        glowLayer.path = cg
        lineLayer.path = cg
        CATransaction.commit()
    }
}

/// 풀스크린 투명 오버레이 윈도우 + 60Hz 마우스 위치 폴링으로 path를 그린다.
/// 입력은 일체 가로채지 않으며(ignoresMouseEvents=true), 단일 인스턴스를 재사용한다.
final class GestureTrailWindow {
    static let shared = GestureTrailWindow()

    private var panel: NSPanel?
    private var trailView: TrailView?
    private var pollTimer: Timer?
    private var totalLength: CGFloat = 0
    private var lastSampledPoint: NSPoint = .zero
    /// 글로벌 좌표(bottom-left)로 보관하는 드래그 시작점 — 라이브 인식의 기준점
    private var startGlobal: NSPoint = .zero
    /// 드래그 중 캡처되는 모든 점들 (CGEvent 좌표, top-left). PathAnalyzer 입력으로 사용.
    private(set) var capturedCGPath: [CGPoint] = []

    /// EventTapController가 mouse-up 시점에 path를 가져갈 수 있는 진입점.
    func currentCGPath() -> [CGPoint] { capturedCGPath }

    /// 거리 누적이 이 값 이상일 때 비로소 화면에 표시 (단순 클릭에서 깜빡임 방지)
    private static let visibilityThreshold: CGFloat = 8.0

    func begin() {
        DispatchQueue.main.async { [weak self] in
            self?.beginInternal()
        }
    }

    func end() {
        DispatchQueue.main.async { [weak self] in
            self?.endInternal()
        }
    }

    private func beginInternal() {
        // 직전 트레일이 살아있으면 즉시 정리
        pollTimer?.invalidate()
        panel?.orderOut(nil)

        // 다중 모니터 합집합 영역 (negative origin 가능)
        let frame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver       // 거의 모든 윈도우 위
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true  // 입력은 일체 가로채지 않음
        panel.alphaValue = 0             // 거리 누적 후 fade-in

        // 윈도우 좌표는 panel.frame 기준 (bottom-left). NSEvent.mouseLocation도 동일 좌표계.
        // panel.frame의 origin이 (예) (-1440, 0)인 경우, 마우스 글로벌 좌표를 윈도우 로컬로 변환 필요.
        let view = TrailView(frame: NSRect(origin: .zero, size: frame.size))
        panel.contentView = view

        let start = NSEvent.mouseLocation
        let local = NSPoint(x: start.x - frame.origin.x, y: start.y - frame.origin.y)
        view.reset(start: local)

        panel.orderFrontRegardless()

        self.panel = panel
        self.trailView = view
        self.totalLength = 0
        self.lastSampledPoint = start
        self.startGlobal = start
        self.capturedCGPath = [GestureRecognizer.nsPointToCG(start)]

        // 60Hz 폴링
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let panel = panel, let view = trailView else { return }
        let global = NSEvent.mouseLocation
        let frame = panel.frame
        let local = NSPoint(x: global.x - frame.origin.x, y: global.y - frame.origin.y)

        let dx = global.x - lastSampledPoint.x
        let dy = global.y - lastSampledPoint.y
        let step = (dx * dx + dy * dy).squareRoot()
        if step >= 1.0 {
            totalLength += step
            lastSampledPoint = global
            view.extend(to: local)
            // 패턴 인식용으로 CGEvent 좌표계 path에 누적
            capturedCGPath.append(GestureRecognizer.nsPointToCG(global))

            // 일정 거리 누적되면 점진적 fade-in
            if panel.alphaValue < 1.0 && totalLength >= Self.visibilityThreshold {
                let alpha = min(1.0, (totalLength - Self.visibilityThreshold) / 12.0 + 0.4)
                panel.alphaValue = alpha
            }
        }

        // ▶ 라이브 액션 라벨: start→current 방향을 매 프레임 재인식
        // 사용자 prefs로 라벨 자체를 끈 경우엔 항상 hidden
        let labelText = OverlayPreferences.showActionLabel
            ? computeLiveLabel(currentGlobal: global)
            : nil
        view.updateLiveLabel(at: local, text: labelText)
    }

    /// 모든 제스처 상태를 라이브 오버레이 라벨로 표현한다 (사용자가 토스트 대신 오버레이만 사용 요청).
    /// 분기 흐름은 EventTapController의 mouse-up 분기와 일치해야 한다.
    /// - 짧은 드래그 (< 20px) → nil (메시지 노이즈 방지)
    /// - Gesture Apps 필터로 차단된 앱 → nil (사용자가 명시적으로 제스처를 끈 영역)
    /// - 화이트리스트 IN: 엔진 체크 건너뛰고 패턴 분석으로 진행
    /// - 비-브라우저 + 화이트리스트 X → "✗ Not browser: <앱명>"
    /// - 패턴 인식 실패 (사선 등) → "✗ Ambiguous"
    /// - 패턴 인식 + 매핑 없음 → "<패턴>  (no mapping)"
    /// - 패턴 인식 + 매핑 disabled → "<패턴>  (disabled)"
    /// - 정상 인식 → "<패턴>  <액션>"
    private func computeLiveLabel(currentGlobal: NSPoint) -> String? {
        // 거리 계산 (CGEvent 좌표계로 변환 후)
        let startCG = GestureRecognizer.nsPointToCG(startGlobal)
        let currentCG = GestureRecognizer.nsPointToCG(currentGlobal)
        let dx = currentCG.x - startCG.x
        let dy = currentCG.y - startCG.y
        let distance = (dx * dx + dy * dy).squareRoot()

        // 짧은 클릭/드래그 — 라벨 노이즈 방지
        if distance < 20 { return nil }

        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier

        // Gesture Apps 필터로 차단된 앱은 EventTapController가 silent cancel 하므로 라벨도 숨긴다.
        guard GestureAppFilter.shouldApply(to: bundleID) else {
            return nil
        }

        // 화이트리스트 IN이 아니라면 엔진 체크가 결정한다.
        let explicitlyAllowed = GestureAppFilter.isExplicitlyAllowed(bundleID: bundleID)
        if !explicitlyAllowed && !EventTapController.shared.gesturesEnabledForFrontmost {
            let name = app?.localizedName ?? "app"
            return "✗ Not browser: \(name)"
        }

        // 패턴 분석 — 실패 시 (사선·모호) 라벨로 사유 표시
        guard let pattern = PathAnalyzer.analyze(path: capturedCGPath) else {
            return "✗ Ambiguous"
        }

        // 매핑 조회 — custom 다중 segment 우선, 단일 방향은 기본 매핑
        let matched: GestureAction?
        if let custom = CustomGestureMappings.match(pattern) {
            matched = custom
        } else if pattern.directions.count == 1 {
            matched = .builtin(GestureMappings.action(for: pattern.directions[0]))
        } else {
            matched = nil
        }

        guard let action = matched else {
            return "\(pattern.displayString)  (no mapping)"
        }
        if action.isDisabled {
            return "\(pattern.displayString)  (disabled)"
        }
        return "\(pattern.displayString)  \(action.label)"
    }

    private func endInternal() {
        pollTimer?.invalidate()
        pollTimer = nil

        guard let panel = panel else { return }

        // 표시될 만큼 그리지도 못한 짧은 클릭은 즉시 숨김
        if panel.alphaValue == 0 {
            panel.orderOut(nil)
            self.panel = nil
            self.trailView = nil
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            // 사용자 설정의 lingering duration: 0.22 ~ 2.0초
            ctx.duration = OverlayPreferences.lingerDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            if self?.panel === panel {
                self?.panel = nil
                self?.trailView = nil
            }
        })
    }
}

// MARK: - Global Hotkey (Carbon RegisterEventHotKey)

/// macOS 글로벌 hotkey를 Carbon API로 등록한다.
/// NSEvent.addGlobalMonitorForEvents와 달리 키 입력을 **가로채서** 다른 앱으로 전파되지 않게 한다.
/// 우리는 ⌥⌘G로 메인 토글(우클릭→mouse-up 변환)을 ON/OFF 한다.
