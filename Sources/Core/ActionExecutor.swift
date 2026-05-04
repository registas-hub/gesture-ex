import AppKit
import CoreGraphics

struct ActionExecutor {
    /// GestureAction을 활성 앱에 전달한다.
    /// 빌트인 disabled / 빌트인 액션은 키스트로크, 사용자 단축키도 키스트로크,
    /// 마우스 액션은 휠 또는 버튼 이벤트로 합성한다. keyCode가 nil인 disabled는 noop.
    static func execute(_ action: GestureAction) {
        switch action {
        case .builtin(let browserAction):
            guard let keyCode = browserAction.keyCode else { return }
            postKey(keyCode: keyCode, flags: browserAction.flags)
        case .shortcut(let shortcut):
            postKey(keyCode: CGKeyCode(shortcut.keyCode), flags: shortcut.cgFlags)
        case .mouse(let mouseAction):
            postMouse(mouseAction)
        }
    }

    /// HID tap 위치에 post → 모든 input 처리 레이어를 정상적으로 통과한다.
    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source,
                                  virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                                virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postMouse(_ action: MouseAction) {
        let source = CGEventSource(stateID: .combinedSessionState)
        switch action {
        case .scroll(let direction, let lines):
            postScroll(source: source, direction: direction, lines: lines)
        case .middleClick:
            postMiddleClick(source: source)
        }
    }

    /// 휠 이벤트는 line 단위로 합성한다.
    /// wheel1=세로(양수=위), wheel2=가로(양수=오른쪽). 사용자가 입력한 lines는 항상 양수,
    /// down/left일 때만 부호를 뒤집어 보낸다.
    private static func postScroll(source: CGEventSource?,
                                    direction: MouseScrollDirection,
                                    lines: Int) {
        let magnitude = Int32(max(1, lines))
        let signed: Int32
        switch direction {
        case .up, .right:    signed = magnitude
        case .down, .left:   signed = -magnitude
        }
        let event: CGEvent?
        if direction.isHorizontal {
            event = CGEvent(scrollWheelEvent2Source: source,
                            units: .line,
                            wheelCount: 2,
                            wheel1: 0, wheel2: signed, wheel3: 0)
        } else {
            event = CGEvent(scrollWheelEvent2Source: source,
                            units: .line,
                            wheelCount: 1,
                            wheel1: signed, wheel2: 0, wheel3: 0)
        }
        event?.post(tap: .cghidEventTap)
    }

    /// 휠 버튼 클릭. 종료 좌표(현재 마우스 위치)에 down/up 한 쌍을 발사한다.
    private static func postMiddleClick(source: CGEventSource?) {
        let cgPoint = GestureRecognizer.nsPointToCG(NSEvent.mouseLocation)

        guard let down = CGEvent(mouseEventSource: source,
                                  mouseType: .otherMouseDown,
                                  mouseCursorPosition: cgPoint,
                                  mouseButton: .center),
              let up = CGEvent(mouseEventSource: source,
                                mouseType: .otherMouseUp,
                                mouseCursorPosition: cgPoint,
                                mouseButton: .center) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

// MARK: - Event Tap Controller

/// HID 레벨 CGEventTap을 관리한다.
/// 1) Chromium 활성 + 드래그 ≥ minDistance + 인식 가능한 방향 → 제스처 액션 실행, 우버튼 이벤트 일체 폐기
/// 2) 그 외 → 원본 down을 up 위치로 옮겨 재발사 (메뉴를 떼는 위치에 띄움)
