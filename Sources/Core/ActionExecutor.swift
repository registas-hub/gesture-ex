import CoreGraphics

struct ActionExecutor {
    /// 키보드 단축키를 합성해서 활성 앱에 전달한다.
    /// HID tap 위치에 post → 모든 input 처리 레이어를 정상적으로 통과한다.
    /// disabled 액션은 noop.
    static func execute(_ action: BrowserAction) {
        guard let keyCode = action.keyCode else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source,
                                  virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                                virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = action.flags
        up.flags = action.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

// MARK: - Event Tap Controller

/// HID 레벨 CGEventTap을 관리한다.
/// 1) Chromium 활성 + 드래그 ≥ minDistance + 인식 가능한 방향 → 제스처 액션 실행, 우버튼 이벤트 일체 폐기
/// 2) 그 외 → 원본 down을 up 위치로 옮겨 재발사 (메뉴를 떼는 위치에 띄움)
