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

    /// 사용자에게 보여줄 단축키 문자열 (`⌘[`, `⇧⌘R`, `Home` 등).
    /// `disabled`는 키 발사가 없으므로 nil.
    var shortcutLabel: String? {
        guard let code = keyCode else { return nil }
        return flags.modifierSymbols + Self.keyDisplayName(for: code)
    }

    /// popup·메뉴 표시용 라벨 — 인간 친화적 이름 + 단축키.
    /// 단축키 없는 항목은 라벨만.
    var menuTitle: String {
        if let shortcut = shortcutLabel {
            return "\(label)  \(shortcut)"
        }
        return label
    }

    /// CGKeyCode → 사용자에게 익숙한 키 표시 문자.
    /// 매핑 테이블은 keyCode 정의와 1:1로 맞춰야 한다.
    private static func keyDisplayName(for code: CGKeyCode) -> String {
        switch code {
        case 0x21: return "["
        case 0x1E: return "]"
        case 0x0F: return "R"
        case 0x2F: return "."
        case 0x11: return "T"
        case 0x0D: return "W"
        case 0x7C: return "→"
        case 0x7B: return "←"
        case 0x2D: return "N"
        case 0x73: return "Home"
        case 0x77: return "End"
        case 0x03: return "F"
        case 0x18: return "="
        case 0x1B: return "−"
        case 0x1D: return "0"
        default:   return "?"
        }
    }
}

/// 의도적 드래그였으나 제스처 실행으로 이어지지 못한 사유.
/// AppDelegate가 이를 받아 사용자에게 토스트로 표시한다.
