import AppKit
import CoreGraphics

/// 사용자가 직접 녹화한 키보드 단축키.
/// 재발사에 필요한 keyCode/flags 외에 표시용 displayKey 문자도 함께 저장한다.
struct KeyShortcut: Codable, Hashable {
    let keyCode: UInt16
    /// CGEventFlags.rawValue. CGEventFlags는 OptionSet이라 직접 Codable이 아니므로 raw로 보관.
    let cgFlagsRaw: UInt64
    /// UI 표시용 키 이름 (예: "A", "Tab", "F12"). 녹화 시점에 결정해 영속화.
    let displayKey: String

    init(keyCode: UInt16, cgFlags: CGEventFlags, displayKey: String) {
        self.keyCode = keyCode
        self.cgFlagsRaw = cgFlags.rawValue
        self.displayKey = displayKey
    }

    var cgFlags: CGEventFlags { CGEventFlags(rawValue: cgFlagsRaw) }

    /// "⇧⌘A" 형태의 사용자 표시 문자열.
    var displayString: String {
        var modifiers = ""
        let f = cgFlags
        if f.contains(.maskControl)   { modifiers += "⌃" }
        if f.contains(.maskAlternate) { modifiers += "⌥" }
        if f.contains(.maskShift)     { modifiers += "⇧" }
        if f.contains(.maskCommand)   { modifiers += "⌘" }
        return modifiers + displayKey
    }

    /// NSEvent.keyDown으로부터 KeyShortcut을 만든다. modifier-only 입력은 nil.
    static func from(event: NSEvent) -> KeyShortcut? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cgFlags = Self.toCGFlags(mods)
        let keyCode = event.keyCode

        if let name = Self.specialKeyName(for: keyCode) {
            return KeyShortcut(keyCode: keyCode, cgFlags: cgFlags, displayKey: name)
        }

        // modifier 떼고 본 글자(예: ⇧+a → "A")가 있으면 사용. 없거나 비표시 가능 문자만 있으면 무효.
        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        let trimmed = chars.unicodeScalars.first.flatMap { scalar -> String? in
            scalar.value >= 0x20 ? String(scalar) : nil
        }
        guard let displayKey = trimmed, !displayKey.isEmpty else { return nil }
        return KeyShortcut(keyCode: keyCode, cgFlags: cgFlags, displayKey: displayKey)
    }

    private static func toCGFlags(_ mods: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if mods.contains(.command) { f.insert(.maskCommand) }
        if mods.contains(.shift)   { f.insert(.maskShift) }
        if mods.contains(.option)  { f.insert(.maskAlternate) }
        if mods.contains(.control) { f.insert(.maskControl) }
        return f
    }

    /// 표시 가능한 특수 키 이름. 매핑에 없는 keyCode는 charactersIgnoringModifiers로 fallback.
    private static func specialKeyName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 0x24: return "Return"
        case 0x4C: return "Enter"
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x33: return "Delete"
        case 0x35: return "Esc"
        case 0x75: return "Fwd Del"
        case 0x73: return "Home"
        case 0x77: return "End"
        case 0x74: return "Page Up"
        case 0x79: return "Page Down"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default: return nil
        }
    }
}
