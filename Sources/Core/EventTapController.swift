import AppKit
import CoreGraphics

final class EventTapController {

    static let shared = EventTapController()

    private static let SYNTHETIC_TAG: Int64 = 0x4332_4F55_5055_5000  // "C2OUPUP\0"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingDown: CGEvent?
    /// down 시점에 AppFilter를 통과했는지 — up에서 같은 결정을 재사용해 일관성 보장.
    private var lastDownPassedFilter: Bool = true

    private(set) var isRunning: Bool = false

    /// 제스처 실행 직후 호출되는 콜백 (UI 스레드에서 호출됨).
    /// 단일 방향이면 `pattern.directions.count == 1`, 다중 segment는 그 이상.
    var onGestureExecuted: ((GesturePattern, GestureAction) -> Void)?

    /// 의도적 드래그(>= 10px)였으나 제스처가 실행되지 못했을 때 호출 (UI 스레드).
    /// 사용자에게 "왜 안 됐는지"를 즉시 알려주는 진단 채널.
    var onGestureSkipped: ((GestureSkipReason) -> Void)?

    /// 우클릭 누른 순간 호출 (UI 스레드). AppDelegate가 트레일 오버레이를 띄운다.
    var onRightDown: (() -> Void)?

    /// 우클릭 뗀 순간 호출 (UI 스레드). 트레일 오버레이를 페이드아웃.
    var onRightUp: (() -> Void)?

    /// 제스처 시도로 간주할 최소 드래그 거리. 이 미만은 단순 클릭으로 분류해
    /// 실패 토스트를 띄우지 않는다(불필요한 노이즈 방지).
    private static let GESTURE_ATTEMPT_THRESHOLD: CGFloat = 10.0

