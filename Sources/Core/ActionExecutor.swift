import CoreGraphics

struct ActionExecutor {
    /// GestureAction을 활성 앱에 전달한다.
    /// 빌트인 BrowserAction이면 미리 정의된 keyCode/flags를, 사용자 단축키면 녹화된 값을 발사한다.
    /// disabled 액션은 noop.
    static func execute(_ action: GestureAction) {
        switch action {
        case .builtin(let browserAction):
            guard let keyCode = browserAction.keyCode else { return }
            postKey(keyCode: keyCode, flags: browserAction.flags)
        case .shortcut(let shortcut):
            postKey(keyCode: CGKeyCode(shortcut.keyCode), flags: shortcut.cgFlags)
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
}

// MARK: - Event Tap Controller

/// HID 레벨 CGEventTap을 관리한다.
/// 1) Chromium 활성 + 드래그 ≥ minDistance + 인식 가능한 방향 → 제스처 액션 실행, 우버튼 이벤트 일체 폐기
/// 2) 그 외 → 원본 down을 up 위치로 옮겨 재발사 (메뉴를 떼는 위치에 띄움)
