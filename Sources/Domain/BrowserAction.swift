import CoreGraphics

enum BrowserAction: String, CaseIterable, Codable {
    case disabled
    case back
    case forward
    case reload
    case hardReload
    case stop
    case newTab
    case closeTab
    case reopenTab
    case nextTab
    case prevTab
    case newWindow
    case scrollTop
    case scrollBottom
    case findInPage
    case zoomIn
    case zoomOut
    case resetZoom

    /// 발사할 가상 키코드. nil이면 액션 비활성(disabled).
    var keyCode: CGKeyCode? {
        switch self {
        case .disabled:     return nil
        case .back:         return 0x21  // [
        case .forward:      return 0x1E  // ]
        case .reload:       return 0x0F  // R
        case .hardReload:   return 0x0F  // Shift+R
        case .stop:         return 0x2F  // . (period)
        case .newTab:       return 0x11  // T
        case .closeTab:     return 0x0D  // W
        case .reopenTab:    return 0x11  // Shift+T
        case .nextTab:      return 0x7C  // Right (Cmd+Option+Right)
        case .prevTab:      return 0x7B  // Left  (Cmd+Option+Left)
        case .newWindow:    return 0x2D  // N
        case .scrollTop:    return 0x73  // Home
        case .scrollBottom: return 0x77  // End
        case .findInPage:   return 0x03  // F
        case .zoomIn:       return 0x18  // = (Cmd++)
        case .zoomOut:      return 0x1B  // - (Cmd+-)
        case .resetZoom:    return 0x1D  // 0
        }
    }

    var flags: CGEventFlags {
        switch self {
        case .disabled:
            return []
        case .back, .forward, .reload, .stop, .newTab, .closeTab, .newWindow,
             .findInPage, .zoomIn, .zoomOut, .resetZoom:
            return .maskCommand
        case .hardReload, .reopenTab:
            return [.maskCommand, .maskShift]
        case .nextTab, .prevTab:
            return [.maskCommand, .maskAlternate]
        case .scrollTop, .scrollBottom:
            return []  // Home/End — 보조 키 없이도 페이지 이동
        }
    }

    var label: String {
        switch self {
        case .disabled:     return "— (Disabled)"
        case .back:         return "Back"
        case .forward:      return "Forward"
        case .reload:       return "Reload"
        case .hardReload:   return "Hard Reload"
        case .stop:         return "Stop Loading"
        case .newTab:       return "New Tab"
        case .closeTab:     return "Close Tab"
        case .reopenTab:    return "Reopen Closed Tab"
        case .nextTab:      return "Next Tab"
        case .prevTab:      return "Previous Tab"
        case .newWindow:    return "New Window"
        case .scrollTop:    return "Scroll to Top"
        case .scrollBottom: return "Scroll to Bottom"
        case .findInPage:   return "Find in Page"
        case .zoomIn:       return "Zoom In"
        case .zoomOut:      return "Zoom Out"
        case .resetZoom:    return "Reset Zoom"
        }
    }
}

/// 의도적 드래그였으나 제스처 실행으로 이어지지 못한 사유.
/// AppDelegate가 이를 받아 사용자에게 토스트로 표시한다.