    /// 우클릭 → mouse-up 변환 활성화 여부. 메뉴 토글의 주 상태값.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "rightClickOnUp.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "rightClickOnUp.enabled") }
    }

    /// Chromium 엔진 브라우저(Chrome/Edge/Brave/Arc/...)에서 제스처 활성화 여부 (기본 ON).
    var chromiumGesturesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "gestures.chromium.enabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "gestures.chromium.enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "gestures.chromium.enabled") }
    }

    /// WebKit 엔진 브라우저(Safari/Safari TP/Orion)에서 제스처 활성화 여부 (기본 ON).
    var webkitGesturesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "gestures.webkit.enabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "gestures.webkit.enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "gestures.webkit.enabled") }
    }

    /// 현재 frontmost 앱의 엔진을 기준으로 제스처가 활성인지 통합 판정.
    var gesturesEnabledForFrontmost: Bool {
        switch BrowserDetector.frontmostEngine {
        case "Chromium": return chromiumGesturesEnabled
        case "WebKit":   return webkitGesturesEnabled
        default:         return false
        }
    }

    /// EventTapController가 mouse-up 시점에 호출해 다중 segment 패턴 분석에 사용할 path 공급자.
    /// AppDelegate에서 GestureTrailWindow와 연결한다.
    var pathProvider: (() -> [CGPoint])?

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        self.tap = newTap
        self.runLoopSource = source
        self.isRunning = true
        return true
    }

    func stop() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        self.tap = nil
        self.runLoopSource = nil
        self.pendingDown = nil
        self.isRunning = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // 합성 이벤트는 그대로 통과 (재진입 방지)
        if event.getIntegerValueField(.eventSourceUserData) == Self.SYNTHETIC_TAG {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .rightMouseDown:
            // ── App Filter — 적용 대상이 아니면 변환 없이 그대로 통과 ──
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let shouldApply = AppFilter.shouldApply(to: bundleID)
            lastDownPassedFilter = shouldApply
            if !shouldApply {
                return Unmanaged.passUnretained(event)
            }

            if let copy = event.copy() {
                copy.setIntegerValueField(.eventSourceUserData, value: Self.SYNTHETIC_TAG)
                pendingDown = copy
            }
            // 트레일 오버레이 띄우기
            let downCb = onRightDown
            DispatchQueue.main.async { downCb?() }
            return nil  // 원본 down은 삼킴

        case .rightMouseUp:
            // down 시점에 필터를 통과하지 못했으면 up도 그대로 통과 (일관성 보장)
            if !lastDownPassedFilter {
                return Unmanaged.passUnretained(event)
            }

            // 어떤 분기로 가든 트레일은 마무리한다
            let upCb = onRightUp
            DispatchQueue.main.async { upCb?() }

            guard let down = pendingDown else {
                return Unmanaged.passUnretained(event)
            }
            defer { pendingDown = nil }

            let downLoc = down.location
            let upLoc = event.location
            let dx = upLoc.x - downLoc.x
            let dy = upLoc.y - downLoc.y
            let distance = (dx * dx + dy * dy).squareRoot()

            // 짧은 클릭(< 10px): 제스처 분기 없이 바로 메뉴 띄움
            guard distance >= Self.GESTURE_ATTEMPT_THRESHOLD else {
                down.location = upLoc
                down.post(tap: .cghidEventTap)
                return Unmanaged.passUnretained(event)
            }

            // 의도적 드래그였음 — Gesture Apps 필터 → 엔진 체크 순으로 평가한다.
            // 어느 분기든 드래그 ≥ 10px 단계까지 왔으면 사용자 의도는 "제스처 시도"였으므로
            // 컨텍스트 메뉴는 띄우지 않고 silent cancel 한다 (분기 4/5와 동일 정책).
            let app = NSWorkspace.shared.frontmostApplication
            let bundleID = app?.bundleIdentifier
            guard GestureAppFilter.shouldApply(to: bundleID) else {
                return swallowAndBalance(at: upLoc)
            }
            if !GestureAppFilter.isExplicitlyAllowed(bundleID: bundleID) {
                guard gesturesEnabledForFrontmost else {
                    let cb = onGestureSkipped
                    DispatchQueue.main.async {
                        cb?(.notChromium(bundleID: bundleID, appName: app?.localizedName))
                    }
                    return swallowAndBalance(at: upLoc)
                }
            }

            // ▶ 패턴 인식: 다중 segment 우선, 단일 방향은 fallback
            let path = pathProvider?() ?? [downLoc, upLoc]
            let pattern = PathAnalyzer.analyze(path: path)
                ?? GestureRecognizer.recognize(from: downLoc, to: upLoc)
                    .map { GesturePattern(directions: [$0]) }

            guard let recognizedPattern = pattern else {
                // 의도적 드래그 + 인식 실패 — 사용자는 메뉴를 띄울 의도가 아니었으므로
                // 컨텍스트 메뉴를 띄우지 않고 silent cancel.
                let cb = onGestureSkipped
                DispatchQueue.main.async {
                    cb?(.ambiguousDirection(distance: distance))
                }
                return swallowAndBalance(at: upLoc)
            }

            // ▶ 매칭: custom 다중 segment 우선 → 단일 방향은 GestureMappings
            let matchedAction: GestureAction?
            if let custom = CustomGestureMappings.match(recognizedPattern) {
                matchedAction = custom
            } else if recognizedPattern.directions.count == 1 {
                matchedAction = .builtin(GestureMappings.action(for: recognizedPattern.directions[0]))
            } else {
                matchedAction = nil  // 다중 segment지만 등록 없음
            }

            // 매핑이 아예 없는 경우 (다중 segment 인식했지만 등록 X) → silent cancel
            guard let action = matchedAction else {
                let cb = onGestureSkipped
                DispatchQueue.main.async {
                    cb?(.ambiguousDirection(distance: distance))
                }
                return swallowAndBalance(at: upLoc)
            }

            // 매핑이 .disabled여도 드래그였던 이상 메뉴를 띄우지 않는다.
            // (드래그 = 제스처 시도이므로 우클릭 메뉴 발사는 일관되게 차단)
            if action.isDisabled {
                return swallowAndBalance(at: upLoc)
            }

            ActionExecutor.execute(action)
            let cb = onGestureExecuted
            DispatchQueue.main.async {
                cb?(recognizedPattern, action)
            }
            return swallowAndBalance(at: upLoc)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// 우버튼 down/up을 모두 swallow하는 분기에서 사용. HID tap suppression만으로는
    /// WindowServer/AppKit의 `pressedMouseButtons` 캐시에 right=pressed가 잔존하여
    /// Chromium NSDraggingSession이 후속 좌드래그를 "좌+우 동시 held"로 오인하고
    /// release를 매칭하지 못하는 stuck 버그가 발생한다. 합성 right-up 1발을
    /// SYNTHETIC_TAG로 발사해 캐시를 정상화한다.
    private func swallowAndBalance(at location: CGPoint) -> Unmanaged<CGEvent>? {
        let source = CGEventSource(stateID: .combinedSessionState)
        if let synthUp = CGEvent(mouseEventSource: source,
                                  mouseType: .rightMouseUp,
                                  mouseCursorPosition: location,
                                  mouseButton: .right) {
            synthUp.setIntegerValueField(.eventSourceUserData, value: Self.SYNTHETIC_TAG)
            synthUp.post(tap: .cghidEventTap)
        }
        return nil
    }
}

private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

// MARK: - Gesture Trail Overlay (드래그 경로 시각화)

/// NSBezierPath → CGPath 변환 (macOS 14 미만 호환).
